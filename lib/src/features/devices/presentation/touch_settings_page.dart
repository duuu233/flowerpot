import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/touch_settings_page_model.dart';
import 'device_online_guard.dart';
import 'widgets/touch_settings_card.dart';

class TouchSettingsPage extends StatefulWidget {
  const TouchSettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<TouchSettingsPage> createState() => _TouchSettingsPageState();
}

class _TouchSettingsPageState extends State<TouchSettingsPage> {
  bool updatingInteraction = false;
  bool updatingSensitivity = false;
  double? pendingSensitivity;

  Future<void> _setTouchInteraction(bool value) async {
    if (updatingInteraction) return;
    setState(() => updatingInteraction = true);
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'touchInteraction', value);
    if (!mounted) return;
    setState(() => updatingInteraction = false);
    if (!result.success) {
      showDeviceActionResult(context, result);
    }
  }

  void _previewSensitivity(double value) {
    setState(() => pendingSensitivity = value);
  }

  Future<void> _setSensitivity(double value) async {
    if (updatingSensitivity) return;
    final sensitivity = value.round().clamp(0, 100);
    setState(() {
      updatingSensitivity = true;
      pendingSensitivity = sensitivity.toDouble();
    });
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'touchSensitivity', sensitivity);
    if (!mounted) return;
    setState(() {
      updatingSensitivity = false;
      pendingSensitivity = null;
    });
    if (!result.success) {
      showDeviceActionResult(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '触觉感知', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final model = TouchSettingsPageModel.fromSettings(device.settings);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '触觉感知', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('touch-settings-scroll-view'),
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            37,
            AppSpacing.pageMargin,
            40,
          ),
          child: TouchSettingsCard(
            model: model,
            sensitivity: pendingSensitivity ?? model.sensitivity.toDouble(),
            updatingInteraction: updatingInteraction,
            updatingSensitivity: updatingSensitivity,
            onTouchInteractionChanged: _setTouchInteraction,
            onSensitivityChanged: _previewSensitivity,
            onSensitivityChangeEnd: _setSensitivity,
          ),
        ),
      ),
    );
  }
}
