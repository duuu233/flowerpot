import '../../../tuya/tuya_models.dart';

class HearingSettingsPageModel {
  const HearingSettingsPageModel({
    required this.soundInteractionEnabled,
    required this.sensitivity,
    this.productName = '设备',
  });

  factory HearingSettingsPageModel.fromSettings(
    DeviceControlSettings settings, {
    String productName = '设备',
  }) {
    return HearingSettingsPageModel(
      soundInteractionEnabled: settings.soundInteraction,
      sensitivity: settings.soundSensitivity.clamp(0, 100),
      productName: productName,
    );
  }

  final bool soundInteractionEnabled;
  final int sensitivity;

  /// 文案里称呼设备的名字：涂鸦产品名（[FlowerpotState.productNameLabel]）。
  final String productName;

  String get status => soundInteractionEnabled ? '已开启' : '已关闭';

  List<String> get descriptionLines => <String>[
    '$productName可以听到声音与振动，并产生多种多样的独',
    '特反馈。',
  ];

  String get description => descriptionLines.join('\n');
}
