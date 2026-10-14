import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/water_level_calibration_model.dart';

/// 下发弹窗**正要展示**的那一步，返回设备有没有收下。
///
/// `water_level_calib` 是一串阶段枚举、不是一条「开始校准」命令，所以每进入一张
/// 卡片就要把对应的 stepN 告诉设备：卡片上写的动作是「设备处在 stepN 时用户该做的事」，
/// 下发必须发生在用户动手之前。第一张卡片（倒空水仓）也一样——弹窗一出现就发 step0。
typedef WaterLevelCalibrationCallback = Future<bool> Function(int step);

/// Called when the user backs out before the sequence finishes.
typedef WaterLevelCalibrationCancel = Future<void> Function();

Future<bool> showWaterLevelCalibrationDialog(
  BuildContext context, {
  required WaterLevelCalibrationCallback onCalibrate,
  required WaterLevelCalibrationCancel onCancel,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .42),
        builder: (_) => WaterLevelCalibrationDialog(
          onCalibrate: onCalibrate,
          onCancel: onCancel,
        ),
      ) ??
      false;
}

class WaterLevelCalibrationDialog extends StatefulWidget {
  const WaterLevelCalibrationDialog({
    required this.onCalibrate,
    required this.onCancel,
    super.key,
  });

  final WaterLevelCalibrationCallback onCalibrate;
  final WaterLevelCalibrationCancel onCancel;

  @override
  State<WaterLevelCalibrationDialog> createState() =>
      _WaterLevelCalibrationDialogState();
}

