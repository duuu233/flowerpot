import '../../../tuya/tuya_models.dart';

class TouchSettingsPageModel {
  const TouchSettingsPageModel({
    required this.touchInteractionEnabled,
    required this.sensitivity,
    this.productName = '设备',
  });

  factory TouchSettingsPageModel.fromSettings(
    DeviceControlSettings settings, {
    String productName = '设备',
  }) {
    return TouchSettingsPageModel(
      touchInteractionEnabled: settings.touchInteraction,
      sensitivity: settings.touchSensitivity.clamp(0, 100),
      productName: productName,
    );
  }

  final bool touchInteractionEnabled;
  final int sensitivity;

  /// 文案里称呼设备的名字：涂鸦产品名（[FlowerpotState.productNameLabel]）。
  final String productName;

  String get status => touchInteractionEnabled ? '已启用' : '已禁用';

  List<String> get descriptionLines => <String>[
    '$productName可以通过它的植物与身体感知人类触摸。',
  ];

  String get description => descriptionLines.join('\n');
}
