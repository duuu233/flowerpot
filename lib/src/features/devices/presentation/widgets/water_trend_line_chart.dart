import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class WaterTrendLineChart extends StatefulWidget {
  const WaterTrendLineChart({
    required this.values,
    required this.labels,
    required this.unit,
    super.key,
    this.maxValue = 100,
    this.fractionDigits = 0,
    this.semanticsName = '水分趋势图',
  });

  final List<double> values;
  final List<String> labels;
  final String unit;
  final double maxValue;
  final int fractionDigits;
  final String semanticsName;

  @override
  State<WaterTrendLineChart> createState() => _WaterTrendLineChartState();
}

class _WaterTrendLineChartState extends State<WaterTrendLineChart> {
  late int selectedIndex = _defaultIndex(widget.values.length);

  @override
  void didUpdateWidget(WaterTrendLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.values != widget.values) {
      selectedIndex = _defaultIndex(widget.values.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.semanticsName}，当前选中${_selectedLabel()}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _selectPoint,
        child: CustomPaint(
          painter: _WaterTrendPainter(
            values: widget.values,
            labels: widget.labels,
            unit: widget.unit,
            maxValue: widget.maxValue,
            fractionDigits: widget.fractionDigits,
            selectedIndex: selectedIndex,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  String _selectedLabel() {
    if (widget.values.isEmpty) return '暂无数据';
    final index = selectedIndex.clamp(0, widget.values.length - 1);
    return '${widget.values[index].toStringAsFixed(widget.fractionDigits)}${widget.unit}';
  }

  void _selectPoint(TapDownDetails details) {
    if (widget.values.isEmpty) return;
    const left = _WaterTrendPainter.left;
    const right = _WaterTrendPainter.right;
    final width = context.size?.width ?? 0;
    final plotWidth = math.max(1.0, width - left - right);
    final ratio = ((details.localPosition.dx - left) / plotWidth).clamp(
      0.0,
      1.0,
    );
    setState(() {
      selectedIndex = (ratio * (widget.values.length - 1)).round();
    });
  }

  static int _defaultIndex(int length) {
    if (length <= 1) return 0;
    return ((length - 1) * .57).round();
  }
}

class _WaterTrendPainter extends CustomPainter {
  const _WaterTrendPainter({
    required this.values,
    required this.labels,
    required this.unit,
    required this.maxValue,
    required this.fractionDigits,
    required this.selectedIndex,
  });

  static const double left = 34;
  static const double right = 4;
  static const double top = 42;
  static const double bottom = 28;

  final List<double> values;
  final List<String> labels;
  final String unit;
  final double maxValue;
  final int fractionDigits;
  final int selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final plotWidth = math.max(1.0, size.width - left - right);
    final plotHeight = math.max(1.0, size.height - top - bottom);
    final baseline = top + plotHeight;
    final gridPaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;

    for (var index = 0; index <= 5; index++) {
      final y = top + plotHeight * index / 5;
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
        (maxValue * (1 - index / 5)).toStringAsFixed(0),
        Offset(0, y - 7),
        AppTypography.axis.copyWith(fontSize: 11),
      );
    }

    final points = List<Offset>.generate(values.length, (index) {
      final x = values.length == 1
          ? left + plotWidth / 2
          : left + plotWidth * index / (values.length - 1);
      final normalized = values[index].clamp(0.0, maxValue) / maxValue;
      return Offset(x, top + plotHeight * (1 - normalized));
    });
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, baseline)
      ..lineTo(points.first.dx, baseline)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.brandPrimary.withValues(alpha: .30),
            AppColors.brandPrimary.withValues(alpha: .03),
          ],
        ).createShader(Rect.fromLTRB(left, top, size.width - right, baseline)),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppColors.brandPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var index = 0; index < labels.length; index++) {
      final x = labels.length == 1
          ? left + plotWidth / 2
          : left + plotWidth * index / (labels.length - 1);
      _paintCenteredText(canvas, labels[index], Offset(x, baseline + 9));
    }

    final safeIndex = selectedIndex.clamp(0, points.length - 1);
    _paintSelection(canvas, size, points[safeIndex], values[safeIndex]);
  }

  void _paintSelection(Canvas canvas, Size size, Offset point, double value) {
    canvas.drawCircle(
      point,
      3.5,
      Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(point, 2.6, Paint()..color = AppColors.brandPrimary);

    final text = '${value.toStringAsFixed(fractionDigits)}$unit';
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTypography.body.copyWith(
          color: AppColors.surface,
          fontSize: 14,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final bubbleWidth = math.max(54.0, textPainter.width + 18).toDouble();
    const bubbleHeight = 18.0;
    final leftEdge = (point.dx - bubbleWidth / 2)
        .clamp(left, math.max(left, size.width - right - bubbleWidth))
        .toDouble();
    final bubbleTop = math.max(1.0, point.dy - bubbleHeight - 10);
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(leftEdge, bubbleTop, bubbleWidth, bubbleHeight),
      const Radius.circular(5),
    );
    canvas.drawRRect(bubbleRect, Paint()..color = AppColors.brandPrimary);
    final arrowCenter = point.dx.clamp(
      leftEdge + 8,
      leftEdge + bubbleWidth - 8,
    );
    final arrow = Path()
      ..moveTo(arrowCenter - 5, bubbleTop + bubbleHeight)
      ..lineTo(arrowCenter + 5, bubbleTop + bubbleHeight)
      ..lineTo(point.dx, bubbleTop + bubbleHeight + 7)
      ..close();
    canvas.drawPath(arrow, Paint()..color = AppColors.brandPrimary);
    textPainter.paint(
      canvas,
      Offset(
        leftEdge + (bubbleWidth - textPainter.width) / 2,
        bubbleTop + (bubbleHeight - textPainter.height) / 2,
      ),
    );
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
      text: TextSpan(text: text, style: AppTypography.axis),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy));
  }

  void _paintText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_WaterTrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.labels != labels ||
      oldDelegate.unit != unit ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.fractionDigits != fractionDigits ||
      oldDelegate.selectedIndex != selectedIndex;
}
