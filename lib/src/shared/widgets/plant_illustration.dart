import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

class PlantIllustration extends StatelessWidget {
  const PlantIllustration({
    super.key,
    this.size = 180,
    this.leafColor = AppColors.leaf,
    this.potColor = const Color(0xFFD88C5A),
  });

  final double size;
  final Color leafColor;
  final Color potColor;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _PlantPainter(leafColor: leafColor, potColor: potColor),
  );
}

class _PlantPainter extends CustomPainter {
  const _PlantPainter({required this.leafColor, required this.potColor});

  final Color leafColor;
  final Color potColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 180;
    canvas.scale(scale, scale);
    final shadow = Paint()..color = const Color(0x1717332B);
    canvas.drawOval(const Rect.fromLTWH(42, 155, 96, 14), shadow);

    final stem = Paint()
      ..color = AppColors.leafDark
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(90, 127), const Offset(90, 55), stem);
    canvas.drawLine(const Offset(89, 86), const Offset(60, 67), stem);
    canvas.drawLine(const Offset(91, 77), const Offset(121, 55), stem);
    canvas.drawLine(const Offset(88, 105), const Offset(58, 100), stem);
    canvas.drawLine(const Offset(91, 101), const Offset(125, 91), stem);

    final leaf = Paint()..color = leafColor;
    final lightLeaf = Paint()
      ..color = Color.lerp(leafColor, AppColors.lime, .28)!;
    _drawLeaf(canvas, const Offset(57, 61), 34, -2.4, leaf);
    _drawLeaf(canvas, const Offset(126, 49), 36, -.62, lightLeaf);
    _drawLeaf(canvas, const Offset(52, 99), 32, 3.05, lightLeaf);
    _drawLeaf(canvas, const Offset(130, 89), 36, -.05, leaf);
    _drawLeaf(canvas, const Offset(89, 48), 39, -1.57, leaf);

    final pot = Path()
      ..moveTo(53, 121)
      ..lineTo(127, 121)
      ..lineTo(117, 158)
      ..quadraticBezierTo(90, 169, 63, 158)
      ..close();
    canvas.drawPath(pot, Paint()..color = potColor);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(48, 116, 84, 17),
        const Radius.circular(8),
      ),
      Paint()..color = Color.lerp(potColor, Colors.white, .12)!,
    );
    canvas.drawArc(
      const Rect.fromLTWH(61, 135, 58, 31),
      0,
      math.pi,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: .13)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawLeaf(
    Canvas canvas,
    Offset center,
    double length,
    double angle,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(
        length * .28,
        -length * .48,
        length * .82,
        -length * .35,
        length,
        0,
      )
      ..cubicTo(length * .8, length * .36, length * .3, length * .46, 0, 0)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      const Offset(3, 0),
      Offset(length * .8, 0),
      Paint()
        ..color = Colors.white.withValues(alpha: .28)
        ..strokeWidth = 1.2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlantPainter oldDelegate) =>
      oldDelegate.leafColor != leafColor || oldDelegate.potColor != potColor;
}
