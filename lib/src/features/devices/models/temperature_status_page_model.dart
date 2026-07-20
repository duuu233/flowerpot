import '../../../tuya/tuya_models.dart';

class TemperatureStatusPageModel {
  const TemperatureStatusPageModel({
    required this.deviceId,
    required this.status,
    required this.description,
    required this.temperature,
    required this.advice,
  });

  factory TemperatureStatusPageModel.fromDevice(SmartPlanterDevice device) {
    final temperature = device.sensors.airTemperature;
    final status = switch (temperature) {
      < 18 => '偏低',
      > 28 => '偏高',
      _ => '适宜',
    };
    final description = switch (status) {
      '偏低' => '当前空气温度偏低，请注意为植物保暖。',
      '偏高' => '当前空气温度偏高，请保持环境通风。',
      _ => '温度适宜植物生长。',
    };
    return TemperatureStatusPageModel(
      deviceId: device.id,
      status: status,
      description: description,
      temperature: temperature,
      advice: '适宜温度范围为18°C~28°C。\n温度过高或过低都会影响植物健康生长哦。',
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final double temperature;
  final String advice;
}
