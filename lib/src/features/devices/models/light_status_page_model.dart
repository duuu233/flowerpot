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
      < 200 => '偏低',
      > 1200 => '充足',
      _ => '一般',
    };
    final description = switch (status) {
      '偏低' => '当前光照低于植物光合作用补偿点，植物新陈代谢水平较低。',
      '充足' => '当前光照能够满足植物生长需求，请避免长时间强光直射。',
      // Previously said the light was *above* the compensation point while the
      // advice below said it was below it, and 「高略于」 was a typo.
      _ => '当前光照略高于植物光合作用补偿点，可以维持正常的新陈代谢。',
    };
    final advice = switch (status) {
      '偏低' => '当前光照略低于植物光合作用补偿点，建议将植物移至明亮散射光处，或每天补光1-2小时。',
      '充足' => '当前光照较为充足，建议保持稳定的明亮散射光，并留意叶片是否出现灼伤。',
      _ => '当前光照基本够用，建议保持在明亮散射光处；若叶色变浅可每天补光1小时。',
    };
    return LightStatusPageModel(
      deviceId: device.id,
      status: status,
      description: description,
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
