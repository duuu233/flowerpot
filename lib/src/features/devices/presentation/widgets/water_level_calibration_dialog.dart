import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/water_level_calibration_model.dart';

typedef WaterLevelCalibrationCallback = Future<bool> Function();

Future<bool> showWaterLevelCalibrationDialog(
  BuildContext context, {
  required WaterLevelCalibrationCallback onCalibrate,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .42),
        builder: (_) => WaterLevelCalibrationDialog(onCalibrate: onCalibrate),
      ) ??
      false;
}

class WaterLevelCalibrationDialog extends StatefulWidget {
  const WaterLevelCalibrationDialog({required this.onCalibrate, super.key});

  final WaterLevelCalibrationCallback onCalibrate;

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
                        onPressed: _submitting
                            ? null
                            : () => Navigator.pop(context, false),
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
    if (_currentStep == WaterLevelCalibrationModel.steps.length - 1) {
      Navigator.pop(context, true);
      return;
    }
    if (_currentStep < WaterLevelCalibrationModel.steps.length - 2) {
      setState(() => _currentStep += 1);
      return;
    }

    setState(() => _submitting = true);
    final succeeded = await widget.onCalibrate();
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (succeeded) _currentStep += 1;
    });
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
                child: CustomPaint(
                  key: const Key('water-level-calibration-illustration'),
                  size: Size.infinite,
                  painter: _WaterLevelCalibrationPainter(step.visual),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WaterLevelCalibrationPainter extends CustomPainter {
  const _WaterLevelCalibrationPainter(this.visual);

  final WaterLevelCalibrationVisual visual;

  static const Color _line = Color(0xFF8D9596);
  static const Color _water = Color(0xFF67C1CC);
  static const Color _waterDark = Color(0xFF2BAAB4);
  static const Color _leaf = Color(0xFFB7D7A6);
  static const Color _leafLine = Color(0xFF74936A);

  @override
  void paint(Canvas canvas, Size size) {
    const artSize = Size(280, 170);
    final scale = math.min(
      size.width / artSize.width,
      size.height / artSize.height,
    );
    final offset = Offset(
      (size.width - artSize.width * scale) / 2,
      (size.height - artSize.height * scale) / 2,
    );
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    switch (visual) {
      case WaterLevelCalibrationVisual.emptyReservoir:
        _paintEmptyReservoir(canvas);
        break;
      case WaterLevelCalibrationVisual.firstPour:
        _paintFirstPour(canvas);
        break;
      case WaterLevelCalibrationVisual.secondPour:
        _paintSecondPour(canvas);
        break;
      case WaterLevelCalibrationVisual.completed:
        _paintCompleted(canvas);
        break;
    }
    canvas.restore();
  }

  void _paintEmptyReservoir(Canvas canvas) {
    _paintGround(canvas);
    _paintInnerPot(canvas, const Offset(26, 72));
    _paintDevice(canvas, const Rect.fromLTWH(145, 72, 105, 78));
    _paintCurvedArrow(canvas, const Offset(116, 82), const Offset(170, 62));
    _paintDrop(canvas, const Offset(212, 58), 8);
    _paintDrop(canvas, const Offset(226, 45), 6);
    _paintUpArrow(canvas, const Offset(20, 138));
  }

  void _paintFirstPour(Canvas canvas) {
    _paintGround(canvas);
    _paintDevice(canvas, const Rect.fromLTWH(76, 70, 125, 82));
    _paintMeasuringCup(canvas, const Offset(188, 44));
    _paintDrop(canvas, const Offset(153, 63), 8);
    _paintDownArrow(canvas, const Offset(130, 44));
  }

  void _paintSecondPour(Canvas canvas) {
    _paintGround(canvas);
    _paintInnerPot(canvas, const Offset(26, 72));
    _paintDevice(canvas, const Rect.fromLTWH(145, 72, 105, 78));
    _paintCurvedArrow(canvas, const Offset(116, 82), const Offset(170, 62));
    _paintDrop(canvas, const Offset(211, 58), 7);
    _paintDrop(canvas, const Offset(225, 48), 6);
    _paintDrop(canvas, const Offset(232, 68), 7);
    canvas.drawCircle(
      const Offset(165, 33),
      16,
      Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      const Offset(165, 33),
      16,
      Paint()
        ..color = _waterDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    _paintText(canvas, '×2', const Offset(165, 33), 14, _waterDark);
  }

  void _paintCompleted(Canvas canvas) {
    final haloRect = Rect.fromCircle(center: const Offset(140, 88), radius: 58);
    canvas.drawCircle(
      const Offset(140, 88),
      58,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[
            Color(0x4470C9D0),
            Color(0x1170C9D0),
            Color(0x0070C9D0),
          ],
        ).createShader(haloRect),
    );
    canvas.drawCircle(
      const Offset(140, 88),
      39,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF67C8CE), Color(0xFF27AAB4)],
        ).createShader(const Rect.fromLTWH(101, 49, 78, 78)),
    );
    final check = Path()
      ..moveTo(121, 88)
      ..lineTo(134, 101)
      ..lineTo(160, 75);
    canvas.drawPath(
      check,
      Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    _paintSparkle(canvas, const Offset(82, 104), 7);
    _paintSparkle(canvas, const Offset(184, 131), 8);
    _paintSparkle(canvas, const Offset(180, 34), 7);
    canvas.drawCircle(
      const Offset(91, 55),
      3,
      Paint()
        ..color = _water
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      const Offset(214, 80),
      3,
      Paint()
        ..color = _water
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintGround(Canvas canvas) {
    canvas.drawOval(
      const Rect.fromLTWH(26, 141, 228, 20),
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[
            Color(0x1170AFB5),
            Color(0x5570AFB5),
            Color(0x1170AFB5),
          ],
        ).createShader(const Rect.fromLTWH(26, 141, 228, 20)),
    );
  }

  void _paintDevice(Canvas canvas, Rect rect) {
    final body = Path()
      ..moveTo(rect.left + 11, rect.top + 8)
      ..quadraticBezierTo(
        rect.center.dx,
        rect.top - 4,
        rect.right - 11,
        rect.top + 8,
      )
      ..quadraticBezierTo(
        rect.right,
        rect.top + 20,
        rect.right - 2,
        rect.bottom - 14,
      )
      ..quadraticBezierTo(
        rect.right - 4,
        rect.bottom,
        rect.center.dx,
        rect.bottom,
      )
      ..quadraticBezierTo(
        rect.left + 4,
        rect.bottom,
        rect.left + 2,
        rect.bottom - 14,
      )
      ..quadraticBezierTo(
        rect.left,
        rect.top + 20,
        rect.left + 11,
        rect.top + 8,
      )
      ..close();
    canvas.drawPath(body, Paint()..color = AppColors.surface);
    canvas.drawPath(
      body,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    canvas.drawOval(
      Rect.fromLTWH(rect.left + 22, rect.top + 5, rect.width - 44, 5),
      Paint()
        ..color = _line.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final screen = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        rect.left + 20,
        rect.top + 17,
        rect.width - 40,
        rect.height * .43,
      ),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF4C4C50), Color(0xFF202024)],
        ).createShader(screen.outerRect),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    canvas.drawCircle(
      Offset(rect.center.dx, screen.bottom - 3),
      1.2,
      Paint()..color = AppColors.surface,
    );
    canvas.drawLine(
      Offset(rect.left + 2, rect.bottom - 16),
      Offset(rect.right - 2, rect.bottom - 16),
      Paint()
        ..color = _line.withValues(alpha: .55)
        ..strokeWidth = .8,
    );
  }

  void _paintInnerPot(Canvas canvas, Offset origin) {
    final rect = Rect.fromLTWH(origin.dx, origin.dy, 70, 62);
    final pot = Path()
      ..moveTo(rect.left + 5, rect.top + 8)
      ..lineTo(rect.right - 5, rect.top + 8)
      ..lineTo(rect.right - 10, rect.bottom - 8)
      ..lineTo(rect.left + 10, rect.bottom - 8)
      ..close();
    canvas.drawPath(pot, Paint()..color = AppColors.surface);
    canvas.drawPath(
      pot,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(rect.left + 5, rect.top + 8),
      Offset(rect.left + 1, rect.top + 4),
      Paint()
        ..color = _line
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(rect.right - 5, rect.top + 8),
      Offset(rect.right - 1, rect.top + 4),
      Paint()
        ..color = _line
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
    for (final x in <double>[rect.left + 15, rect.center.dx, rect.right - 15]) {
      canvas.drawRect(
        Rect.fromLTWH(x - 3, rect.bottom - 8, 6, 10),
        Paint()..color = AppColors.surface,
      );
      canvas.drawRect(
        Rect.fromLTWH(x - 3, rect.bottom - 8, 6, 10),
        Paint()
          ..color = _line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    _paintPlant(canvas, Offset(rect.center.dx, rect.top + 6));
  }

  void _paintPlant(Canvas canvas, Offset base) {
    final stem = Paint()
      ..color = _leafLine
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final endpoints = <Offset>[
      Offset(base.dx - 26, base.dy - 26),
      Offset(base.dx - 15, base.dy - 43),
      Offset(base.dx, base.dy - 56),
      Offset(base.dx + 17, base.dy - 39),
      Offset(base.dx + 29, base.dy - 24),
      Offset(base.dx - 20, base.dy - 14),
      Offset(base.dx + 22, base.dy - 10),
    ];
    for (final end in endpoints) {
      canvas.drawLine(base, end, stem);
      _paintLeaf(canvas, end, math.atan2(end.dy - base.dy, end.dx - base.dx));
    }
    canvas.drawLine(base, Offset(base.dx, base.dy - 60), stem);
  }

  void _paintLeaf(Canvas canvas, Offset center, double angle) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final leaf = Path()
      ..moveTo(-11, 0)
      ..quadraticBezierTo(0, -6, 11, 0)
      ..quadraticBezierTo(0, 6, -11, 0)
      ..close();
    canvas.drawPath(leaf, Paint()..color = _leaf);
    canvas.drawPath(
      leaf,
      Paint()
        ..color = _leafLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
    canvas.drawLine(
      const Offset(-8, 0),
      const Offset(8, 0),
      Paint()
        ..color = _leafLine
        ..strokeWidth = .6,
    );
    canvas.restore();
  }

  void _paintMeasuringCup(Canvas canvas, Offset center) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.58);
    final cup = Path()
      ..moveTo(-20, -19)
      ..lineTo(20, -19)
      ..lineTo(16, 21)
      ..quadraticBezierTo(0, 28, -16, 21)
      ..close();
    canvas.drawPath(cup, Paint()..color = AppColors.surface);
    canvas.drawPath(
      cup,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final water = Path()
      ..moveTo(-14, 7)
      ..quadraticBezierTo(0, 12, 14, 7)
      ..lineTo(12, 20)
      ..quadraticBezierTo(0, 24, -12, 20)
      ..close();
    canvas.drawPath(water, Paint()..color = const Color(0x9967C1CC));
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(10, -12 + i * 7),
        Offset(16, -12 + i * 7),
        Paint()
          ..color = _line
          ..strokeWidth = .8,
      );
    }
    canvas.restore();
    _paintText(canvas, '30mL', center + const Offset(38, 0), 13, _waterDark);
  }

  void _paintCurvedArrow(Canvas canvas, Offset start, Offset end) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx + 12,
        start.dy - 28,
        end.dx - 10,
        end.dy - 26,
        end.dx,
        end.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = _waterDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    _paintArrowHead(canvas, end, math.pi / 2.4);
  }

  void _paintUpArrow(Canvas canvas, Offset start) {
    final paint = Paint()
      ..color = _waterDark
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, start - const Offset(0, 24), paint);
    _paintArrowHead(canvas, start - const Offset(0, 24), -math.pi / 2);
  }

  void _paintDownArrow(Canvas canvas, Offset start) {
    final end = start + const Offset(0, 25);
    final paint = Paint()
      ..color = _waterDark
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, paint);
    _paintArrowHead(canvas, end, math.pi / 2);
  }

  void _paintArrowHead(Canvas canvas, Offset tip, double angle) {
    const length = 8.0;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - length * math.cos(angle - .55),
        tip.dy - length * math.sin(angle - .55),
      )
      ..lineTo(
        tip.dx - length * math.cos(angle + .55),
        tip.dy - length * math.sin(angle + .55),
      )
      ..close();
    canvas.drawPath(path, Paint()..color = _waterDark);
  }

  void _paintDrop(Canvas canvas, Offset center, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..cubicTo(
        center.dx - radius * .7,
        center.dy,
        center.dx - radius,
        center.dy + radius * .45,
        center.dx,
        center.dy + radius,
      )
      ..cubicTo(
        center.dx + radius,
        center.dy + radius * .45,
        center.dx + radius * .7,
        center.dy,
        center.dx,
        center.dy - radius,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xAA9ADCE3));
    canvas.drawPath(
      path,
      Paint()
        ..color = _waterDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9,
    );
  }

  void _paintSparkle(Canvas canvas, Offset center, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(center.dx, center.dy, center.dx + radius, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + radius)
      ..quadraticBezierTo(center.dx, center.dy, center.dx - radius, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - radius)
      ..close();
    canvas.drawPath(path, Paint()..color = _water);
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_WaterLevelCalibrationPainter oldDelegate) =>
      oldDelegate.visual != visual;
}
