import '../../../tuya/tuya_models.dart';

class DisplaySettingsPageModel {
  const DisplaySettingsPageModel({required this.autoBrightnessEnabled});

  factory DisplaySettingsPageModel.fromSettings(
    DeviceControlSettings settings,
  ) {
    return DisplaySettingsPageModel(
      autoBrightnessEnabled: settings.autoBrightness,
    );
  }

  final bool autoBrightnessEnabled;

  String get status => autoBrightnessEnabled ? '已开启' : '已关闭';

  List<String> get descriptionLines => const <String>[
    '自动屏幕亮度开启后，YSplanter会根据检测到的环境',
    '光强度自动调节屏幕亮度。',
  ];

  String get description => descriptionLines.join('\n');
}
