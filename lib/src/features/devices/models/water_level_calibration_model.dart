/// 水位校准向导（`docs/app_DP_问题修正说明.md` §5，固件 1.0.16 起的新编号语义）。
///
/// 页面顺序：入口 → 1/4 倒空 → 2/4 加 20 mL → 3/4 再加 20 mL → 4/4 保存 → 结果。
/// **采样发生在 DP140 报文到达的瞬间**，所以每一页的文案都是「点按钮之前要做完的事」，
/// 点了按钮才发这一页对应的 DP140 值。
enum WaterLevelCalibrationVisual {
  emptyReservoir,
  firstPour,
  secondPour,
  completed,
}

class WaterLevelCalibrationStepModel {
  const WaterLevelCalibrationStepModel({
    required this.dpValue,
    required this.instruction,
    required this.primaryActionLabel,
    required this.visual,
    required this.semanticLabel,
    this.waitBeforeSample = false,
  });

  /// 点主按钮时下发的 DP140 值（0~4）。
  final int dpValue;
  final String instruction;
  final String primaryActionLabel;
  final WaterLevelCalibrationVisual visual;
  final String semanticLabel;

  /// 这一步和上一次采样之间要隔 ≥5 秒（1→2、2→3）：按钮先置灰倒计时。
  final bool waitBeforeSample;
}

abstract final class WaterLevelCalibrationModel {
  static const String title = '水位传感器校准';

  /// 采样步之间的最小间隔。
  static const Duration sampleInterval = Duration(seconds: 5);

  /// 设备看门狗：单步超过 3 分钟没动静就自动取消。
  static const Duration stepTimeout = Duration(minutes: 3);

  /// 入口页：点「开始校准」发 0，设备进校准页并提示倒空（不采样）。
  static const WaterLevelCalibrationStepModel entry =
      WaterLevelCalibrationStepModel(
        dpValue: 0,
        instruction: '校准需要约 1 分钟，请准备好 40 mL 清水。\n点击“开始校准”后按提示操作。',
        primaryActionLabel: '开始校准',
        visual: WaterLevelCalibrationVisual.emptyReservoir,
        semanticLabel: '水位传感器校准示意图',
      );

  /// 1/4 ~ 4/4。
  static const List<WaterLevelCalibrationStepModel> steps =
      <WaterLevelCalibrationStepModel>[
        WaterLevelCalibrationStepModel(
          dpValue: 1,
          instruction: '请将水箱中的水完全倒空，\n静置数秒。',
          primaryActionLabel: '已倒空，记录空杯',
          visual: WaterLevelCalibrationVisual.emptyReservoir,
          semanticLabel: '移出植物内胆并倒空水箱示意图',
        ),
        WaterLevelCalibrationStepModel(
          dpValue: 2,
          instruction: '请加入 20 mL 水，\n静置 5 秒以上。',
          primaryActionLabel: '已加入，记录',
          visual: WaterLevelCalibrationVisual.firstPour,
          semanticLabel: '向水箱加入20毫升水示意图',
          waitBeforeSample: true,
        ),
        WaterLevelCalibrationStepModel(
          dpValue: 3,
          instruction: '请再加入 20 mL 水（累计 40 mL），\n静置 5 秒以上。',
          primaryActionLabel: '已加入，记录',
          visual: WaterLevelCalibrationVisual.secondPour,
          semanticLabel: '再次向水箱加入20毫升水示意图',
          waitBeforeSample: true,
        ),
        WaterLevelCalibrationStepModel(
          dpValue: 4,
          instruction: '点击后设备将计算\n并保存校准值。',
          primaryActionLabel: '完成校准',
          visual: WaterLevelCalibrationVisual.completed,
          semanticLabel: '保存水位校准示意图',
        ),
      ];
}
