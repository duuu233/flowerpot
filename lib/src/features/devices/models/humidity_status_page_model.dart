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

  /// 这一页读的实时 / 状态 DP，写法同 `WaterStatusPageModel.reportedDps`。
  /// 功能点表里**没有空气湿度历史 DP**，曲线只能是空态。
  static const reportedDps = <String>[
    'air_humidity', // 114，倍数 1：原值 ÷10
    'air_humidity_status', // 115
  ];

  /// [language] 决定文案取中文还是英文表，见 [TuyaStatusCopy]。
  factory HumidityStatusPageModel.fromDevice(
    SmartPlanterDevice device, {
    String language = 'zh',
  }) {
    final humidity = device.sensors.relativeHumidity;
    // `air_humidity_status` (DP 115)，设备没上报时按相对湿度兜底。
    final level =
        device.status.humidity ?? TuyaStatusCopy.humidityFor(humidity);
    final copy = TuyaStatusCopy.airHumidityCopy(level, language: language);
    return HumidityStatusPageModel(
      deviceId: device.id,
      status: copy.label,
      description: copy.description,
      humidity: humidity,
      // 养护建议由产品统一给稿，和状态文字同一张表，见 TuyaStatusCopy。
      advice: copy.advice,
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final int humidity;
  final String advice;
}
