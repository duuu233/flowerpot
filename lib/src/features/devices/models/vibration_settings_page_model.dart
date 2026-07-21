import '../../../tuya/tuya_models.dart';

class VibrationSettingsPageModel {
  const VibrationSettingsPageModel({required this.vibrationEnabled});

  factory VibrationSettingsPageModel.fromSettings(
    DeviceControlSettings settings,
  ) {
    return VibrationSettingsPageModel(vibrationEnabled: settings.vibration);
  }

  final bool vibrationEnabled;

  String get status => vibrationEnabled ? '已启用' : '已禁用';

  List<String> get descriptionLines => const <String>[
    '开启后，YSplanter将在触摸操作、缺水警报及番茄钟',
    '提醒等情况自动触发振动。',
  ];

  String get description => descriptionLines.join('\n');
}
