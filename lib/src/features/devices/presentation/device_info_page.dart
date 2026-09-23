import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/blocking_progress.dart';
import '../../../tuya/tuya_models.dart';
import '../../mower/mower_ui.dart';
import 'device_online_guard.dart';
import 'widgets/device_plant_artwork.dart';

/// 更多设备信息。花盆设备设置页、割草机设置页「设备参数」都进这一页（2026-09-23 产品：
/// 割草机「完全按那边的 UI 和页面名称写」）。
///
/// 内容（2026-09-23 产品定稿，全部是真数据，没有就空着）：
/// - 头部：产品图 + 昵称（可改名，同一个 [RenameDeviceDialog]）；
/// - 软件：固件版本；
/// - 硬件：设备型号（**涂鸦产品名称**，不是昵称，只读）、设备devId、mac地址（仅割草机）、硬件版本。
///
/// 去掉的：APP版本、MAC（花盆）、设备UUID、花托UUID——其中 APP版本 / 两个 UUID 原来是凑出来的值。
class DeviceInfoPage extends StatefulWidget {
  const DeviceInfoPage({required this.deviceId, super.key, this.info});

  final String deviceId;
  final DeviceInfoData? info;

  @override
  State<DeviceInfoPage> createState() => _DeviceInfoPageState();
}

class _DeviceInfoPageState extends State<DeviceInfoPage> {
  String get deviceId => widget.deviceId;

  /// 涂鸦产品名称（「设备型号」）。进页面问一次，[FlowerpotState.productNameFor] 里有缓存。
  Future<String?>? _productName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.info == null) {
      _productName ??= FlowerpotScope.of(context).productNameFor(deviceId);
    }
  }

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

  List<Widget> _sections(DeviceInfoData details) => <Widget>[
    const SizedBox(height: 16),
    const _InformationSectionTitle(label: '软件'),
    const SizedBox(height: 10),
    _InformationCard(
      rows: <_InformationRowData>[
        _InformationRowData(label: '固件版本', value: details.firmwareVersion),
      ],
    ),
    const SizedBox(height: 16),
    const _InformationSectionTitle(label: '硬件'),
    const SizedBox(height: 10),
    _InformationCard(
      rows: <_InformationRowData>[
        _InformationRowData(label: '设备型号', value: details.model),
        _InformationRowData(label: '设备devId', value: details.deviceDevId),
        // 只有割草机有这一行（产品：「对比割草机少一个 mac 地址」）。
        if (details.mac != null)
          _InformationRowData(label: 'mac地址', value: details.mac!),
        _InformationRowData(label: '硬件版本', value: details.hardwareVersion),
      ],
    ),
  ];

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
    final state = FlowerpotScope.of(context);
    final device = state.deviceById(deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '更多设备信息', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final mower = state.isMowerDevice(device);
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
                    mower: mower,
                    onRename: () => _rename(context, device),
                  ),
                  if (widget.info != null)
                    ..._sections(widget.info!)
                  else
                    FutureBuilder<String?>(
                      future: _productName,
                      builder: (context, snapshot) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _sections(
                          DeviceInfoData.fromDevice(
                            device,
                            mower: mower,
                            model: snapshot.data ?? '',
                          ),
                        ),
                      ),
                    ),
                  // 联调用：把 DP 162 当前上报的值原样弹出来核对（花盆 DP，割草机没有）。
                  if (!mower) ...<Widget>[
                    const SizedBox(height: 20),
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
    required this.firmwareVersion,
    required this.model,
    required this.deviceDevId,
    required this.hardwareVersion,
    this.mac,
  });

  /// [model] 是涂鸦产品名称（异步取，[FlowerpotState.productNameFor]）；取不到传空串。
  factory DeviceInfoData.fromDevice(
    SmartPlanterDevice device, {
    required bool mower,
    String model = '',
  }) {
    return DeviceInfoData(
      firmwareVersion: device.firmwareVersion,
      model: model,
      deviceDevId: device.id,
      // 割草机才显示 mac 地址；DeviceBean.getMac（没有时是 uuid），去掉冒号。
      mac: mower ? device.macAddress.replaceAll(':', '') : null,
      // 花盆：`hardware_version`（DP 149）。割草机协议 V2.3 里没有硬件版本 DP，
      // 不能拿花盆的 149 去解（两边 DP 号重叠、含义不同），没有数据来源就空着。
      hardwareVersion: mower ? '' : device.hardwareVersion,
    );
  }

  final String firmwareVersion;
  final String model;
  final String deviceDevId;

  /// 只有割草机有；null 表示不显示这一行。
  final String? mac;
  final String hardwareVersion;
}

class _DeviceInfoHero extends StatelessWidget {
  const _DeviceInfoHero({
    required this.device,
    required this.mower,
    required this.onRename,
  });

  final SmartPlanterDevice device;
  final bool mower;
  final VoidCallback onRename;

  /// 割草机的产品图：涂鸦产品图（DeviceBean.iconUrl），拿不到用设计稿导出的割草机图。
  Widget _mowerImage() {
    const fallback = Image(
      image: AssetImage(MowerAssets.device),
      width: 62,
      height: 62,
      fit: BoxFit.contain,
    );
    final url = device.iconUrl.trim();
    if (url.isEmpty) return fallback;
    return Image.network(
      url,
      width: 62,
      height: 62,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '设备图片',
      errorBuilder: (_, _, _) => fallback,
    );
  }

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
                  child: mower
                      ? _mowerImage()
                      : DevicePlantArtwork(deviceId: device.id, width: 62),
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
                    // 陪伴天数是花盆的概念，割草机头部只有产品图 + 昵称。
                    if (!mower)
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
