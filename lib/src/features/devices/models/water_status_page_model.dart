import '../../../tuya/tuya_models.dart';

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
    // `water_needs_status` (DP 107) when the device has reported it, otherwise
    // the app's own reservoir threshold. The device separates 喝水中 from
    // 水分充足; both mean the reservoir still has water, which is the only
    // distinction this page draws.
    final hasReservoirWater = switch (device.status.waterNeeds) {
      WaterNeedsStatus.shortage => false,
      WaterNeedsStatus.drinking || WaterNeedsStatus.watery => true,
      null => waterLevel > 20,
    };
    return WaterStatusPageModel(
      deviceId: device.id,
      status: hasReservoirWater ? '喝水中' : '需要补水',
      description: hasReservoirWater
          ? '植物正在从水仓中直接吸取水分，请保持当前状态。'
          : '当前水仓水量不足，请及时加水，避免植物根系缺水。',
      waterLevel: waterLevel,
      soilMoisture: device.sensors.soilMoisture,
      advice: hasReservoirWater
          ? '当前湿度适宜，建议保持现有浇水频率，避免盆土长期过湿，确保植物根系健康。'
          : '请向水仓缓慢补水，并留意土壤湿度变化，避免一次加入过多水分。',
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final int waterLevel;
  final int soilMoisture;
  final String advice;
}
