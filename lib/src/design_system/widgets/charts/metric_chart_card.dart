import 'package:flutter/material.dart';

import '../../tokens/app_radius.dart';
import '../../tokens/app_spacing.dart';
import '../cards/app_surface_card.dart';

class MetricChartCard extends StatelessWidget {
  const MetricChartCard({
    required this.title,
    required this.chart,
    super.key,
    this.leading,
    this.unit,
    this.legend,
    this.height = 240,
    this.titleStyle,
    this.unitStyle,
    this.padding = AppSpacing.cardPadding,
    this.borderRadius = AppRadius.card,
  });

  final String title;
  final Widget? leading;
  final String? unit;
  final Widget chart;
  final Widget? legend;
  final double height;
  final TextStyle? titleStyle;
  final TextStyle? unitStyle;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: padding,
      borderRadius: borderRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  title,
                  style: titleStyle ?? Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (unit != null)
                Text(
                  unit!,
                  style: unitStyle ?? Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(height: height, child: chart),
          if (legend != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            legend!,
          ],
        ],
      ),
    );
  }
}
