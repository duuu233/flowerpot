enum WaterLevelCalibrationVisual {
  emptyReservoir,
  firstPour,
  secondPour,
  completed,
}

class WaterLevelCalibrationStepModel {
  const WaterLevelCalibrationStepModel({
    required this.instruction,
    required this.visual,
    required this.semanticLabel,
    this.secondaryActionLabel = '取消',
    this.primaryActionLabel = '下一步',
  });

  final String instruction;
  final WaterLevelCalibrationVisual visual;
  final String semanticLabel;
  final String secondaryActionLabel;
  final String primaryActionLabel;
}

abstract final class WaterLevelCalibrationModel {
  static const String title = '水位传感器校准';

  static const List<WaterLevelCalibrationStepModel> steps =
      <WaterLevelCalibrationStepModel>[
        WaterLevelCalibrationStepModel(
          instruction: '请先移出植物内胆，\n并倒空水仓中的剩余水。',
          visual: WaterLevelCalibrationVisual.emptyReservoir,
          semanticLabel: '移出植物内胆并倒空水仓示意图',
        ),
        WaterLevelCalibrationStepModel(
          instruction: '请向水仓中倒入30mL水，\n并点击“下一步”确认',
          visual: WaterLevelCalibrationVisual.firstPour,
          semanticLabel: '向水仓倒入30毫升水示意图',
        ),
        WaterLevelCalibrationStepModel(
          instruction: '请再次向水仓中倒入30mL水，\n并再次点击“下一步”确认',
          visual: WaterLevelCalibrationVisual.secondPour,
          semanticLabel: '再次向水仓倒入30毫升水示意图',
        ),
        WaterLevelCalibrationStepModel(
          instruction: '校准完成！',
          visual: WaterLevelCalibrationVisual.completed,
          semanticLabel: '水位传感器校准完成',
          secondaryActionLabel: '关闭',
          primaryActionLabel: '完成',
        ),
      ];
}
