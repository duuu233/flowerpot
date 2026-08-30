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
    final state = FlowerpotScope.of(context);
    final device = state.deviceById(widget.deviceId);
    final ota = state.otaProgressFor(widget.deviceId);
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.xl,
                AppSpacing.pageMargin,
                40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _GeneralSettingsCard(
                    device: device,
                    updatingFirmware: _updatingFirmware,
                    ota: ota,
                    onTemperatureUnit: () => _chooseTemperatureUnit(device),
                    onClockFormat: () => _chooseClockFormat(device),
                    onCalibration: _calibrateWaterLevel,
                    onSystemFiles: _showSystemFileMessage,
                    onFirmware: () => _checkFirmware(device),
                    onRepair: _showRepairMessage,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _DeviceActionsCard(
                    onPairing: () => _repairNetwork(device),
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
    final scope = FlowerpotScope.of(context);
    await showWaterLevelCalibrationDialog(
      context,
      onCalibrate: (step) async {
        final result = await scope.calibrateWaterLevel(widget.deviceId, step);
        if (!mounted) return false;
        if (!result.success) {
          showAppMessage(context, result.message, tone: AppMessageTone.error);
        }
        return result.success;
      },
      onCancel: () => scope.cancelWaterLevelCalibration(widget.deviceId),
    );
  }

  void _showSystemFileMessage() {
    showAppMessage(context, '系统文件更新暂未开放');
  }

  /// The product has no repair DP: the exported function point table goes
  /// straight from 水位校准 (140) to 恢复出厂设置 (141). Say so rather than
  /// sending a command the device will reject.
  void _showRepairMessage() {
    showAppMessage(context, '系统修复暂未开放');
  }

  Future<void> _checkFirmware(SmartPlanterDevice device) async {
    if (_updatingFirmware) return;
    // 升级发起后本地标志就复位了，真正的进行中状态在 state 里，否则用户能在
    // 设备还在烧录时再发起一次。
    final running =
        FlowerpotScope.of(context).otaProgressFor(widget.deviceId)?.status ==
        OtaStatus.running;
    if (running) {
      showAppMessage(context, '固件正在升级中，请等待完成', tone: AppMessageTone.info);
      return;
    }
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

  /// 重新配网 = 先解绑，再从搜索设备重新走一遍。
  ///
  /// 不能直接跳到填 Wi-Fi 那一页：设备还绑在账号上时它是正常工作状态，既不拉
  /// 热点也不监听配网广播，配过去只会等满 120 秒报 `1006 out of time`。解绑
  /// （带 DP 141 恢复出厂）会让它回到配网状态，这时搜索页才扫得到它的热点。
  Future<void> _repairNetwork(SmartPlanterDevice device) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '重新配网',
      message:
          '需要先解绑“${device.name}”，设备会回到配网状态，随后重新添加。\n'
          '设备上的个性化设置会被清除，确定继续吗？',
      confirmLabel: '解绑并重新配网',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final result = await FlowerpotScope.of(
      context,
    ).removeDevice(widget.deviceId, resetFactory: true);
    if (!mounted) return;
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
      return;
    }
    // 设备已经从账号里移除，本页和它的兄弟页都失去了数据源，所以清到根再进
    // 搜索页——而不是 push 一层上去。
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.pushNamed(context, AppRoutes.deviceSearch);
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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageMargin,
          10,
          AppSpacing.pageMargin,
          18,
        ),
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
    required this.ota,
    required this.onFirmware,
    required this.onRepair,
  });

  final SmartPlanterDevice device;
  final bool updatingFirmware;
  final VoidCallback onTemperatureUnit;
  final VoidCallback onClockFormat;
  final VoidCallback onCalibration;
  final VoidCallback onSystemFiles;
  final OtaProgress? ota;
  final VoidCallback onFirmware;
  final VoidCallback onRepair;

  @override
  Widget build(BuildContext context) {
    final settings = device.settings;
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
            // 升级要跑几分钟，把设备回报的百分比顶到这一行，否则用户只能对着
            // 一个不动的加载态干等。
            value: switch (ota?.status) {
              OtaStatus.running => '升级中 ${ota?.percent ?? 0}%',
              OtaStatus.failed => ota?.message ?? '升级失败',
              _ => 'V${device.firmwareVersion}',
            },
            loading: updatingFirmware || ota?.status == OtaStatus.running,
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
      margin: const EdgeInsets.fromLTRB(51, 0, 16, AppSpacing.xxs),
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
            AppAssets.infoOutlineIcon,
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
      minTileHeight: 42,
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
