import 'package:flutter/material.dart';

import '../../models/touch_settings_page_model.dart';
import 'device_sensitivity_settings_card.dart';
import 'setting_orbit_illustration.dart';

class TouchSettingsCard extends StatelessWidget {
  const TouchSettingsCard({
    required this.model,
    required this.sensitivity,
    required this.onTouchInteractionChanged,
    required this.onSensitivityChanged,
    required this.onSensitivityChangeEnd,
    super.key,
    this.updatingInteraction = false,
    this.updatingSensitivity = false,
  });

  final TouchSettingsPageModel model;
  final double sensitivity;
  final ValueChanged<bool>? onTouchInteractionChanged;
  final ValueChanged<double>? onSensitivityChanged;
  final ValueChanged<double>? onSensitivityChangeEnd;
  final bool updatingInteraction;
  final bool updatingSensitivity;

  @override
  Widget build(BuildContext context) {
    return DeviceSensitivitySettingsCard(
      symbol: DeviceSettingSymbol.touch,
      title: '触摸交互',
      status: model.status,
      description: model.description,
      descriptionLines: model.descriptionLines,
      interactionEnabled: model.touchInteractionEnabled,
      interactionSwitchKey: const Key('touch-interaction-switch'),
      sensitivity: sensitivity,
      sensitivitySliderKey: const Key('touch-sensitivity-slider'),
      updatingInteraction: updatingInteraction,
      updatingSensitivity: updatingSensitivity,
      onInteractionChanged: onTouchInteractionChanged,
      onSensitivityChanged: onSensitivityChanged,
      onSensitivityChangeEnd: onSensitivityChangeEnd,
    );
  }
}
