import '../../../tuya/tuya_models.dart';

/// 显示页：DP117 自动亮度开关 + DP168 手动亮度（`docs/app_DP_问题修正说明.md` §6）。
class DisplaySettingsPageModel {
  const DisplaySettingsPageModel({
    required this.autoBrightnessEnabled,
    required this.manualBrightness,
    this.productName = '设备',
  });

  factory DisplaySettingsPageModel.fromSettings(
    DeviceControlSettings settings, {
    String productName = '设备',
  }) {
    return DisplaySettingsPageModel(
      autoBrightnessEnabled: settings.autoBrightness,
      manualBrightness: settings.manualBrightness,
      productName: productName,
    );
  }

  final bool autoBrightnessEnabled;

  /// 0~100，0 = 灭屏；只在自动亮度关闭时生效。
  final int manualBrightness;

  /// 文案里称呼设备的名字：涂鸦产品名（[FlowerpotState.productNameLabel]）。
  final String productName;

  String get status => autoBrightnessEnabled ? '已开启' : '已关闭';

  List<String> get descriptionLines => autoBrightnessEnabled
      ? <String>[
          '自动屏幕亮度开启后，$productName会根据检测到的环境',
          '光强度自动调节屏幕亮度；关闭后可手动调节亮度。',
        ]
      : const <String>['自动屏幕亮度已关闭，屏幕亮度按下方设置显示，', '调到 0 时屏幕熄灭。'];

  String get description => descriptionLines.join('\n');
}
