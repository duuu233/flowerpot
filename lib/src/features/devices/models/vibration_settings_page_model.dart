import '../../../tuya/tuya_models.dart';

class VibrationSettingsPageModel {
  const VibrationSettingsPageModel({
    required this.vibrationEnabled,
    this.keyVibrationEnabled = true,
    this.plantVibrationEnabled = true,
    this.productName = '设备',
  });

  factory VibrationSettingsPageModel.fromSettings(
    DeviceControlSettings settings, {
    String productName = '设备',
  }) {
    return VibrationSettingsPageModel(
      vibrationEnabled: settings.vibration,
      keyVibrationEnabled: settings.touchKeyVibration,
      plantVibrationEnabled: settings.touchPlantVibration,
      productName: productName,
    );
  }

  final bool vibrationEnabled;

  /// `touch_vib_switch` (123) and `touch_plant_vib_switch` (124): the two
  /// scenes the device vibrates in, each its own writable function point.
  final bool keyVibrationEnabled;
  final bool plantVibrationEnabled;

  /// 文案里称呼设备的名字：涂鸦产品名（[FlowerpotState.productNameLabel]）。
  final String productName;

  String get status => vibrationEnabled ? '已启用' : '已禁用';

  List<String> get descriptionLines => <String>[
    '开启后，$productName将在触摸操作、缺水警报提醒',
    '等情况自动触发振动。',
  ];

  String get description => descriptionLines.join('\n');
}
