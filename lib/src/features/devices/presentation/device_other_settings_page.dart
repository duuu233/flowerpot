import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../../../tuya/tuya_repository.dart' show TuyaException;
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
  void initState() {
    super.initState();
    // 进页面就静默问一次涂鸦有没有新固件，用户不必先点一下才知道。查到了就在
    // 「固件版本更新」那行点个红点；查失败什么都不说，见
    // FlowerpotState.refreshFirmwareUpdate。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FlowerpotScope.of(context).refreshFirmwareUpdate(widget.deviceId);
    });
  }

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
                    firmwareUpdate: state.hasFirmwareUpdate(widget.deviceId),
                    onTemperatureUnit: () => _chooseTemperatureUnit(device),
                    onClockFormat: () => _chooseClockFormat(device),
                    onCalibration: _calibrateWaterLevel,
                    onFirmware: () => _checkFirmware(device),
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

  /// 检查固件，有新版本就弹确认框并发起升级。
  ///
  /// 「发起」和「完成」是两件事：涂鸦的 `startOta` 返回时设备才刚开始下载，
  /// 之后几分钟的进度和最终成败都从事件通道回来（见 `FlowerpotState.otaUpdates`），
  /// 所以这里只负责起头，进度显示在功能行上。
  Future<void> _checkFirmware(SmartPlanterDevice device) async {
    if (_updatingFirmware) return;
    final state = FlowerpotScope.of(context);
    // 升级发起后本地标志就复位了，真正的进行中状态在 state 里，否则用户能在
    // 设备还在烧录时再发起一次。
    final running =
        state.otaProgressFor(widget.deviceId)?.status == OtaStatus.running;
    // 进页面时静默查过一次，红点就是那次的结论；只有用户点的是「重新检查」时
    // 才不能拿那份旧结论糊弄他。
    var useKnownVersion = true;
    if (running) {
      // 设备掉电、掉线或校验失败时，涂鸦可能再也不回终态。十分钟没有任何事件
      // 就让用户重新检查，而不是把他锁在一个永远不动的进度上。
      if (!state.otaStalled(widget.deviceId)) {
        showAppMessage(context, '固件正在升级中，请等待完成', tone: AppMessageTone.info);
        return;
      }
      final retry = await showAppConfirmDialog(
        context,
        title: '升级似乎已中断',
        message:
            '设备已经很久没有回报升级进度。可以重新检查固件；'
            '若设备仍在升级中，请等它完成后再试。',
        confirmLabel: '重新检查',
        icon: Icons.sync_problem_outlined,
      );
      if (!retry || !mounted) return;
      useKnownVersion = false;
      state.clearOtaProgress(widget.deviceId);
    }
    setState(() => _updatingFirmware = true);
    try {
      // 已经知道版本号就不再问第二遍，直接把两个版本摆给用户看。
      final known = useKnownVersion
          ? state.availableFirmwareFor(widget.deviceId)
          : null;
      final version = known ?? await state.checkFirmware(widget.deviceId);
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
      final result = await state.upgradeFirmware(widget.deviceId, version);
      if (!mounted) return;
      showAppMessage(
        context,
        result.message,
        tone: result.success ? AppMessageTone.success : AppMessageTone.error,
      );
    } on TuyaException catch (error) {
      // SDK 的原始码对用户没有意义，但 message 是能照着做的那句；直接把
      // `Instance of 'TuyaException'` 丢到界面上是之前的行为。
      if (mounted) {
        showAppMessage(
          context,
          '固件检查失败：${error.message}',
          tone: AppMessageTone.error,
        );
      }
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
    required this.ota,
    required this.firmwareUpdate,
    required this.onFirmware,
  });

  final SmartPlanterDevice device;
  final bool updatingFirmware;
  final VoidCallback onTemperatureUnit;
  final VoidCallback onClockFormat;
  final VoidCallback onCalibration;
  final OtaProgress? ota;

  /// 涂鸦报了一个和当前版本不同的固件，行尾点红点。
  final bool firmwareUpdate;
  final VoidCallback onFirmware;

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
            key: const Key('firmware-update-setting'),
            assetPath: AppAssets.chipUpdateIcon,
            title: '固件版本更新',
            // 升级中就别再点红点了，那一行已经在讲进度。
            badge: firmwareUpdate && ota?.status != OtaStatus.running,
            // 升级要跑几分钟，把设备回报的百分比顶到这一行，否则用户只能对着
            // 一个不动的加载态干等。
            value: switch (ota?.status) {
              OtaStatus.running => '升级中 ${ota?.percent ?? 0}%',
              OtaStatus.failed => ota?.message ?? '升级失败',
              _ => 'V${device.firmwareVersion}',
            },
            // 转圈只用在"正在问云端"这几百毫秒上：升级期间也转的话，上面那个
            // 百分比就被它顶掉了（一行只显示其中之一），用户反而看不见进度。
            loading: updatingFirmware,
            onTap: onFirmware,
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
    this.badge = false,
  });

  final String assetPath;
  final String title;
  final String? value;
  final Color? titleColor;
  final bool loading;
  final bool badge;
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
          if (badge) ...<Widget>[
            const AppNoticeDot(semanticLabel: '有新固件'),
            const SizedBox(width: AppSpacing.xs),
          ],
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