class _WaterLevelCalibrationDialogState
    extends State<WaterLevelCalibrationDialog> {
  int _currentStep = 0;
  bool _submitting = false;

  /// 当前这张卡片对应的 stepN 有没有下发成功。
  ///
  /// 开场那次 step0 失败时停在 false，等用户点「下一步」时先补发——设备没进校准
  /// 模式，后面几步全是白发。到达后面几张卡片的前提就是它们的 step 已经发成功，
  /// 所以那几张卡上它恒为 true。
  bool _stepDelivered = false;

  WaterLevelCalibrationStepModel get _step =>
      WaterLevelCalibrationModel.steps[_currentStep];

  /// 最后那张「校准完成」卡片：step3 在它出现时就已经发过了，两个按钮都只是关闭。
  bool get _onSummaryStep =>
      _currentStep == WaterLevelCalibrationModel.steps.length - 1;

  @override
  void initState() {
    super.initState();
    // 第一步就要下发 step0：弹窗一出现设备就得进校准模式，不能等用户倒完水才发。
    // 放在首帧之后是因为下发失败要 setState 回显，initState 里还不能标记重建。
    WidgetsBinding.instance.addPostFrameCallback((_) => _deliverEntryStep());
  }

  Future<void> _deliverEntryStep() async {
    if (!mounted) return;
    setState(() => _submitting = true);
    final delivered = await widget.onCalibrate(0);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _stepDelivered = delivered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final availableHeight = MediaQuery.sizeOf(context).height - 48;
    // 稿子 216:5899 等四步：弹窗 406 高、步骤条 195 宽。
    final dialogHeight = math.min(406.0, availableHeight);

    return Dialog(
      key: const Key('water-level-calibration-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 327),
        child: SizedBox(
          height: dialogHeight,
          child: Column(
            children: <Widget>[
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => AppDialogScrollView(
                    child: SizedBox(
                      height: math.max(
                        constraints.maxHeight,
                        _minimumBodyHeight(context, constraints.maxWidth),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                        child: Column(
                          children: <Widget>[
                            Text(
                              WaterLevelCalibrationModel.title,
                              style: AppTypography.deviceTitle.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            SizedBox(
                              key: const Key('water-level-calibration-stepper'),
                              width: 195,
                              child: AppStepIndicator(
                                stepCount:
                                    WaterLevelCalibrationModel.steps.length,
                                currentStep: _currentStep,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxl),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: AppDurations.normal,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                child: _CalibrationStepContent(
                                  key: Key(
                                    'water-level-calibration-step-${_currentStep + 1}',
                                  ),
                                  step: _step,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              SizedBox(
                height: 56,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        key: const Key('calibration-secondary-button'),
                        style: _actionStyle(AppColors.textSecondary),
                        onPressed: _submitting ? null : _handleSecondaryAction,
                        child: Text(
                          _step.secondaryActionLabel,
                          style: AppTypography.status.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: AppColors.divider),
                    Expanded(
                      child: TextButton(
                        key: const Key('calibration-primary-button'),
                        style: _actionStyle(AppColors.brandPrimary),
                        onPressed: _submitting ? null : _handlePrimaryAction,
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.brandPrimary,
                                ),
                              )
                            : Text(
                                _step.primaryActionLabel,
                                style: AppTypography.status.copyWith(
                                  color: AppColors.brandPrimary,
                                  fontSize: 17,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Preserve the normal illustration layout, but keep text and a usable
  // illustration height scrollable when the viewport or text scale is tight.
  double _minimumBodyHeight(BuildContext context, double width) {
    final contentWidth = math.max(1.0, width - 32);
    double textHeight(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: contentWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final instructionSize = contentWidth < 280 ? 18.0 : 20.0;
    final instructionStyle = AppTypography.deviceTitle.copyWith(
      fontSize: instructionSize,
      fontWeight: FontWeight.w500,
      height: 1.47,
    );
    final instructionHeight = WaterLevelCalibrationModel.steps
        .map((step) => textHeight(step.instruction, instructionStyle))
        .reduce(math.max);
    return 24 +
        textHeight(
          WaterLevelCalibrationModel.title,
          AppTypography.deviceTitle.copyWith(fontWeight: FontWeight.w600),
        ) +
        AppSpacing.lg +
        24 +
        AppSpacing.xxl +
        math.max(instructionSize * 1.47 * 2, instructionHeight) +
        AppSpacing.xs +
        80;
  }

  ButtonStyle _actionStyle(Color foregroundColor) {
    return TextButton.styleFrom(
      foregroundColor: foregroundColor,
      disabledForegroundColor: foregroundColor.withValues(alpha: .5),
      minimumSize: const Size.fromHeight(56),
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
    );
  }

  Future<void> _handlePrimaryAction() async {
    // 「完成」不下发任何东西：step3 在这张卡片出现时就发过了，四步已经走完。
    if (_onSummaryStep) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _submitting = true);
    // 开场那次 step0 没成功就先补上，再发下一张卡片的 step。
    final entered = _stepDelivered || await widget.onCalibrate(_currentStep);
    final advanced = entered && await widget.onCalibrate(_currentStep + 1);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      // 补发成功但下一步失败时仍停在本卡，本卡的 step 已经在设备那边生效。
      _stepDelivered = entered;
      if (advanced) _currentStep += 1;
    });
  }

  Future<void> _handleSecondaryAction() async {
    // 半途退出才是「取消」，要用 step5 把设备从校准模式里放出来。
    // 最后那张卡上的「关闭」不是取消：step0–step3 已经全部发完，再补一条 step5
    // 等于让固件把刚校准好的结果作废。
    if (!_onSummaryStep) await widget.onCancel();
    if (!mounted) return;
    Navigator.pop(context, _onSummaryStep);
  }
}

class _CalibrationStepContent extends StatelessWidget {
  const _CalibrationStepContent({required this.step, super.key});

  final WaterLevelCalibrationStepModel step;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 280;
        return Column(
          children: <Widget>[
            // 说明区固定两行高、垂直居中（稿子 222:6239：第四步单行的「校准完成！」
            // 放在两行的中间）。原来顶对齐，进第四步时插图上跳约 29 并被拉大。
            ConstrainedBox(
              // 至少两行高；万一窄屏折成三行照常撑开，不截字。
              constraints: BoxConstraints(
                minHeight: (compact ? 18 : 20) * 1.47 * 2,
              ),
              child: Center(
                heightFactor: 1,
                child: Text(
                  step.instruction,
                  key: const Key('water-level-calibration-instruction'),
                  textAlign: TextAlign.center,
                  style: AppTypography.deviceTitle.copyWith(
                    fontSize: compact ? 18 : 20,
                    fontWeight: FontWeight.w500,
                    height: 1.47,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // 插图固定 230×164（稿子四步一致），空间不够时按比例缩。
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 230,
                    maxHeight: 164,
                  ),
                  child: Semantics(
                    label: step.semanticLabel,
                    image: true,
                    child: Image.asset(
                      _assetFor(step.visual),
                      key: const Key('water-level-calibration-illustration'),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const _CalibrationIllustrationFallback(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _assetFor(WaterLevelCalibrationVisual visual) => switch (visual) {
    WaterLevelCalibrationVisual.emptyReservoir =>
      AppAssets.waterCalibrationRemoveInnerPot,
    WaterLevelCalibrationVisual.firstPour => AppAssets.waterCalibrationAdd30ml,
    WaterLevelCalibrationVisual.secondPour =>
      AppAssets.waterCalibrationAddSecond30ml,
    WaterLevelCalibrationVisual.completed => AppAssets.waterCalibrationComplete,
  };
}

class _CalibrationIllustrationFallback extends StatelessWidget {
  const _CalibrationIllustrationFallback();

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: const Key('water-level-calibration-illustration-fallback'),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.brandSurface,
          borderRadius: AppRadius.card,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              '示意图暂不可用',
              textAlign: TextAlign.center,
              style: AppTypography.smallBody.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
