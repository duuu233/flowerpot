import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

class AppLineChart extends StatelessWidget {
  const AppLineChart({
    required this.values,
    super.key,
    this.color = AppColors.leaf,
    this.height = 190,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _LineChartPainter(values, color)),
  );
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final grid = Paint()
      ..color = AppColors.ink.withValues(alpha: .07)
      ..strokeWidth = 1;
    for (var index = 0; index < 5; index++) {
      final y = 12 + (size.height - 28) * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(1.0, maxValue - minValue);
    final line = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final normalized = (values[index] - minValue) / range;
      final y = size.height - 16 - normalized * (size.height - 36);
      if (index == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height - 16)
      ..lineTo(0, size.height - 16)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: .28),
            color.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
