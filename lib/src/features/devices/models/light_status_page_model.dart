import '../../../tuya/tuya_models.dart';

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
    final status = switch (illuminance) {
      < 500 => '偏低',
      > 1200 => '充足',
      _ => '一般',
    };
    final description = switch (status) {
      '偏低' => '当前光照低于植物光合作用补偿点，植物新陈代谢水平较低。',
      '充足' => '当前光照能够满足植物生长需求，请避免长时间强光直射。',
      _ => '光照强度高略于植物光合作用补偿点。植物新陈代谢水平较低。',
    };
    final advice = switch (status) {
      '偏低' => '当前光照略低于植物光合作用补偿点，建议将植物移至明亮散射光处，或每天补光1-2小时。',
      '充足' => '当前光照较为充足，建议保持稳定的明亮散射光，并留意叶片是否出现灼伤。',
      _ => '当前光照接近植物适宜范围，建议保持现有位置并持续观察每日光量积分。',
    };
    return LightStatusPageModel(
      deviceId: device.id,
      status: status,
      description: description,
      illuminance: illuminance,
      ppfd: device.sensors.ppfd.toDouble(),
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
