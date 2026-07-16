import 'package:flutter/material.dart';

import '../../tokens/app_spacing.dart';
import '../cards/app_surface_card.dart';

class MetricChartCard extends StatelessWidget {
  const MetricChartCard({
    required this.title,
    required this.chart,
    super.key,
    this.unit,
    this.legend,
    this.height = 240,
  });

  final String title;
  final String? unit;
  final Widget chart;
  final Widget? legend;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (unit != null)
                Text(unit!, style: Theme.of(context).textTheme.bodySmall),
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
