import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/water_status_page_model.dart';
import 'water_trend_line_chart.dart';

class WaterTrendChartCard extends StatelessWidget {
  const WaterTrendChartCard({
    required this.metric,
    required this.values,
    required this.labels,
    required this.onMetricChanged,
    super.key,
  });

  final WaterStatusMetric metric;
  final List<double> values;
  final List<String> labels;
  final ValueChanged<WaterStatusMetric> onMetricChanged;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: AppSpacing.cardPadding,
      borderRadius: AppRadius.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Image.asset(
                AppAssets.infoIcon,
                width: 16,
                height: 16,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
              const SizedBox(width: AppSpacing.sm),
              PopupMenuButton<WaterStatusMetric>(
                initialValue: metric,
                tooltip: '切换数据指标',
                onSelected: onMetricChanged,
                itemBuilder: (context) => WaterStatusMetric.values
                    .map(
                      (value) => PopupMenuItem<WaterStatusMetric>(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(growable: false),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(metric.label, style: AppTypography.body),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: AppColors.textPrimary,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                metric.unit,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 188,
            child: WaterTrendLineChart(
              values: values,
              labels: labels,
              unit: metric.unit,
              maxValue: metric.chartMax,
            ),
          ),
        ],
      ),
    );
  }
}
