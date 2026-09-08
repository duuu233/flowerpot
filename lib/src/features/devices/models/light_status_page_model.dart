import '../../../tuya/tuya_models.dart';
import '../../../tuya/tuya_status_copy.dart';

class LightStatusPageModel {
  const LightStatusPageModel({
    required this.deviceId,
    required this.status,
    required this.description,
    required this.illuminance,
    required this.ppfd,
    required this.dliValues,
    required this.advice,
  });

  /// [language] 决定文案取中文还是英文表，见 [TuyaStatusCopy]。
  factory LightStatusPageModel.fromDevice(
    SmartPlanterDevice device, {
    List<double> dliValues = const <double>[],
    String language = 'zh',
  }) {
    final illuminance = device.sensors.illuminance;
    // `lighting_condition` (DP 108)，设备没上报时按照度兜底。
    final condition =
        device.status.lighting ?? TuyaStatusCopy.lightingFor(illuminance);
    final copy = TuyaStatusCopy.lightingCopy(condition, language: language);
    return LightStatusPageModel(
      deviceId: device.id,
      status: copy.label,
      description: copy.description,
      illuminance: illuminance,
      ppfd: device.sensors.ppfd,
      dliValues: dliValues,
      // 养护建议由产品统一给稿，和状态文字同一张表，见 TuyaStatusCopy。
      advice: copy.advice,
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final int illuminance;
  final double ppfd;
  final List<double> dliValues;
  final String advice;
}
