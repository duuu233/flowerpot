import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import 'widgets/water_level_calibration_dialog.dart';

class DeviceOtherSettingsPage extends StatefulWidget {
  const DeviceOtherSettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<DeviceOtherSettingsPage> createState() =>
      _DeviceOtherSettingsPageState();
}

class _DeviceOtherSettingsPageState extends State<DeviceOtherSettingsPage> {
  bool _updatingFirmware = false;

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '其他设置', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }

    return AppPageScaffold(
      appBar: const AppPageHeader(title: '其他设置', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        key: const Key('device-other-settings-scroll-view'),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
              maxWidth: 375,
              padding: const EdgeInsets.fromLTRB(20, 72, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _GeneralSettingsCard(
                    device: device,
                    updatingFirmware: _updatingFirmware,
                    onTemperatureUnit: () => _chooseTemperatureUnit(device),
                    onClockFormat: () => _chooseClockFormat(device),
                    onCalibration: _calibrateWaterLevel,
                    onSystemFiles: _showSystemFileMessage,
                    onFirmware: () => _checkFirmware(device),
                    onRepair: () => _runMaintenance(
                      action: 'repairSystem',
                      title: '修复系统文件',
                      message: '修复过程中请保持设备在线并连接电源。',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _DeviceActionsCard(
                    onPairing: () =>
                        Navigator.pushNamed(context, AppRoutes.pairing),
                    onFactoryReset: () =>
                        _removeDevice(device, resetFactory: true),
                    onRemove: () => _removeDevice(device, resetFactory: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseTemperatureUnit(SmartPlanterDevice device) async {
    final selected = await showTemperatureUnitSheet(
      context,
      selectedUnit: device.settings.temperatureUnit,
    );
    if (selected != null && selected != device.settings.temperatureUnit) {
      await _updateSetting('temperatureUnit', selected);
    }
  }

  Future<void> _chooseClockFormat(SmartPlanterDevice device) async {
    final selected = await showClockFormatSheet(
      context,
      selectedFormat: device.settings.clockFormat,
    );
    if (selected != null && selected != device.settings.clockFormat) {
      await _updateSetting('clockFormat', selected);
    }
  }

  Future<void> _updateSetting(String key, Object value) async {
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, key, value);
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  Future<void> _calibrateWaterLevel() async {
    await showWaterLevelCalibrationDialog(
      context,
      onCalibrate: () async {
        final result = await FlowerpotScope.of(
          context,
        ).runMaintenance(widget.deviceId, 'calibrateWaterLevel');
        if (!mounted) return false;
        if (!result.success) {
          showAppMessage(context, result.message, tone: AppMessageTone.error);
        }
        return result.success;
      },
    );
  }

  Future<void> _runMaintenance({
    required String action,
    required String title,
    required String message,
  }) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: '开始',
    );
    if (!confirmed || !mounted) return;
    final result = await FlowerpotScope.of(
      context,
    ).runMaintenance(widget.deviceId, action);
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  void _showSystemFileMessage() {
    showAppMessage(context, '系统文件更新功能暂未接入，可在后续替换为文件选择流程。');
  }

  Future<void> _checkFirmware(SmartPlanterDevice device) async {
    if (_updatingFirmware) return;
    setState(() => _updatingFirmware = true);
    try {
      final version = await FlowerpotScope.of(
        context,
      ).checkFirmware(widget.deviceId);
      if (!mounted) return;
      if (version == null || version == device.firmwareVersion) {
        showAppMessage(context, '当前已是最新固件版本');
        return;
      }
      setState(() => _updatingFirmware = false);
      final confirmed = await showFirmwareUpdateDialog(
        context,
        currentVersion: device.firmwareVersion,
        availableVersion: version,
      );
      if (!confirmed || !mounted) return;
      setState(() => _updatingFirmware = true);
      final result = await FlowerpotScope.of(
        context,
      ).upgradeFirmware(widget.deviceId, version);
      if (!mounted) return;
      showAppMessage(
        context,
        result.message,
        tone: result.success ? AppMessageTone.success : AppMessageTone.error,
      );
    } catch (error) {
      if (mounted) {
        showAppMessage(context, '固件检查失败：$error', tone: AppMessageTone.error);
      }
    } finally {
      if (mounted) setState(() => _updatingFirmware = false);
    }
  }

  Future<void> _removeDevice(
    SmartPlanterDevice device, {
    required bool resetFactory,
  }) async {
    final title = resetFactory ? '恢复出厂设置' : '移除设备';
    final message = resetFactory
        ? '设备数据和个性化设置将被清除，确定继续吗？'
        : '移除后需要重新配网才能使用“${device.name}”，确定继续吗？';
    final confirmed = await showAppConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: title,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final result = await FlowerpotScope.of(
      context,
    ).removeDevice(widget.deviceId, resetFactory: resetFactory);
    if (!mounted) return;
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
      return;
    }
    showAppMessage(context, result.message, tone: AppMessageTone.success);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

Future<String?> showTemperatureUnitSheet(
  BuildContext context, {
  required String selectedUnit,
}) {
  return _showSettingsChoiceSheet(
    context,
    title: '温度单位',
    selectedValue: selectedUnit,
    keyPrefix: 'temperature-unit',
    options: const <_SettingsChoiceOptionData>[
      _SettingsChoiceOptionData(value: 'celsius', label: '摄氏度（℃）'),
      _SettingsChoiceOptionData(value: 'fahrenheit', label: '华氏度（℉）'),
    ],
  );
}

Future<String?> showClockFormatSheet(
  BuildContext context, {
  required String selectedFormat,
}) {
  return _showSettingsChoiceSheet(
    context,
    title: '时钟模式',
    selectedValue: selectedFormat,
    keyPrefix: 'clock-format',
    options: const <_SettingsChoiceOptionData>[
      _SettingsChoiceOptionData(value: '12h', label: '12小时'),
      _SettingsChoiceOptionData(value: '24h', label: '24小时'),
    ],
  );
}

Future<String?> _showSettingsChoiceSheet(
  BuildContext context, {
  required String title,
  required String selectedValue,
  required String keyPrefix,
  required List<_SettingsChoiceOptionData> options,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    barrierColor: Colors.black.withValues(alpha: .42),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => _SettingsChoiceSheet(
      title: title,
      initialValue: selectedValue,
      keyPrefix: keyPrefix,
      options: options,
    ),
  );
}

class _SettingsChoiceOptionData {
  const _SettingsChoiceOptionData({required this.value, required this.label});

  final String value;
  final String label;
}

class _SettingsChoiceSheet extends StatefulWidget {
  const _SettingsChoiceSheet({
    required this.title,
    required this.initialValue,
    required this.keyPrefix,
    required this.options,
  });

  final String title;
  final String initialValue;
  final String keyPrefix;
  final List<_SettingsChoiceOptionData> options;

  @override
  State<_SettingsChoiceSheet> createState() => _SettingsChoiceSheetState();
}

class _SettingsChoiceSheetState extends State<_SettingsChoiceSheet> {
  late String _selectedValue = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: Key('${widget.keyPrefix}-sheet'),
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              key: Key('${widget.keyPrefix}-drag-handle'),
              width: 48,
              height: 4,
              decoration: const BoxDecoration(
                color: AppColors.disabled,
                borderRadius: AppRadius.full,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 50,
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 72,
                    child: TextButton(
                      key: Key('cancel-${widget.keyPrefix}'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        '取消',
                        style: AppTypography.status.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: AppTypography.deviceTitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: TextButton(
                      key: Key('confirm-${widget.keyPrefix}'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.brandPrimary,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => Navigator.pop(context, _selectedValue),
                      child: Text(
                        '确认',
                        style: AppTypography.status.copyWith(
                          color: AppColors.brandPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var index = 0; index < widget.options.length; index++) ...[
              _SettingsChoiceOption(
                key: Key('${widget.options[index].value}-${widget.keyPrefix}'),
                label: widget.options[index].label,
                selected: _selectedValue == widget.options[index].value,
                onTap: () => setState(
                  () => _selectedValue = widget.options[index].value,
                ),
              ),
              if (index < widget.options.length - 1)
                const SizedBox(height: AppSpacing.xxs),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsChoiceOption extends StatelessWidget {
  const _SettingsChoiceOption({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF7F7F7) : Colors.transparent,
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: onTap,
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: Center(
            child: Text(
              label,
              style: AppTypography.status.copyWith(
                fontSize: selected ? 19 : 16,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> showFirmwareUpdateDialog(
  BuildContext context, {
  required String currentVersion,
  required String availableVersion,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .42),
        builder: (dialogContext) => Dialog(
          key: const Key('firmware-update-dialog'),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 327),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  child: Column(
                    children: <Widget>[
                      Text(
                        '检查更新',
                        style: AppTypography.deviceTitle.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      _FirmwareVersionRow(
                        label: '当前版本',
                        version: _displayVersion(currentVersion),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _FirmwareVersionRow(
                        label: '发现新版本',
                        version: _displayVersion(availableVersion),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                IntrinsicHeight(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextButton(
                          key: const Key('postpone-firmware-update'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            foregroundColor: AppColors.textSecondary,
                            shape: const RoundedRectangleBorder(),
                          ),
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(
                            '稍后',
                            style: AppTypography.status.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: TextButton(
                          key: const Key('install-firmware-update'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            foregroundColor: AppColors.brandPrimary,
                            shape: const RoundedRectangleBorder(),
                          ),
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(
                            '立即更新',
                            style: AppTypography.status.copyWith(
                              color: AppColors.brandPrimary,
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
      ) ??
      false;
}

String _displayVersion(String version) =>
    version.startsWith('V') ? version : 'V$version';

class _FirmwareVersionRow extends StatelessWidget {
  const _FirmwareVersionRow({required this.label, required this.version});

  final String label;
  final String version;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: AppTypography.status)),
        Text(version, style: AppTypography.status),
      ],
    );
  }
}

class _GeneralSettingsCard extends StatelessWidget {
  const _GeneralSettingsCard({
    required this.device,
    required this.updatingFirmware,
    required this.onTemperatureUnit,
    required this.onClockFormat,
    required this.onCalibration,
    required this.onSystemFiles,
    required this.onFirmware,
    required this.onRepair,
  });

  final SmartPlanterDevice device;
  final bool updatingFirmware;
  final VoidCallback onTemperatureUnit;
  final VoidCallback onClockFormat;
  final VoidCallback onCalibration;
  final VoidCallback onSystemFiles;
  final VoidCallback onFirmware;
  final VoidCallback onRepair;

  @override
  Widget build(BuildContext context) {
    final settings = device.settings;
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: <Widget>[
          _SettingsRow(
            key: const Key('temperature-unit-setting'),
            assetPath: AppAssets.temperatureUnitIcon,
            title: '温度单位',
            value: settings.temperatureUnit == 'celsius' ? '摄氏度（℃）' : '华氏度（℉）',
            onTap: onTemperatureUnit,
          ),
          _SettingsRow(
            key: const Key('clock-format-setting'),
            assetPath: AppAssets.clockModeIcon,
            title: '时钟模式',
            value: settings.clockFormat == '24h' ? '24小时' : '12小时',
            onTap: onClockFormat,
          ),
          _SettingsRow(
            key: const Key('water-level-calibration-setting'),
            assetPath: AppAssets.waterCalibrationIcon,
            title: '水位传感器校准',
            onTap: onCalibration,
          ),
          _SettingsRow(
            assetPath: AppAssets.fileSyncIcon,
            title: '系统文件更新',
            onTap: onSystemFiles,
          ),
          const _SystemFileNotice(),
          _SettingsRow(
            assetPath: AppAssets.chipUpdateIcon,
            title: '固件版本更新',
            value: 'V${device.firmwareVersion}',
            loading: updatingFirmware,
            onTap: onFirmware,
          ),
          _SettingsRow(
            assetPath: AppAssets.deviceRepairIcon,
            title: '修复系统文件',
            onTap: onRepair,
          ),
        ],
      ),
    );
  }
}

class _SystemFileNotice extends StatelessWidget {
  const _SystemFileNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('system-file-notice'),
      margin: const EdgeInsets.fromLTRB(51, 0, 16, 7),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Image.asset(
            AppAssets.warningIcon,
            width: 18,
            height: 18,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: '系统文件说明',
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              '系统文件包括YSplanter的表情、行为模型、语言包，和其他系统所需文件。',
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceActionsCard extends StatelessWidget {
  const _DeviceActionsCard({
    required this.onPairing,
    required this.onFactoryReset,
    required this.onRemove,
  });

  final VoidCallback onPairing;
  final VoidCallback onFactoryReset;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: <Widget>[
          _SettingsRow(
            key: const Key('repair-network-setting'),
            assetPath: AppAssets.globeWarningIcon,
            title: '重新配网',
            titleColor: AppColors.warningSoft,
            onTap: onPairing,
          ),
          _SettingsRow(
            key: const Key('factory-reset-setting'),
            assetPath: AppAssets.resetIcon,
            title: '恢复出厂设置',
            titleColor: AppColors.danger,
            onTap: onFactoryReset,
          ),
          _SettingsRow(
            key: const Key('remove-device-setting'),
            assetPath: AppAssets.deleteIcon,
            title: '移除设备',
            titleColor: AppColors.danger,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.assetPath,
    required this.title,
    required this.onTap,
    super.key,
    this.value,
    this.titleColor,
    this.loading = false,
  });

  final String assetPath;
  final String title;
  final String? value;
  final Color? titleColor;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 44,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: Image.asset(
        assetPath,
        width: 23,
        height: 23,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: title,
      ),
      title: Text(
        title,
        style: AppTypography.bodyEmphasis.copyWith(
          color: titleColor ?? AppColors.textPrimary,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (loading)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (value != null)
            Text(
              value!,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
          const AppTrailingChevron(),
        ],
      ),
      onTap: onTap,
    );
  }
}
