import '../../../tuya/tuya_models.dart';

class HumidityStatusPageModel {
  const HumidityStatusPageModel({
    required this.deviceId,
    required this.status,
    required this.description,
    required this.humidity,
    required this.advice,
  });

  factory HumidityStatusPageModel.fromDevice(SmartPlanterDevice device) {
    final humidity = device.sensors.relativeHumidity;
    final status = switch (humidity) {
      < 40 => '偏低',
      > 70 => '偏高',
      _ => '适宜',
    };
    final description = switch (status) {
      '偏低' => '当前相对湿度偏低，请适当增加环境湿度。',
      '偏高' => '当前相对湿度偏高，请保持环境通风。',
      _ => '相对湿度适宜植物生长。',
    };
    return HumidityStatusPageModel(
      deviceId: device.id,
      status: status,
      description: description,
      humidity: humidity,
      advice: '当前湿度适宜，继续保持现有养护环境，有助于植物健康生长。',
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final int humidity;
  final String advice;
}
