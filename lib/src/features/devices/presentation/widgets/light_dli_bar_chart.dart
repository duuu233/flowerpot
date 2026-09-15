import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class LightDliBarChart extends StatelessWidget {
  const LightDliBarChart({
    required this.values,
    required this.labels,
    super.key,
    this.maxValue = 1.0,
    this.decimals = 1,
  });

  final List<double> values;
  final List<String> labels;

  /// 纵轴上限。默认 1.0 是设计稿给 DLI 的刻度；光照状态页画 137–139 的 lux 时按
  /// 数据传一个整刻度进来。
  final double maxValue;

  /// 纵轴刻度的小数位。
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DliBarChartPainter(
        values: values,
        labels: labels,
        maxValue: maxValue,
        decimals: decimals,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _DliBarChartPainter extends CustomPainter {
  const _DliBarChartPainter({
    required this.values,
    required this.labels,
    required this.maxValue,
    required this.decimals,
  });

  final List<double> values;
  final List<String> labels;
  final double maxValue;
  final int decimals;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const left = 34.0;
    const right = 4.0;
    const top = 8.0;
    const bottom = 28.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    // Axis tops out at [maxValue]; taller bars clip.
    final gridPaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;

    for (var index = 0; index <= 5; index++) {
      final ratio = index / 5;
      final y = top + chartHeight * ratio;
      if (index == 5) {
        canvas.drawLine(
          Offset(left, y),
          Offset(size.width - right, y),
          gridPaint,
        );
      } else {
        _drawDashedLine(
          canvas,
          Offset(left, y),
          Offset(size.width - right, y),
          gridPaint,
        );
      }
      _paintText(
        canvas,
        (maxValue * (1 - ratio)).toStringAsFixed(decimals),
        Offset(0, y - 7),
        AppColors.textSecondary,
        10,
      );
    }

    final slotWidth = chartWidth / values.length;
    final barWidth = math.min(11.0, slotWidth * .45);
    final barPaint = Paint()..color = AppColors.brandPrimary;
    for (var index = 0; index < values.length; index++) {
      final normalized = (values[index] / maxValue).clamp(0.0, 1.0);
      final x = left + slotWidth * index + (slotWidth - barWidth) / 2;
      final barHeight = chartHeight * normalized;
      canvas.drawRect(
        Rect.fromLTWH(x, top + chartHeight - barHeight, barWidth, barHeight),
        barPaint,
      );
      final label = index < labels.length ? labels[index] : '${index + 1}';
      _paintCenteredText(
        canvas,
        label,
        Offset(x + barWidth / 2, top + chartHeight + 8),
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 3.0;
    const dashGap = 3.0;
    var x = start.dx;
    while (x < end.dx) {
      canvas.drawLine(
        Offset(x, start.dy),
        Offset(math.min(x + dashWidth, end.dx), end.dy),
        paint,
      );
      x += dashWidth + dashGap;
    }
  }

  void _paintCenteredText(Canvas canvas, String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTypography.axis.copyWith(fontSize: 11),
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
        style: AppTypography.axis.copyWith(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_DliBarChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.labels != labels ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.decimals != decimals;
}
