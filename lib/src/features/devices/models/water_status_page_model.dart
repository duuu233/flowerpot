import '../../../tuya/tuya_models.dart';
import '../../../tuya/tuya_status_copy.dart';

enum WaterStatusMetric {
  waterLevel,
  soilMoisture;

  SensorMetric get sensorMetric => switch (this) {
    WaterStatusMetric.waterLevel => SensorMetric.waterLevel,
    WaterStatusMetric.soilMoisture => SensorMetric.soilMoisture,
  };

  String get label => switch (this) {
    WaterStatusMetric.waterLevel => '水仓水位变化',
    WaterStatusMetric.soilMoisture => '土壤湿度变化',
  };

  String get unit => switch (this) {
    WaterStatusMetric.waterLevel => 'ml',
    WaterStatusMetric.soilMoisture => '%',
  };
}

class WaterStatusArguments {
  const WaterStatusArguments({
    required this.deviceId,
    this.initialMetric = WaterStatusMetric.waterLevel,
  });

  final String deviceId;
  final WaterStatusMetric initialMetric;
}

class WaterStatusPageModel {
  const WaterStatusPageModel({
    required this.deviceId,
    required this.status,
    required this.description,
    required this.waterLevel,
    required this.soilMoisture,
    required this.advice,
  });

  factory WaterStatusPageModel.fromDevice(SmartPlanterDevice device) {
    final waterLevel = device.sensors.waterLevel;
    // `water_needs_status` (DP 107)，设备没上报时按水仓水位兜底。页面顶部的状态
    // 文字和说明都来自 TuyaStatusCopy，首页那张卡片读的是同一张表。
    final needs =
        device.status.waterNeeds ?? TuyaStatusCopy.waterNeedsFor(waterLevel);
    final copy = TuyaStatusCopy.waterNeeds[needs]!;
    return WaterStatusPageModel(
      deviceId: device.id,
      status: copy.label,
      description: copy.description,
      waterLevel: waterLevel,
      soilMoisture: device.sensors.soilMoisture,
      advice: switch (needs) {
        WaterNeedsStatus.shortage => '请向水仓缓慢补水，并留意土壤湿度变化，避免一次加入过多水分。',
        WaterNeedsStatus.drinking => '当前湿度适宜，建议保持现有浇水频率，避免盆土长期过湿，确保植物根系健康。',
        WaterNeedsStatus.watery => '请暂停补水并保持通风，等水位回落后再恢复原来的浇水频率。',
      },
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final int waterLevel;
  final int soilMoisture;
  final String advice;
}
