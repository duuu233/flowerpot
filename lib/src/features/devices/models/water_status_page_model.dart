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

  /// [language] 决定文案取中文还是英文表，见 [TuyaStatusCopy]。
  factory WaterStatusPageModel.fromDevice(
    SmartPlanterDevice device, {
    String language = 'zh',
  }) {
    final waterLevel = device.sensors.waterLevel;
    // `water_needs_status` (DP 107)，设备没上报时按水仓水位兜底。页面顶部的状态
    // 文字和说明都来自 TuyaStatusCopy，首页那张卡片读的是同一张表。
    final needs =
        device.status.waterNeeds ?? TuyaStatusCopy.waterNeedsFor(waterLevel);
    final copy = TuyaStatusCopy.waterNeedsCopy(needs, language: language);
    return WaterStatusPageModel(
      deviceId: device.id,
      status: copy.label,
      description: copy.description,
      waterLevel: waterLevel,
      soilMoisture: device.sensors.soilMoisture,
      // 养护建议由产品统一给稿，和状态文字同一张表，见 TuyaStatusCopy。
      advice: copy.advice,
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final int waterLevel;
  final int soilMoisture;
  final String advice;
}
