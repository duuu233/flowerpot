import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/water_level_calibration_model.dart';

/// Reports the step the user just confirmed, and returns whether the device
/// accepted it. `water_level_calib` is an enum of stages, not a single command,
/// so the device has to be told about each one as it happens.
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

  WaterLevelCalibrationStepModel get _step =>
      WaterLevelCalibrationModel.steps[_currentStep];

  /// The closing "校准完成" card, which reports nothing to the device.
  bool get _onSummaryStep =>
      _currentStep == WaterLevelCalibrationModel.steps.length - 1;

  @override
  Widget build(BuildContext context) {
    final availableHeight = MediaQuery.sizeOf(context).height - 48;
    final dialogHeight = math.min(420.0, availableHeight);

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
                        width: 208,
                        child: AppStepIndicator(
                          stepCount: WaterLevelCalibrationModel.steps.length,
                          currentStep: _currentStep,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: AppDurations.normal,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
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
    if (_onSummaryStep) {
      Navigator.pop(context, true);
      return;
    }

    setState(() => _submitting = true);
    final succeeded = await widget.onCalibrate(_currentStep);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (succeeded) _currentStep += 1;
    });
  }

  Future<void> _handleSecondaryAction() async {
    // On the summary card the sequence is already finished and the button
    // reads 关闭, so there is nothing to cancel.
    if (!_onSummaryStep) await widget.onCancel();
    if (!mounted) return;
    Navigator.pop(context, false);
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
            Text(
              step.instruction,
              key: const Key('water-level-calibration-instruction'),
              textAlign: TextAlign.center,
              style: AppTypography.deviceTitle.copyWith(
                fontSize: compact ? 18 : 20,
                fontWeight: FontWeight.w500,
                height: 1.47,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
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
