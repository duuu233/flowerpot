import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/hearing_settings_page_model.dart';
import 'widgets/hearing_settings_card.dart';

class HearingSettingsPage extends StatefulWidget {
  const HearingSettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<HearingSettingsPage> createState() => _HearingSettingsPageState();
}

class _HearingSettingsPageState extends State<HearingSettingsPage> {
  bool updatingInteraction = false;
  bool updatingSensitivity = false;
  double? pendingSensitivity;

  Future<void> _setSoundInteraction(bool value) async {
    if (updatingInteraction) return;
    setState(() => updatingInteraction = true);
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'soundInteraction', value);
    if (!mounted) return;
    setState(() => updatingInteraction = false);
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
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
    ).updateSetting(widget.deviceId, 'soundSensitivity', sensitivity);
    if (!mounted) return;
    setState(() {
      updatingSensitivity = false;
      pendingSensitivity = null;
    });
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '听觉感知', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final model = HearingSettingsPageModel.fromSettings(device.settings);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '听觉感知', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('hearing-settings-scroll-view'),
        child: ResponsiveContent(
          maxWidth: 375,
          padding: const EdgeInsets.fromLTRB(20, 37, 20, 40),
          child: HearingSettingsCard(
            model: model,
            sensitivity: pendingSensitivity ?? model.sensitivity.toDouble(),
            updatingInteraction: updatingInteraction,
            updatingSensitivity: updatingSensitivity,
            onSoundInteractionChanged: _setSoundInteraction,
            onSensitivityChanged: _previewSensitivity,
            onSensitivityChangeEnd: _setSensitivity,
          ),
        ),
      ),
    );
  }
}
