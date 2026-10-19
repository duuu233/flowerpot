import 'package:flutter/material.dart';

import '../../models/display_settings_page_model.dart';
import 'device_sensitivity_settings_card.dart';
import 'setting_orbit_illustration.dart';

/// 显示页卡片：上面是自动亮度开关（DP117），下面是手动亮度滑条（DP168）。
/// 自动亮度开着时手动亮度不生效，滑条锁住。
class DisplaySettingsCard extends StatelessWidget {
  const DisplaySettingsCard({
    required this.model,
    required this.brightness,
    required this.onAutoBrightnessChanged,
    required this.onBrightnessChanged,
    required this.onBrightnessChangeEnd,
    super.key,
    this.updating = false,
    this.updatingBrightness = false,
  });

  final DisplaySettingsPageModel model;
  final double brightness;
  final ValueChanged<bool>? onAutoBrightnessChanged;
  final ValueChanged<double>? onBrightnessChanged;
  final ValueChanged<double>? onBrightnessChangeEnd;
  final bool updating;
  final bool updatingBrightness;

  @override
  Widget build(BuildContext context) {
    return DeviceSensitivitySettingsCard(
      symbol: DeviceSettingSymbol.brightness,
      title: '自动屏幕亮度',
      status: model.status,
      description: model.description,
      descriptionLines: model.descriptionLines,
      interactionEnabled: model.autoBrightnessEnabled,
      interactionSwitchKey: const Key('auto-brightness-switch'),
      sensitivity: brightness,
      sensitivitySliderKey: const Key('manual-brightness-slider'),
      sliderLabel: '屏幕亮度',
      sliderLocked: model.autoBrightnessEnabled,
      updatingInteraction: updating,
      updatingSensitivity: updatingBrightness,
      onInteractionChanged: onAutoBrightnessChanged,
      onSensitivityChanged: onBrightnessChanged,
      onSensitivityChangeEnd: onBrightnessChangeEnd,
    );
  }
}
