import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 状态页的折线图（需水、光照日视图、温度、湿度共用）。
///
/// - 纵轴 0 ~ [maxValue] 分 5 格；有负值（零下的温度）时按同样的格距往下延伸，
///   0 那条线画实，零下那段线和填充换成冷色，一眼分得出冰点上下。
/// - [gaps] 标出设备没采到、以 0 补齐的点：线在那里断开，底下铺灰并写「未采集」，
///   不把补齐的 0 画成一次真实的骤降。
/// - 横轴标签默认在图上等距铺开；给了 [labelPositions]（按点的下标，可带小数）就
///   画在对应的点上，日视图按点的真实时刻标整点用这个。
class WaterTrendLineChart extends StatefulWidget {
  const WaterTrendLineChart({
    required this.values,
    required this.labels,
    required this.unit,
    super.key,
    this.gaps = const <bool>[],
    this.labelPositions,
    this.maxValue = 100,
    this.fractionDigits = 0,
    this.semanticsName = '水分趋势图',
  });

  final List<double> values;
  final List<String> labels;
  final String unit;
  final List<bool> gaps;
  final List<double>? labelPositions;
  final double maxValue;
  final int fractionDigits;
  final String semanticsName;

  @override
  State<WaterTrendLineChart> createState() => _WaterTrendLineChartState();
}

class _WaterTrendLineChartState extends State<WaterTrendLineChart> {
  late int selectedIndex = _defaultIndex();

  @override
  void didUpdateWidget(WaterTrendLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.values != widget.values) {
      selectedIndex = _defaultIndex();
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
            gaps: widget.gaps,
            labels: widget.labels,
            labelPositions: widget.labelPositions,
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
    if (_isGap(widget.gaps, index)) return _WaterTrendPainter.gapText;
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

  /// 默认选中靠右一点的那个点；正好落在没采到的点上就挪到最近一个有数的点。
  int _defaultIndex() {
    final length = widget.values.length;
    if (length <= 1) return 0;
    final base = ((length - 1) * .57).round();
    for (var offset = 0; offset < length; offset++) {
      for (final index in <int>[base + offset, base - offset]) {
        if (index >= 0 && index < length && !_isGap(widget.gaps, index)) {
          return index;
        }
      }
    }
    return base;
  }
}

bool _isGap(List<bool> gaps, int index) => index < gaps.length && gaps[index];

class _WaterTrendPainter extends CustomPainter {
  const _WaterTrendPainter({
    required this.values,
    required this.gaps,
    required this.labels,
    required this.labelPositions,
    required this.unit,
    required this.maxValue,
    required this.fractionDigits,
    required this.selectedIndex,
  });

  static const double left = 34;
  static const double right = 4;
  static const double top = 42;
  static const double bottom = 28;

  /// 纵轴 0 以上固定 5 格。
  static const int _divisionsAboveZero = 5;

  /// 零下最多往下延伸几格（-50 °C 这一档），再往下的贴底画。
  static const int _maxDivisionsBelowZero = 5;

  static const gapText = '未采集';

  final List<double> values;
  final List<bool> gaps;
  final List<String> labels;
  final List<double>? labelPositions;
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
    final plotRight = size.width - right;

    // ── 纵轴：有零下的点才往下加格，格距不变，0 始终落在一条网格线上 ──
    final step = maxValue / _divisionsAboveZero;
    var lowest = 0.0;
    for (var index = 0; index < values.length; index++) {
      if (!_isGap(gaps, index)) lowest = math.min(lowest, values[index]);
    }
    final below = lowest < 0
        ? math.min((-lowest / step).ceil(), _maxDivisionsBelowZero)
        : 0;
    final divisions = _divisionsAboveZero + below;
    final axisMin = -below * step;
    double yOf(double value) =>
        top +
        plotHeight * (maxValue - value.clamp(axisMin, maxValue)) /
            (maxValue - axisMin);
    final zeroY = yOf(0);

    double xOf(double index) => values.length == 1
        ? left + plotWidth / 2
        : left + plotWidth * index / (values.length - 1);
    final points = List<Offset>.generate(
      values.length,
      (index) => Offset(xOf(index.toDouble()), yOf(values[index])),
    );

    // ── 没采到的那几段：先铺灰底（网格压在上面），线在这里断开 ──
    final halfStep = values.length == 1
        ? plotWidth / 2
        : plotWidth / (values.length - 1) / 2;
    final gapRects = <Rect>[
      for (final (start, end) in _runs(gap: true))
        Rect.fromLTRB(
          math.max(left, points[start].dx - halfStep),
          top,
          math.min(plotRight, points[end].dx + halfStep),
          baseline,
        ),
    ];
    final gapPaint = Paint()
      ..color = AppColors.divider.withValues(alpha: .6);
    for (final rect in gapRects) {
      canvas.drawRect(rect, gapPaint);
    }

    // 格子太密（零下延伸得多）时隔一条标一个数，从 0 那条往两边数。
    final labelEvery = plotHeight / divisions < 16 ? 2 : 1;
    final gridPaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;
    final zeroPaint = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 1;
    for (var index = 0; index <= divisions; index++) {
      final value = maxValue - step * index;
      final y = yOf(value);
      if (index == divisions) {
        canvas.drawLine(Offset(left, y), Offset(plotRight, y), gridPaint);
      } else if (below > 0 && index == _divisionsAboveZero) {
        canvas.drawLine(Offset(left, y), Offset(plotRight, y), zeroPaint);
      } else {
        _drawDashedLine(canvas, Offset(left, y), Offset(plotRight, y), gridPaint);
      }
      if ((index - _divisionsAboveZero) % labelEvery == 0) {
        _paintText(
          canvas,
          _axisText(value),
          Offset(0, y - 7),
          AppTypography.axis.copyWith(
            fontSize: 11,
            color: value < 0 ? AppColors.info : null,
          ),
        );
      }
    }

