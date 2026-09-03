import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_radius.dart';

/// Dashed rounded outline around [child].
///
/// Used by every "add something here" target in the app — the animation upload
/// zone, the memorial image slot, the 新增纪念日 button — which the Figma frames
/// all draw the same way. Flutter has no dashed [BoxBorder], so the outline is
/// painted.
class AppDashedBorder extends StatelessWidget {
  const AppDashedBorder({
    required this.child,
    super.key,
    this.color,
    this.radius = AppRadius.md,
    this.dash = 5,
    this.gap = 5,
  });

  final Widget child;

  /// Defaults to the brand colour at the opacity the frames use.
  final Color? color;
  final double radius;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRoundedRectPainter(
        color: color ?? AppColors.brandPrimary.withValues(alpha: .55),
        radius: radius,
        dash: dash,
        gap: gap,
      ),
      child: child,
    );
  }
}

class _DashedRoundedRectPainter extends CustomPainter {
  const _DashedRoundedRectPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + dash, metric.length)),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap;
}
