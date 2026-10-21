import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import '../models/display_settings_page_model.dart';
import 'device_online_guard.dart';
import 'widgets/display_settings_card.dart';

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  static const _brightnessInterval = Duration(milliseconds: 120);
  static const _brightnessSettleDelay = Duration(milliseconds: 500);
  static const _brightnessEchoTimeout = Duration(seconds: 5);
  bool updating = false;
  bool _sendingBrightness = false;
  bool _draggingBrightness = false;
  int? _queuedBrightness;
  Timer? _brightnessTimer;
  double? pendingBrightness;
  Future<ActionResult>? _brightnessRequest;
  Timer? _brightnessSettleTimer;
  Timer? _brightnessEchoTimer;

  void _cancelBrightnessConfirmation() {
    _brightnessSettleTimer?.cancel();
    _brightnessSettleTimer = null;
    _brightnessEchoTimer?.cancel();
    _brightnessEchoTimer = null;
  }

  void _cancelBrightnessDraft() {
    _brightnessTimer?.cancel();
    _brightnessTimer = null;
    _queuedBrightness = null;
    _draggingBrightness = false;
    pendingBrightness = null;
    _cancelBrightnessConfirmation();
  }

  void _releaseBrightnessDraft() {
    _cancelBrightnessConfirmation();
    if (mounted) setState(() => pendingBrightness = null);
  }

  // SDK success only means the command was accepted. Keep the released thumb
  // stable across intermediate echoes; return to device state once it settles.
  void _syncBrightnessConfirmation() {
    if (_brightnessEchoTimer == null || pendingBrightness == null) return;
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device?.settings.manualBrightness != pendingBrightness!.round()) {
      _brightnessSettleTimer?.cancel();
      _brightnessSettleTimer = null;
      return;
    }
    _brightnessSettleTimer ??= Timer(_brightnessSettleDelay, () {
      _brightnessSettleTimer = null;
      if (!mounted) return;
      final current = FlowerpotScope.of(context).deviceById(widget.deviceId);
      if (current?.settings.manualBrightness == pendingBrightness?.round()) {
        _releaseBrightnessDraft();
      }
    });
  }

  void _awaitBrightnessEcho() {
    if (pendingBrightness == null) return;
    _cancelBrightnessConfirmation();
    // Never leave an unconfirmed local value on screen indefinitely.
    _brightnessEchoTimer = Timer(
      _brightnessEchoTimeout,
      _releaseBrightnessDraft,
    );
    _syncBrightnessConfirmation();
  }

  void _previewBrightness(double value) {
    if (updating) return;
    _cancelBrightnessConfirmation();
    _draggingBrightness = true;
    setState(() => pendingBrightness = value);
    _queuedBrightness = value.round().clamp(0, 100);
    _scheduleBrightness();
  }

  void _scheduleBrightness() {
    if (_sendingBrightness || _brightnessTimer != null) return;
    _brightnessTimer = Timer(_brightnessInterval, () {
      _brightnessTimer = null;
      unawaited(_flushBrightness());
    });
  }

  // 拖动时限频、串行下发，只保留最近值；松手立即补发最终值（0=灭屏）。
  void _setBrightness(double value) {
    if (updating) return;
    _cancelBrightnessConfirmation();
    _draggingBrightness = false;
    _queuedBrightness = value.round().clamp(0, 100);
    setState(() => pendingBrightness = value);
    _brightnessTimer?.cancel();
    _brightnessTimer = null;
    unawaited(_flushBrightness());
  }

  Future<void> _flushBrightness() async {
    if (!mounted || _sendingBrightness || _queuedBrightness == null) return;
    final state = FlowerpotScope.of(context);
    final device = state.deviceById(widget.deviceId);
    if (device == null ||
        !device.online ||
        device.settings.autoBrightness ||
        updating) {
      setState(_cancelBrightnessDraft);
      return;
    }
    final brightness = _queuedBrightness!;
    _queuedBrightness = null;
    setState(() => _sendingBrightness = true);
    final request = state.updateSetting(
      widget.deviceId,
      'manualBrightness',
      brightness,
    );
    _brightnessRequest = request;
    final result = await request;
    _brightnessRequest = null;
    if (!mounted) return;
    setState(() {
      _sendingBrightness = false;
      if (!result.success &&
          !_draggingBrightness &&
          _queuedBrightness == null) {
        pendingBrightness = null;
      }
    });
    if (_queuedBrightness != null) {
      if (_draggingBrightness) {
        _scheduleBrightness();
      } else {
        unawaited(_flushBrightness());
      }
    } else if (!result.success) {
      showDeviceActionResult(context, result);
    } else if (!_draggingBrightness && !updating) {
      _awaitBrightnessEcho();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    // 设备端切回自动/离线时放弃拖动草稿，避免继续发送手动值或锁住自动开关。
    if (device == null || !device.online || device.settings.autoBrightness) {
      _cancelBrightnessDraft();
    } else {
      _syncBrightnessConfirmation();
    }
  }

  @override
  void dispose() {
    _cancelBrightnessDraft();
    super.dispose();
  }

  Future<void> _setAutoBrightness(bool value) async {
    if (updating) return;
    setState(() {
      updating = true;
      _cancelBrightnessDraft();
    });
    // Cancel unsent dimming first, then let the active write release the shared
    // state lock before switching modes. Brightness traffic never fades Switch.
    await _brightnessRequest;
    if (!mounted) return;
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'autoBrightness', value);
    if (!mounted) return;
    setState(() => updating = false);
    if (!result.success) {
      showDeviceActionResult(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '显示', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final model = DisplaySettingsPageModel.fromSettings(device.settings);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '显示', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: DeviceOnlineBody(
        deviceId: widget.deviceId,
        child: SingleChildScrollView(
          key: const Key('display-settings-scroll-view'),
          child: ResponsiveContent(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              27,
              AppSpacing.pageMargin,
              40,
            ),
            child: DisplaySettingsCard(
              model: model,
              brightness:
                  pendingBrightness ?? model.manualBrightness.toDouble(),
              updating: updating,
              updatingBrightness: updating,
              onAutoBrightnessChanged: _setAutoBrightness,
              onBrightnessChanged: _previewBrightness,
              onBrightnessChangeEnd: _setBrightness,
            ),
          ),
        ),
      ),
    );
  }
}
