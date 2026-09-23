import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/blocking_progress.dart';
import '../../../tuya/tuya_models.dart';
import 'device_online_guard.dart';
import 'widgets/device_plant_artwork.dart';

class DeviceInfoPage extends StatelessWidget {
  const DeviceInfoPage({required this.deviceId, super.key, this.info});

  final String deviceId;
  final DeviceInfoData? info;

  Future<void> _rename(BuildContext context, SmartPlanterDevice device) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => RenameDeviceDialog(initialName: device.name),
    );
    if (name == null || !context.mounted) return;
    final state = FlowerpotScope.of(context);
    // 改名走云端，点两次会提交两回。
    final result = await withBlockingProgress(
      context,
      () => state.renameDevice(device.id, name),
    );
    if (result != null && context.mounted) {
      showDeviceActionResult(context, result, announceSuccess: true);
    }
  }

  /// 联调用：把 DP 162 `plant_confirm` 当前上报的值弹出来。
  ///
  /// 直接用系统的 `AlertDialog`，不走 App 自己的提示组件——这里要的是"原样看到设备报了
  /// 什么"，越少加工越好。同时把 DP 116 一起列出来：162 是跟着 116 走的（下发 116 之后
  /// 固件会把 162 改回 0 并立即上报），单看 162 判断不了是不是正常。
  ///
  /// `plantConfirmRaw` 是上报的**原文**；`plantConfirm` 是 App 解析后的结论
  /// （`fromDp` 只认明确的 1，其它一律当 0），两者都显示才看得出解析有没有偏差。
  /// 联调诊断串：**植物与电池两组 DP 的原值、解析结果、以及匹配到了谁**。
  ///
  /// 2026-09-11 产品要的三件事都靠它回答：
  ///
  /// 1. 「固件固定上报的植物 ID 是多少」——看 `DP 116 上报原值`，那个值就是要填到后台
  ///    植物的**涂鸦标识**字段里的；
  /// 2. 「上报的 ID 后端存不存在」——看 `目录匹配`。**匹配不上就按无植物处理**，
  ///    这一行直接说破是哪一种，不用再猜是没上报还是没配；
  /// 3. 「电池数据为空，DP 有没有正常上来」——看电池那一组的原值。
  ///
  /// 用 `SelectableText`：这一段是要复制出去发给后端/固件的。
  static String _dpDiagnostics(BuildContext context, SmartPlanterDevice device) {
    final state = FlowerpotScope.of(context);
    final reported = device.plantVariety;
    final matched = state.reportedPlantName(device.id);
    return <String>[
      '【植物】',
      'DP 116 plant_variety 上报原值：'
          '${reported.isEmpty ? '（未上报过）' : reported}',
      '解析成 id：${PlantVariety.parse(reported) ?? '（不是数字，按字符串标识符处理）'}',
      // 匹配用的是**后台的涂鸦标识**（tuYaRemark），不是植物自增 id。
      '目录匹配：${matched == null || matched.isEmpty ? '未匹配到（后台没有这个涂鸦标识 ⇒ 按无植物显示）' : matched}',
      'DP 162 plant_confirm 上报原值：'
          '${device.plantConfirmRaw.isEmpty ? '（未上报过）' : device.plantConfirmRaw}',
      'DP 162 解析：${device.plantConfirm.name}'
          '（${device.plantConfirm.dpValue}，true 才弹引导窗）',
      '',
      '【电池】',
      'DP 103 battery_level：${device.battery}%',
      'DP 104/145 充电中：${device.charging}',
      '⚠️ 电池**没有历史 DP**（历史只有 131–139 水位/土壤湿度/光照，'
          '加 164/165 空气温度/湿度的日历史），',
      '所以报表里的电池曲线永远为空——要曲线需要设备侧新增历史 DP。',
      '',
      '【设备】',
      '名称：${device.name}',
      'devId：${device.id}',
    ].join('\n');
  }

  Future<void> _showPlantConfirmDp(
    BuildContext context,
    SmartPlanterDevice device,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('device-info-dp162-dialog'),
        title: const Text('DP 诊断'),
        content: SingleChildScrollView(
          child: SelectableText(_dpDiagnostics(context, device)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '更多设备信息', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final details = info ?? DeviceInfoData.fromDevice(device);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '更多设备信息', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        key: const Key('device-info-scroll-view'),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                37,
                AppSpacing.pageMargin,
                28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _DeviceInfoHero(
                    device: device,
                    onRename: () => _rename(context, device),
                  ),
                  const SizedBox(height: 16),
                  const _InformationSectionTitle(label: '软件'),
                  const SizedBox(height: 10),
                  _InformationCard(
                    rows: <_InformationRowData>[
                      _InformationRowData(
                        label: 'APP版本',
                        value: details.appVersion,
                      ),
                      _InformationRowData(
                        label: '固件版本',
                        value: details.firmwareVersion,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _InformationSectionTitle(label: '硬件'),
                  const SizedBox(height: 10),
                  _InformationCard(
                    rows: <_InformationRowData>[
                      _InformationRowData(label: 'MAC', value: details.mac),
                      _InformationRowData(
                        label: '硬件版本',
                        value: details.hardwareVersion,
                      ),
                      _InformationRowData(
                        label: '设备devId',
                        value: details.deviceDevId,
                      ),
                      _InformationRowData(
                        label: '设备UUID',
                        value: details.deviceUuid,
                      ),
                      _InformationRowData(
                        label: '花托UUID',
                        value: details.planterUuid,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // 联调用：把 DP 162 当前上报的值原样弹出来核对。
                  OutlinedButton(
                    key: const Key('device-info-dp162-probe'),
                    onPressed: () => _showPlantConfirmDp(context, device),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: AppColors.brandPrimary,
                      side: const BorderSide(color: AppColors.brandPrimary),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('查看 DP 162（plant_confirm）'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 改设备名的弹框。花盆设备信息页和割草机设备参数页共用（2026-09-23 起割草机也用它）。
class RenameDeviceDialog extends StatefulWidget {
  const RenameDeviceDialog({required this.initialName, super.key});

  final String initialName;

  @override
  State<RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<RenameDeviceDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: '编辑设备名称',
      message: '最多 20 个字符，重命名后设备列表与首页同步更新。',
      icon: Icons.drive_file_rename_outline,
      confirmLabel: '保存',
      confirmKey: const Key('save-device-info-name'),
      content: AppDialogTextField(
        key: const Key('device-info-name-field'),
        controller: _controller,
        hintText: '请输入设备名称',
        maxLength: 20,
      ),
      onCancel: () => Navigator.pop(context),
      onConfirm: () => Navigator.pop(context, _controller.text),
    );
  }
}

class DeviceInfoData {
  const DeviceInfoData({
    required this.appVersion,
    required this.firmwareVersion,
    required this.mac,
    required this.hardwareVersion,
    required this.deviceDevId,
    required this.deviceUuid,
    required this.planterUuid,
  });

  factory DeviceInfoData.fromDevice(SmartPlanterDevice device) {
    final compactId = device.id.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    return DeviceInfoData(
      appVersion: '1.0.0',
      firmwareVersion: device.firmwareVersion,
      mac: device.macAddress.replaceAll(':', ''),
      // `hardware_version` (DP 149).
      hardwareVersion: device.hardwareVersion,
      deviceDevId: device.id,
      deviceUuid: 'uuid$compactId',
      planterUuid: device.productId,
    );
  }

  final String appVersion;
  final String firmwareVersion;
  final String mac;
  final String hardwareVersion;
  final String deviceDevId;
  final String deviceUuid;
  final String planterUuid;
}

class _DeviceInfoHero extends StatelessWidget {
  const _DeviceInfoHero({required this.device, required this.onRename});

  final SmartPlanterDevice device;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
      ),
      child: SizedBox(
        height: 110,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 76,
                child: Center(
                  child: DevicePlantArtwork(deviceId: device.id, width: 62),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          key: const Key('rename-device-info-button'),
                          tooltip: '编辑设备名称',
                          onPressed: onRename,
                          visualDensity: VisualDensity.compact,
                          icon: Image.asset(
                            AppAssets.editIcon,
                            width: 22,
                            height: 22,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ],
                    ),
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        color: AppColors.brandSurface,
                        borderRadius: AppRadius.full,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        child: Text(
                          '已陪伴${device.companionDays}天',
                          style: const TextStyle(
                            color: AppColors.brandPrimary,
                            fontSize: 14,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InformationSectionTitle extends StatelessWidget {
  const _InformationSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 4,
          height: 18,
          child: ColoredBox(color: AppColors.brandPrimary),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _InformationRowData {
  const _InformationRowData({required this.label, required this.value});

  final String label;
  final String value;
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({required this.rows});

  final List<_InformationRowData> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          children: <Widget>[
            for (final row in rows)
              SizedBox(
                height: 39,
                child: Row(
                  children: <Widget>[
                    Text(
                      row.label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        row.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
