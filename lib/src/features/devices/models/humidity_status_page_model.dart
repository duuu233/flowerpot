import '../../../tuya/tuya_models.dart';
import '../../../tuya/tuya_status_copy.dart';

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
    // `air_humidity_status` (DP 115)，设备没上报时按相对湿度兜底。
    final level =
        device.status.humidity ?? TuyaStatusCopy.humidityFor(humidity);
    final copy = TuyaStatusCopy.airHumidity[level]!;
    return HumidityStatusPageModel(
      deviceId: device.id,
      status: copy.label,
      description: copy.description,
      humidity: humidity,
      // 原来这句无论干湿都写「当前湿度适宜」，和上面的状态文字直接打架。
      advice: switch (level) {
        ComfortLevel.low => '空气偏干，可在花盆附近放一杯水或开加湿器，缓解叶片失水。',
        ComfortLevel.suitable => '当前湿度适宜，继续保持现有养护环境，有助于植物健康生长。',
        ComfortLevel.high => '空气偏潮，请加强通风，避免叶面长时间凝结水膜诱发病害。',
      },
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final int humidity;
  final String advice;
}
