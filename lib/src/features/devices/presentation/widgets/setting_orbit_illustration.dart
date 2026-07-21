import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

enum DeviceSettingSymbol { brightness, sound, vibration, touch }

class DeviceSettingOrbitIllustration extends StatelessWidget {
  const DeviceSettingOrbitIllustration({required this.symbol, super.key});

  final DeviceSettingSymbol symbol;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _DeviceSettingOrbitPainter(symbol)),
    );
  }
}

class _DeviceSettingOrbitPainter extends CustomPainter {
  const _DeviceSettingOrbitPainter(this.symbol);

  final DeviceSettingSymbol symbol;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 104);
    canvas.drawCircle(
      center,
      78,
      Paint()..color = AppColors.brandPrimary.withValues(alpha: .025),
    );
    canvas.drawCircle(
      center,
      58,
      Paint()..color = AppColors.brandPrimary.withValues(alpha: .032),
    );
    canvas.drawCircle(
      center,
      39,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            AppColors.brandPrimary.withValues(alpha: .09),
            AppColors.brandPrimary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 39)),
    );

    _dot(canvas, center + const Offset(-58, -54), 3, .18);
    _dot(canvas, center + const Offset(70, -39), 3, .17);
    _dot(canvas, center + const Offset(-47, 32), 5, .30);
    _dot(canvas, center + const Offset(62, 46), 3, .10);

    switch (symbol) {
      case DeviceSettingSymbol.brightness:
        _drawBrightness(canvas, center);
        break;
      case DeviceSettingSymbol.sound:
        _drawSound(canvas, center);
        break;
      case DeviceSettingSymbol.vibration:
        _drawVibration(canvas, center);
        break;
      case DeviceSettingSymbol.touch:
        _drawTouch(canvas, center);
        break;
    }
  }

  void _drawBrightness(Canvas canvas, Offset center) {
    final paint = Paint()
      ..color = AppColors.brandPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, 10.5, paint);
    for (var index = 0; index < 8; index++) {
      final angle = index * .7853981633974483;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(center + direction * 17, center + direction * 24, paint);
    }
  }

  void _drawSound(Canvas canvas, Offset center) {
    const heights = <double>[8, 17, 31, 54, 42, 29, 62, 30, 17, 8];
    const gap = 7.2;
    final paint = Paint()
      ..color = AppColors.brandPrimary
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final startX = center.dx - ((heights.length - 1) * gap / 2);
    for (var index = 0; index < heights.length; index++) {
      final x = startX + index * gap;
      final halfHeight = heights[index] / 2;
      canvas.drawLine(
        Offset(x, center.dy - halfHeight),
        Offset(x, center.dy + halfHeight),
        paint,
      );
    }
  }

  void _drawVibration(Canvas canvas, Offset center) {
    final paint = Paint()..color = AppColors.brandPrimary;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(.42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-10, -24, 20, 48),
        const Radius.circular(4),
      ),
      paint,
    );
    for (final bar in const <({double x, double height})>[
      (x: -30, height: 21),
      (x: -20, height: 35),
      (x: 20, height: 35),
      (x: 30, height: 21),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(bar.x, 0),
            width: 5.5,
            height: bar.height,
          ),
          const Radius.circular(3),
        ),
        paint,
      );
    }
    canvas.restore();
  }

  void _drawTouch(Canvas canvas, Offset center) {
    canvas.save();
    canvas.translate(center.dx - 3, center.dy + 5);
    canvas.rotate(-.58);
    _drawMaterialIcon(canvas, Icons.back_hand_rounded, Offset.zero, 47);
    canvas.restore();
    _drawMaterialIcon(
      canvas,
      Icons.favorite_rounded,
      center + const Offset(14, -15),
      25,
    );
  }

  void _drawMaterialIcon(
    Canvas canvas,
    IconData icon,
    Offset center,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: AppColors.brandPrimary,
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _dot(Canvas canvas, Offset center, double radius, double alpha) {
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = AppColors.brandPrimary.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_DeviceSettingOrbitPainter oldDelegate) =>
      oldDelegate.symbol != symbol;
}
