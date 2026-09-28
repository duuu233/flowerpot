import '../../../tuya/tuya_models.dart';

/// The LED page is a single switch, laid out like 震动设置.
///
/// 背后是 `led_switch`（DP 166，双色 LED 灯效总开关，2026-09-28 固件新增，默认关）。
/// 原来固件没有单独的 LED 功能点，和「显示」页共用 117；新 DP 说明写明 117 是屏幕背光、
/// 166 是双色 LED，两个独立开关，所以两页不再联动。
class LedSettingsPageModel {
  const LedSettingsPageModel({required this.ledEnabled});

  factory LedSettingsPageModel.fromSettings(DeviceControlSettings settings) =>
      LedSettingsPageModel(ledEnabled: settings.ledEnabled);

  final bool ledEnabled;

  String get status => ledEnabled ? '已开启' : '已关闭';

  /// 2026-09-28 产品改文案（背后已是 DP166 双色 LED，不再是屏幕指示灯）。
  List<String> get descriptionLines => const <String>[
    '关闭后，YSplanter的双色 LED 灯效将不再亮起',
  ];

  String get description => descriptionLines.join('\n');
}
