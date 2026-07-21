import 'package:flutter/material.dart';

import '../../models/hearing_settings_page_model.dart';
import 'device_sensitivity_settings_card.dart';
import 'setting_orbit_illustration.dart';

class HearingSettingsCard extends StatelessWidget {
  const HearingSettingsCard({
    required this.model,
    required this.sensitivity,
    required this.onSoundInteractionChanged,
    required this.onSensitivityChanged,
    required this.onSensitivityChangeEnd,
    super.key,
    this.updatingInteraction = false,
    this.updatingSensitivity = false,
  });

  final HearingSettingsPageModel model;
  final double sensitivity;
  final ValueChanged<bool>? onSoundInteractionChanged;
  final ValueChanged<double>? onSensitivityChanged;
  final ValueChanged<double>? onSensitivityChangeEnd;
  final bool updatingInteraction;
  final bool updatingSensitivity;

  @override
  Widget build(BuildContext context) {
    return DeviceSensitivitySettingsCard(
      symbol: DeviceSettingSymbol.sound,
      title: '声音互动',
      status: model.status,
      description: model.description,
      descriptionLines: model.descriptionLines,
      interactionEnabled: model.soundInteractionEnabled,
      interactionSwitchKey: const Key('sound-interaction-switch'),
      sensitivity: sensitivity,
      sensitivitySliderKey: const Key('sound-sensitivity-slider'),
      updatingInteraction: updatingInteraction,
      updatingSensitivity: updatingSensitivity,
      onInteractionChanged: onSoundInteractionChanged,
      onSensitivityChanged: onSensitivityChanged,
      onSensitivityChangeEnd: onSensitivityChangeEnd,
    );
  }
}
