import '../../../tuya/tuya_models.dart';

class VibrationSettingsPageModel {
  const VibrationSettingsPageModel({
    required this.vibrationEnabled,
    this.keyVibrationEnabled = true,
    this.plantVibrationEnabled = true,
  });

  factory VibrationSettingsPageModel.fromSettings(
    DeviceControlSettings settings,
  ) {
    return VibrationSettingsPageModel(
      vibrationEnabled: settings.vibration,
      keyVibrationEnabled: settings.touchKeyVibration,
      plantVibrationEnabled: settings.touchPlantVibration,
    );
  }

  final bool vibrationEnabled;

  /// `touch_vib_switch` (123) and `touch_plant_vib_switch` (124): the two
  /// scenes the device vibrates in, each its own writable function point.
  final bool keyVibrationEnabled;
  final bool plantVibrationEnabled;

  String get status => vibrationEnabled ? '已启用' : '已禁用';

  List<String> get descriptionLines => const <String>[
    '开启后，YSplanter将在触摸操作、缺水警报提醒',
    '等情况自动触发振动。',
  ];

  String get description => descriptionLines.join('\n');
}
