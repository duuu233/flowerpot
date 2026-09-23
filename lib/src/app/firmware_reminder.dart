import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system/design_system.dart';
import '../features/devices/presentation/device_other_settings_page.dart';
import '../features/mower/mower_device.dart';
import '../features/mower/presentation/mower_firmware.dart';
import '../features/mower/presentation/mower_home_page.dart';
import '../features/mower/presentation/widgets/mower_bottom_nav.dart';
import '../routes/app_routes.dart';
import '../state.dart';
import '../tuya/tuya_models.dart';
import 'app_route_tracker.dart';

/// 固件升级提醒：按涂鸦平台给这次固件配的升级方式（[FirmwareUpgradeType]）弹不同的框
/// （2026-09-15 产品）。
///
/// | 升级方式 | 交互 |
/// | --- | --- |
/// | 提醒升级 | 弹「检测到 V x.y.z 新版本，确认是否升级」，取消 / 立刻更新 |
/// | 强制升级 | 弹「检测到 V x.y.z 新版本，请升级后使用」，只有立刻更新，返回键和点遮罩都关不掉 |
/// | 检测升级 | 不弹，保持现有的小红点 |
///
/// 「立刻更新」：关掉提醒弹窗，跳到这台设备的「其他设置」（割草机是切到「设置」栏），
/// 再弹固件升级框，用户确认后才升级（2026-09-23 产品；此前是跳过去直接升级）。
///
/// **只在设备页上监控**：进设备详情及其下各子页（[_isDevicePage]）时问一次涂鸦
/// （同一台设备 [recheckInterval] 内不重复问）。设备列表、搜索 / 配网、「我的」一侧的
/// 页面都不监控。「其他设置」本身不弹——升级入口就在那一页上，而且「立刻更新」要跳去的
/// 正是它。
///
/// - 提醒升级点了「取消」，这次进设备面板就不再提醒；离开设备页（回列表、进「我的」）
///   之后再进来会重新提醒——对应平台说明「用户进入设备面板主动提醒」。
/// - 强制升级只要还有新版本、没在升级，每次回到设备页都会弹。
/// - 正在升级（且没超时卡住）时不弹；最上面盖着别的弹框时先不弹，关掉后路由栈一变再看。
class FirmwareReminderHost extends StatefulWidget {
  const FirmwareReminderHost({
    required this.state,
    required this.routes,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final FlowerpotState state;
  final AppRouteTracker routes;

  /// 闪屏期间为 false。
  final bool enabled;
  final Widget child;

  /// 同一台设备多久之内不重复问涂鸦有没有新固件。
  static const Duration recheckInterval = Duration(minutes: 1);

  /// 设备相关、但不属于「设备页」的路由。
  static const Set<String> _notDevicePages = <String>{
    AppRoutes.deviceList,
    AppRoutes.deviceSearch,
    AppRoutes.pairing,
    AppRoutes.pairingFailure,
    AppRoutes.pairingSuccess,
  };

  /// 设备详情及其下各子页（含「其他设置」），以及割草机那套页面（`/mower…`，2026-09-23：
  /// 「固件升级提醒机制跟花盆做一样的，红点和弹窗」）。
  static bool _isDevicePage(String? name) =>
      name != null &&
      ((name.startsWith('/devices/') && !_notDevicePages.contains(name)) ||
          _isMowerPage(name));

  static bool _isMowerPage(String? name) =>
      name != null && name.startsWith(AppRoutes.mowerHome);

  static String _displayVersion(String version) =>
      version.startsWith('V') ? version : 'V$version';

  static String remindMessage(String version) =>
      '检测到${_displayVersion(version)}新版本，确认是否升级';

  static String forceMessage(String version) =>
      '检测到${_displayVersion(version)}新版本，请升级后使用';

  @override
  State<FirmwareReminderHost> createState() => _FirmwareReminderHostState();
}

class _FirmwareReminderHostState extends State<FirmwareReminderHost> {
  final Map<String, DateTime> _checkedAt = <String, DateTime>{};

  /// 这次进设备面板已经点过「取消」的设备。离开设备页就清掉。
  final Set<String> _remindDismissed = <String>{};

  bool _scheduled = false;
  bool _evaluating = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    widget.routes.addListener(_schedule);
    widget.state.addListener(_schedule);
    if (widget.enabled) _schedule();
  }

  @override
  void didUpdateWidget(covariant FirmwareReminderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.routes, widget.routes)) {
      oldWidget.routes.removeListener(_schedule);
      widget.routes.addListener(_schedule);
    }
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(_schedule);
      widget.state.addListener(_schedule);
    }
    if (widget.enabled && !oldWidget.enabled) _schedule();
  }

  @override
  void dispose() {
    widget.routes.removeListener(_schedule);
    widget.state.removeListener(_schedule);
    super.dispose();
  }

  /// 路由栈回调发生在 Navigator 刷新过程中，状态通知也可能落在 build 里：都推到帧末再看。
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_evaluate());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// 一次只跑一轮；跑的过程中（例如弹窗开着）又有变化，跑完再看一遍。
  Future<void> _evaluate() async {
    if (_evaluating) {
      _dirty = true;
      return;
    }
    _evaluating = true;
    try {
      do {
        _dirty = false;
        await _evaluateOnce();
      } while (_dirty && mounted);
    } finally {
      _evaluating = false;
    }
  }

  Future<void> _evaluateOnce() async {
    if (!mounted || !widget.enabled) return;
    final state = widget.state;
    final page = widget.routes.currentPage;
    final name = page?.settings.name;
    // 割草机各页只有外壳带设备 ID，子页不带——统一取当前绑着的那台（MowerDevice）。
    final deviceId = page != null && FirmwareReminderHost._isDevicePage(name)
        ? FirmwareReminderHost._isMowerPage(name)
              ? MowerDevice.instance.deviceId
              : AppRoutes.deviceIdOf(page.settings) ?? state.selectedDevice?.id
        : null;
    // 离开设备页就算这次看完了设备面板，下次进来重新提醒。
    _remindDismissed.removeWhere((id) => id != deviceId);
    if (deviceId == null || !state.authenticated) return;
    if (name == AppRoutes.deviceOtherSettings) return;
    if (widget.routes.popupOnTop) return;
    final running =
        state.otaProgressFor(deviceId)?.status == OtaStatus.running &&
        !state.otaStalled(deviceId);
    if (running) return;

    final checkedAt = _checkedAt[deviceId];
    if (checkedAt == null ||
        DateTime.now().difference(checkedAt) >
            FirmwareReminderHost.recheckInterval) {
      _checkedAt[deviceId] = DateTime.now();
      await state.refreshFirmwareUpdate(deviceId);
      // 结论没变时状态层不会通知，自己再看一遍。
      _dirty = true;
      return;
    }

    final update = state.availableFirmwareFor(deviceId);
    if (update == null) return;
    switch (update.upgradeType) {
      case FirmwareUpgradeType.check:
        return;
      case FirmwareUpgradeType.remind:
        if (_remindDismissed.contains(deviceId)) return;
        await _alert(deviceId, update, force: false);
      case FirmwareUpgradeType.force:
        await _alert(deviceId, update, force: true);
    }
  }

  Future<void> _alert(
    String deviceId,
    FirmwareUpdate update, {
    required bool force,
  }) async {
    final dialogContext = widget.routes.navigator?.overlay?.context;
    if (dialogContext == null) return;
    debugPrint(
      '[ota] 升级提醒（${force ? '强制' : '提醒'}）$deviceId → ${update.version}',
    );
    final bool upgrade;
    if (force) {
      upgrade = await _showForceDialog(dialogContext, update.version);
    } else {
      upgrade =
          await showAppDialog(
            dialogContext,
            title: FirmwareReminderHost.remindMessage(update.version),
            icon: Icons.system_update_alt_rounded,
            cancelLabel: '取消',
            confirmLabel: '立刻更新',
            barrierDismissible: false,
          ) ==
          true;
    }
    if (!mounted) return;
    if (!upgrade) {
      _remindDismissed.add(deviceId);
      return;
    }
    // 割草机（2026-09-23 产品，与花盆同理）：关提醒弹窗 → 退回割草机外壳、切到「设置」栏（升级入口
    // 「设备升级」在那一页）→ 再弹固件升级框（当前版本 → 新版本），确认后才升级。
    if (FirmwareReminderHost._isMowerPage(
      widget.routes.currentPage?.settings.name,
    )) {
      final navigator = widget.routes.navigator;
      navigator?.popUntil(
        (route) => route.settings.name == AppRoutes.mowerHome || route.isFirst,
      );
      MowerHomePage.tabRequests.value = MowerTab.settings;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = navigator?.overlay?.context;
        if (context != null) unawaited(upgradeMowerFirmware(context, deviceId));
      });
      return;
    }
    unawaited(
      widget.routes.navigator?.pushNamed(
        AppRoutes.deviceOtherSettings,
        arguments: DeviceOtherSettingsArguments(
          deviceId: deviceId,
          startFirmwareUpgrade: true,
        ),
      ),
    );
  }

  /// 强制升级：只有「立刻更新」，返回键、点遮罩都关不掉。
  static Future<bool> _showForceDialog(BuildContext context, String version) {
    var resolved = false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .4),
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AppDialog(
          key: const Key('firmware-force-upgrade-dialog'),
          title: FirmwareReminderHost.forceMessage(version),
          icon: Icons.system_update_alt_rounded,
          confirmLabel: '立刻更新',
          showCancel: false,
          onConfirm: () {
            if (resolved) return;
            resolved = true;
            Navigator.of(dialogContext).pop(true);
          },
        ),
      ),
    ).then((value) => value ?? false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
