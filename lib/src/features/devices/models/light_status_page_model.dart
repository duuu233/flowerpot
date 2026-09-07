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

  factory LightStatusPageModel.fromDevice(
    SmartPlanterDevice device, {
    List<double> dliValues = const <double>[],
  }) {
    final illuminance = device.sensors.illuminance;
    // `lighting_condition` (DP 108)，设备没上报时按照度兜底。
    final condition =
        device.status.lighting ?? TuyaStatusCopy.lightingFor(illuminance);
    final copy = TuyaStatusCopy.lighting[condition]!;
    final advice = switch (condition) {
      LightingCondition.shortage =>
        '当前光照略低于植物光合作用补偿点，建议将植物移至明亮散射光处，或每天补光1-2小时。',
      LightingCondition.good => '当前光照基本够用，建议保持在明亮散射光处；若叶色变浅可每天补光1小时。',
      LightingCondition.veryGood => '当前光照较为充足，建议保持稳定的明亮散射光，并留意叶片是否出现灼伤。',
    };
    return LightStatusPageModel(
      deviceId: device.id,
      status: copy.label,
      description: copy.description,
      illuminance: illuminance,
      ppfd: device.sensors.ppfd,
      dliValues: dliValues,
      advice: advice,
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
