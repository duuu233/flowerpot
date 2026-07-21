import '../../../tuya/tuya_models.dart';

class HearingSettingsPageModel {
  const HearingSettingsPageModel({
    required this.soundInteractionEnabled,
    required this.sensitivity,
  });

  factory HearingSettingsPageModel.fromSettings(
    DeviceControlSettings settings,
  ) {
    return HearingSettingsPageModel(
      soundInteractionEnabled: settings.soundInteraction,
      sensitivity: settings.soundSensitivity.clamp(0, 100),
    );
  }

  final bool soundInteractionEnabled;
  final int sensitivity;

  String get status => soundInteractionEnabled ? '已开启' : '已关闭';

  List<String> get descriptionLines => const <String>[
    'YSplanter可以听到声音与振动，并产生多种多样的独',
    '特反馈。',
  ];

  String get description => descriptionLines.join('\n');
}
