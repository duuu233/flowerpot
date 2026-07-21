import 'package:flutter/material.dart';

import '../../models/vibration_settings_page_model.dart';
import 'device_toggle_settings_card.dart';
import 'setting_orbit_illustration.dart';

class VibrationSettingsCard extends StatelessWidget {
  const VibrationSettingsCard({
    required this.model,
    required this.onVibrationChanged,
    super.key,
    this.updating = false,
  });

  final VibrationSettingsPageModel model;
  final ValueChanged<bool>? onVibrationChanged;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    return DeviceToggleSettingsCard(
      symbol: DeviceSettingSymbol.vibration,
      title: '启动震动',
      status: model.status,
      description: model.description,
      descriptionLines: model.descriptionLines,
      value: model.vibrationEnabled,
      switchKey: const Key('vibration-switch'),
      updating: updating,
      onChanged: onVibrationChanged,
    );
  }
}
