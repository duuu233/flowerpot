import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
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
  bool updating = false;
  bool _sendingBrightness = false;
  bool _draggingBrightness = false;
  int? _queuedBrightness;
  Timer? _brightnessTimer;
  double? pendingBrightness;

  void _previewBrightness(double value) {
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
    if (device == null || device.settings.autoBrightness || updating) {
      _queuedBrightness = null;
      setState(() => pendingBrightness = null);
      return;
    }
    final brightness = _queuedBrightness!;
    _queuedBrightness = null;
    setState(() => _sendingBrightness = true);
    final result = await state.updateSetting(
      widget.deviceId,
      'manualBrightness',
      brightness,
    );
    if (!mounted) return;
    setState(() {
      _sendingBrightness = false;
      if (!_draggingBrightness && _queuedBrightness == null) {
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
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    // 设备端切回自动/离线时放弃拖动草稿，避免继续发送手动值或锁住自动开关。
    if (device == null || !device.online || device.settings.autoBrightness) {
      _brightnessTimer?.cancel();
      _brightnessTimer = null;
      _queuedBrightness = null;
      _draggingBrightness = false;
      pendingBrightness = null;
    }
  }

  @override
  void dispose() {
    _brightnessTimer?.cancel();
    _queuedBrightness = null;
    super.dispose();
  }

  Future<void> _setAutoBrightness(bool value) async {
    if (updating ||
        _sendingBrightness ||
        _queuedBrightness != null ||
        _draggingBrightness) {
      return;
    }
    setState(() => updating = true);
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
              updating:
                  updating ||
                  _sendingBrightness ||
                  _queuedBrightness != null ||
                  _draggingBrightness,
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
