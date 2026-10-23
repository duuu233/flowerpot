import '../../../tuya/tuya_models.dart';

class TouchSettingsPageModel {
  const TouchSettingsPageModel({
    required this.touchInteractionEnabled,
    required this.sensitivity,
  });

  factory TouchSettingsPageModel.fromSettings(DeviceControlSettings settings) {
    return TouchSettingsPageModel(
      touchInteractionEnabled: settings.touchInteraction,
      sensitivity: settings.touchSensitivity.clamp(0, 100),
    );
  }

  final bool touchInteractionEnabled;
  final int sensitivity;

  String get status => touchInteractionEnabled ? '已启用' : '已禁用';

  List<String> get descriptionLines => const <String>[
    '东方金穗可以通过它的植物与身体感知人类触摸。',
  ];

  String get description => descriptionLines.join('\n');
}
