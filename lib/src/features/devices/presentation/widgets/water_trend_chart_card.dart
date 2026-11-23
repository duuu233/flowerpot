import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/water_status_page_model.dart';
import 'water_trend_line_chart.dart';

class WaterTrendChartCard extends StatelessWidget {
  const WaterTrendChartCard({
    required this.metric,
    required this.values,
    required this.labels,
    super.key,
    this.gaps = const <bool>[],
    this.labelPositions,
  });

  final WaterStatusMetric metric;
  final List<double> values;
  final List<String> labels;

  /// 设备没采到的点，见 [WaterTrendLineChart.gaps]。
  final List<bool> gaps;

  /// 横轴标签落在第几个点上，见 [WaterTrendLineChart.labelPositions]。
  final List<double>? labelPositions;

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
              // 2026-11-23 起只有水仓水位一条曲线，土壤湿度不再有历史，切换菜单去掉。
              Text(metric.label, style: AppTypography.body),
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
              gaps: gaps,
              labels: labels,
              labelPositions: labelPositions,
              unit: metric.unit,
              maxValue: metric.chartMax,
            ),
          ),
        ],
      ),
    );
  }
}
