import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import 'water_trend_line_chart.dart';

class TemperatureTrendChartCard extends StatelessWidget {
  const TemperatureTrendChartCard({
    required this.values,
    required this.labels,
    super.key,
  });

  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return MetricChartCard(
      leading: Image.asset(
        AppAssets.infoIcon,
        width: 16,
        height: 16,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
      title: '空气温度变化',
      unit: '°C',
      height: 188,
      titleStyle: AppTypography.body,
      unitStyle: AppTypography.body.copyWith(color: AppColors.textSecondary),
      chart: WaterTrendLineChart(
        values: values,
        labels: labels,
        unit: '°C',
        maxValue: 50,
        fractionDigits: 1,
        semanticsName: '空气温度趋势图',
      ),
    );
  }
}
