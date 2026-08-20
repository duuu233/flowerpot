import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';

class DeviceInfoPage extends StatelessWidget {
  const DeviceInfoPage({required this.deviceId, super.key, this.info});

  final String deviceId;
  final DeviceInfoData? info;

  Future<void> _rename(BuildContext context, SmartPlanterDevice device) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDeviceDialog(initialName: device.name),
    );
    if (name == null || !context.mounted) return;
    final result = await FlowerpotScope.of(
      context,
    ).renameDevice(device.id, name);
    if (context.mounted) {
      showAppMessage(
        context,
        result.message,
        tone: result.success ? AppMessageTone.success : AppMessageTone.error,
      );
    }
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
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
    return AlertDialog(
      title: const Text('编辑设备名称'),
      content: TextField(
        key: const Key('device-info-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 20,
      ),
      actions: <Widget>[
        AppTextButton(label: '取消', onPressed: () => Navigator.pop(context)),
        FilledButton(
          key: const Key('save-device-info-name'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
        ),
      ],
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
              const SizedBox(
                width: 76,
                child: Center(
                  child: AppDevicePlaceholder(hasPlant: true, width: 62),
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
