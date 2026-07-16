import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class LightDliBarChart extends StatelessWidget {
  const LightDliBarChart({
    required this.values,
    required this.labels,
    super.key,
  });

  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DliBarChartPainter(values: values, labels: labels),
      child: const SizedBox.expand(),
    );
  }
}

class _DliBarChartPainter extends CustomPainter {
  const _DliBarChartPainter({required this.values, required this.labels});

  final List<double> values;
  final List<String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const left = 34.0;
    const right = 4.0;
    const top = 8.0;
    const bottom = 28.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final maxValue = math.max(1.0, values.reduce(math.max) * 1.12);
    final gridPaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;

    for (var index = 0; index <= 5; index++) {
      final ratio = index / 5;
      final y = top + chartHeight * ratio;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), gridPaint);
      _paintText(
        canvas,
        (maxValue * (1 - ratio)).toStringAsFixed(1),
        Offset(0, y - 7),
        AppColors.textSecondary,
        10,
      );
    }

    final slotWidth = chartWidth / values.length;
    final barWidth = math.min(20.0, slotWidth * .45);
    final barPaint = Paint()..color = AppColors.brandPrimary;
    for (var index = 0; index < values.length; index++) {
      final normalized = values[index] / maxValue;
      final x = left + slotWidth * index + (slotWidth - barWidth) / 2;
      final barHeight = chartHeight * normalized;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top + chartHeight - barHeight, barWidth, barHeight),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, barPaint);
      final label = index < labels.length ? labels[index] : '${index + 1}';
      _paintCenteredText(
        canvas,
        label,
        Offset(x + barWidth / 2, top + chartHeight + 8),
      );
    }
  }

  void _paintCenteredText(Canvas canvas, String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy));
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_DliBarChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.labels != labels;
}