    final gapLabel = TextPainter(
      text: TextSpan(
        text: gapText,
        style: AppTypography.axis.copyWith(color: AppColors.textTertiary),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    for (final rect in gapRects) {
      // 窄到放不下字的（零星一两个点）只留灰底。
      if (gapLabel.width + 8 > rect.width) continue;
      gapLabel.paint(
        canvas,
        Offset(
          rect.center.dx - gapLabel.width / 2,
          rect.center.dy - gapLabel.height / 2,
        ),
      );
    }

    // ── 折线：每段有数的连成一条，填充到 0 线；0 线以下那半换冷色 ──
    // 没有零下时不裁：贴着 0 基线的线和点要画全。
    final above = below > 0
        ? Rect.fromLTRB(0, 0, size.width, zeroY)
        : Offset.zero & size;
    final belowZero = Rect.fromLTRB(0, zeroY, size.width, size.height);
    for (final (start, end) in _runs(gap: false)) {
      final run = points.sublist(start, end + 1);
      final line = Path()..moveTo(run.first.dx, run.first.dy);
      for (final point in run.skip(1)) {
        line.lineTo(point.dx, point.dy);
      }
      final fill = Path.from(line)
        ..lineTo(run.last.dx, zeroY)
        ..lineTo(run.first.dx, zeroY)
        ..close();
      _paintRun(
        canvas,
        clip: above,
        line: line,
        fill: fill,
        run: run,
        color: AppColors.brandPrimary,
        fillShader: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.brandPrimary.withValues(alpha: .30),
            AppColors.brandPrimary.withValues(alpha: .03),
          ],
        ).createShader(Rect.fromLTRB(left, top, plotRight, zeroY)),
      );
      if (below > 0) {
        _paintRun(
          canvas,
          clip: belowZero,
          line: line,
          fill: fill,
          run: run,
          color: AppColors.info,
          fillShader: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              AppColors.info.withValues(alpha: .03),
              AppColors.info.withValues(alpha: .22),
            ],
          ).createShader(Rect.fromLTRB(left, zeroY, plotRight, baseline)),
        );
      }
    }

    final positions = labelPositions;
    for (var index = 0; index < labels.length; index++) {
      final x = positions != null && index < positions.length
          ? xOf(positions[index])
          : labels.length == 1
          ? left + plotWidth / 2
          : left + plotWidth * index / (labels.length - 1);
      _paintCenteredText(canvas, labels[index], Offset(x, baseline + 9));
    }

    final safeIndex = selectedIndex.clamp(0, points.length - 1);
    if (_isGap(gaps, safeIndex)) {
      _paintSelection(
        canvas,
        size,
        Offset(points[safeIndex].dx, zeroY),
        gapText,
        AppColors.textSecondary,
      );
    } else {
      final value = values[safeIndex];
      _paintSelection(
        canvas,
        size,
        points[safeIndex],
        '${value.toStringAsFixed(fractionDigits)}$unit',
        value < 0 ? AppColors.info : AppColors.brandPrimary,
      );
    }
  }

  /// 连续一段「没采到」（[gap] 为 true）或「有数」的点，首尾下标都含。
  List<(int, int)> _runs({required bool gap}) {
    final runs = <(int, int)>[];
    int? start;
    for (var index = 0; index <= values.length; index++) {
      final matches = index < values.length && _isGap(gaps, index) == gap;
      if (matches) {
        start ??= index;
      } else if (start != null) {
        runs.add((start, index - 1));
        start = null;
      }
    }
    return runs;
  }

  void _paintRun(
    Canvas canvas, {
    required Rect clip,
    required Path line,
    required Path fill,
    required List<Offset> run,
    required Color color,
    required Shader fillShader,
  }) {
    canvas
      ..save()
      ..clipRect(clip);
    if (run.length == 1) {
      // 前后都没采到、孤零零的一个点：画个点，不然连不成线就看不见了。
      canvas.drawCircle(run.single, 2.2, Paint()..color = color);
    } else {
      canvas
        ..drawPath(fill, Paint()..shader = fillShader)
        ..drawPath(
          line,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
    }
    canvas.restore();
  }

  /// 纵轴刻度：取整，-0 写成 0。
  static String _axisText(double value) {
    final text = value.toStringAsFixed(0);
    return text == '-0' ? '0' : text;
  }

  void _paintSelection(
    Canvas canvas,
    Size size,
    Offset point,
    String text,
    Color color,
  ) {
    canvas.drawCircle(
      point,
      3.5,
      Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(point, 2.6, Paint()..color = color);

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
    canvas.drawRRect(bubbleRect, Paint()..color = color);
    final arrowCenter = point.dx.clamp(
      leftEdge + 8,
      leftEdge + bubbleWidth - 8,
    );
    final arrow = Path()
      ..moveTo(arrowCenter - 5, bubbleTop + bubbleHeight)
      ..lineTo(arrowCenter + 5, bubbleTop + bubbleHeight)
      ..lineTo(point.dx, bubbleTop + bubbleHeight + 7)
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);
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
      oldDelegate.gaps != gaps ||
      oldDelegate.labels != labels ||
      oldDelegate.labelPositions != labelPositions ||
      oldDelegate.unit != unit ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.fractionDigits != fractionDigits ||
      oldDelegate.selectedIndex != selectedIndex;
}
