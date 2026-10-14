import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/widgets/blocking_progress.dart';
import '../../../tuya/tuya_models.dart';
import 'device_online_guard.dart';
import 'firmware_upgrade_flow.dart';
import 'widgets/ota_progress_dialog.dart';
import 'widgets/water_level_calibration_dialog.dart';

/// 「其他设置」的路由参数。老调用点传的裸 deviceId 字符串照样认。
class DeviceOtherSettingsArguments {
  const DeviceOtherSettingsArguments({
    required this.deviceId,
    this.startFirmwareUpgrade = false,
  });

  final String deviceId;

  /// 从固件升级提醒弹窗点「立刻更新」过来：进页面就弹固件升级框（当前版本 → 新版本），
  /// 用户在这一页确认后才升级（2026-09-23 产品：「点击立即更新需要关闭弹窗，跳转到设置那个页面
  /// 再弹出下面的固件升级框，花盆同理」；2026-09-15 那版是跳过来直接升级、不弹框）。
  final bool startFirmwareUpgrade;
}

class DeviceOtherSettingsPage extends StatefulWidget {
  const DeviceOtherSettingsPage({
    required this.deviceId,
    super.key,
    this.startFirmwareUpgrade = false,
  });

  final String deviceId;

  /// 见 [DeviceOtherSettingsArguments.startFirmwareUpgrade]。
  final bool startFirmwareUpgrade;

  @override
  State<DeviceOtherSettingsPage> createState() =>
      _DeviceOtherSettingsPageState();
}

class _DeviceOtherSettingsPageState extends State<DeviceOtherSettingsPage>
    with NetworkRetryAware<DeviceOtherSettingsPage> {
  @override
  void initState() {
    super.initState();
    // 进页面就静默问一次涂鸦有没有新固件，用户不必先点一下才知道。查到了就在
    // 「固件版本更新」那行点个红点；查失败什么都不说，见
    // FlowerpotState.refreshFirmwareUpdate。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = FlowerpotScope.of(context);
      if (widget.startFirmwareUpgrade &&
          state.deviceById(widget.deviceId) != null) {
        _checkFirmware();
        return;
      }
      state.refreshFirmwareUpdate(widget.deviceId);
    });
  }

  /// 「网络异常」弹窗点「重试」：重读设备，再问一次有没有新固件。
  @override
  Future<void> reloadForNetworkRetry() async {
    final state = FlowerpotScope.of(context);
    await state.reloadDevices();
    if (!mounted) return;
    await state.refreshFirmwareUpdate(widget.deviceId);
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
                11,
                AppSpacing.pageMargin,
                40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _GeneralSettingsCard(
                    device: device,
                    updatingFirmware: state.isCheckingFirmware(
                      widget.deviceId,
                    ),
                    ota: ota,
                    firmwareUpdate: state.hasFirmwareUpdate(widget.deviceId),
                    onTemperatureUnit: () => _chooseTemperatureUnit(device),
                    onClockFormat: () => _chooseClockFormat(device),
                    onCalibration: _calibrateWaterLevel,
                    onFirmware: _checkFirmware,
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
    // 下发要走云端往返，这段盖住不让点第二次（2026-09-12 产品：所有可能重复
    // 点击的地方都要有 loading）。
    final state = FlowerpotScope.of(context);
    final result = await withBlockingProgress(
      context,
      () => state.updateSetting(widget.deviceId, key, value),
    );
    // `withBlockingProgress` 返回可空：null 表示页面已经不在了，动作压根没发起。
    if (!mounted || result == null) return;
    showDeviceActionResult(context, result, announceSuccess: true);
  }

  Future<void> _calibrateWaterLevel() async {
    final scope = FlowerpotScope.of(context);
    await showWaterLevelCalibrationDialog(
      context,
      onCalibrate: (step) async {
        final result = await scope.calibrateWaterLevel(widget.deviceId, step);
        if (!mounted) return false;
        if (!result.success) {
          showDeviceActionResult(context, result);
        }
        return result.success;
      },
      onCancel: () => scope.cancelWaterLevelCalibration(widget.deviceId),
    );
  }

  /// 固件版本更新：和割草机「设备升级」共用 [runFirmwareUpgrade]（逻辑和交互都是那一份）。
  Future<void> _checkFirmware() => runFirmwareUpgrade(context, widget.deviceId);

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
    final state = FlowerpotScope.of(context);
    // 解绑是不可逆动作，更不能点两次。
    final result = await withBlockingProgress(
      context,
      () => state.removeDevice(widget.deviceId, resetFactory: true),
    );
    if (!mounted || result == null) return;
    if (!result.success) {
      showDeviceActionResult(context, result);
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
    // 恢复出厂要先把 DP 141 发到设备上才解绑（2026-09-21），离线时发不出去——先拦，
    // 别让用户确认完一件做不成的事。状态层还会再判一次，这里只是提前说。
    if (resetFactory && !ensureDeviceOnline(context, widget.deviceId)) return;
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
    final state = FlowerpotScope.of(context);
    // 同上：不可逆，点一次就够。
    // 恢复出厂：先下发 141、下发成功才解绑（`factoryResetDevice`）；移除设备直接解绑。
    final result = await withBlockingProgress(
      context,
      () => resetFactory
          ? state.factoryResetDevice(widget.deviceId)
          : state.removeDevice(widget.deviceId, resetFactory: false),
    );
    if (!mounted || result == null) return;
    if (!result.success) {
      showDeviceActionResult(context, result);
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
        // 稿子 214:6138 / 215:5871：弹层 222 高，标题紧贴拖动条、两项紧挨、底部不再留白。
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageMargin,
          10,
          AppSpacing.pageMargin,
          4,
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
            const SizedBox(height: 2),
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
            const SizedBox(height: 20),
            Flexible(
              child: AppDialogScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (
                      var index = 0;
                      index < widget.options.length;
                      index++
                    ) ...[
                      _SettingsChoiceOption(
                        key: Key(
                          '${widget.options[index].value}-${widget.keyPrefix}',
                        ),
                        label: widget.options[index].label,
                        selected: _selectedValue == widget.options[index].value,
                        onTap: () => setState(
                          () => _selectedValue = widget.options[index].value,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 48,
            minWidth: double.infinity,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
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
      ),
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
              OtaStatus.running => otaRunningLabel(ota, withPercent: true),
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
      // 2026-09-15 产品：每一项列高适当调高一点，页面剩余高度足够。42 → 56（Material
      // 单行列表的标准高度）；七行一共多出 98，375×812 仍是一屏放下。
      minTileHeight: 56,
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
