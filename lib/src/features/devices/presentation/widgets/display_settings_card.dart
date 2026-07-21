import 'package:flutter/material.dart';

import '../../models/display_settings_page_model.dart';
import 'device_toggle_settings_card.dart';
import 'setting_orbit_illustration.dart';

class DisplaySettingsCard extends StatelessWidget {
  const DisplaySettingsCard({
    required this.model,
    required this.onAutoBrightnessChanged,
    super.key,
    this.updating = false,
  });

  final DisplaySettingsPageModel model;
  final ValueChanged<bool>? onAutoBrightnessChanged;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    return DeviceToggleSettingsCard(
      symbol: DeviceSettingSymbol.brightness,
      title: '自动屏幕亮度',
      status: model.status,
      description: model.description,
      descriptionLines: model.descriptionLines,
      value: model.autoBrightnessEnabled,
      switchKey: const Key('auto-brightness-switch'),
      updating: updating,
      onChanged: onAutoBrightnessChanged,
    );
  }
}
