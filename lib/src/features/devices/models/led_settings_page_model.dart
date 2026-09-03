import '../../../tuya/tuya_models.dart';

/// The LED page is a single switch, laid out like 震动设置.
///
/// It rides on `disp_brightness_switch` (DP 117, 显示屏幕亮度开关): the
/// 2026-09-03 platform export has no separate LED function point, and 117 is
/// the only on/off the firmware exposes for the light the planter shows. The
/// 显示 page presents the same DP as 「自动屏幕亮度」, so the two rows move
/// together — repointing this at a real LED DP is one line in
/// `TuyaConfig.setting` once the firmware adds one.
class LedSettingsPageModel {
  const LedSettingsPageModel({required this.ledEnabled});

  factory LedSettingsPageModel.fromSettings(DeviceControlSettings settings) =>
      LedSettingsPageModel(ledEnabled: settings.autoBrightness);

  final bool ledEnabled;

  String get status => ledEnabled ? '已开启' : '已关闭';

  List<String> get descriptionLines => const <String>[
    '关闭后，YSplanter的屏幕指示灯将不再亮起，',
    '设备仍会正常记录数据并推送提醒。',
  ];

  String get description => descriptionLines.join('\n');
}
