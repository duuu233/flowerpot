import '../../../tuya/tuya_models.dart';
import '../../../tuya/tuya_status_copy.dart';

/// 需水状态页曲线画的指标。2026-11-23 起只剩水仓水位：土壤湿度（DP 106）改成
/// 只报 dry / moderate 档位，134–136 历史不再上报，「土壤湿度变化」曲线和切换菜单
/// 一并去掉。
enum WaterStatusMetric {
  waterLevel;

  SensorMetric get sensorMetric => switch (this) {
    WaterStatusMetric.waterLevel => SensorMetric.waterLevel,
  };

  String get label => switch (this) {
    WaterStatusMetric.waterLevel => '水仓水位变化',
  };

  String get unit => switch (this) {
    WaterStatusMetric.waterLevel => 'ml',
  };

  /// 曲线纵轴上限，取功能点导出里的量程：水位 131–133 / DP 105 是 0–200 mL。
  /// 以前沿用图表默认的 100，超过 100 mL 的点全被压在顶线上。
  double get chartMax => switch (this) {
    WaterStatusMetric.waterLevel => 200,
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

  /// 这一页读的实时 / 状态 DP，进页面时连同原始上报值记进联调日志
  /// （`FlowerpotState.logStatusDps`）。和 [fromDevice] 里实际取的字段一一对应。
  /// 历史曲线另走 131–133，见 `TuyaConfig.history` 的 waterLevel。
  static const reportedDps = <String>[
    'water_level', // 105
    'soil_moist', // 106，枚举 dry / moderate
    'water_needs_status', // 107
  ];

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
      // 106 只显示档位文字，不显示数值（2026-11-23 产品口径）。
      soilMoisture: TuyaStatusCopy.soilMoistureLabel(
        device.status.soilMoisture,
        language: language,
      ),
      // 养护建议由产品统一给稿，和状态文字同一张表，见 TuyaStatusCopy。
      advice: copy.advice,
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final int waterLevel;

  /// DP 106 的档位文字：干燥 / 适中，没上报为「--」。
  final String soilMoisture;
  final String advice;
}
