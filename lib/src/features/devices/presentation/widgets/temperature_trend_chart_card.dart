import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import 'water_trend_line_chart.dart';

class TemperatureTrendChartCard extends StatelessWidget {
  const TemperatureTrendChartCard({
    required this.values,
    required this.labels,
    super.key,
    this.gaps = const <bool>[],
    this.labelPositions,
    this.unit = '°C',
    this.maxValue = 50,
  });

  final List<double> values;
  final List<String> labels;

  /// 设备没采到的点，见 [WaterTrendLineChart.gaps]。
  final List<bool> gaps;

  /// 横轴标签落在第几个点上，见 [WaterTrendLineChart.labelPositions]。
  final List<double>? labelPositions;

  /// Follows `temp_unit_convert`: the device reports in the unit it is set to,
  /// so the axis only changes its label and its ceiling.
  final String unit;
  final double maxValue;

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
      unit: unit,
      height: 188,
      titleStyle: AppTypography.body,
      unitStyle: AppTypography.body.copyWith(color: AppColors.textSecondary),
      chart: WaterTrendLineChart(
        values: values,
        gaps: gaps,
        labels: labels,
        labelPositions: labelPositions,
        unit: unit,
        maxValue: maxValue,
        fractionDigits: 1,
        semanticsName: '空气温度趋势图',
      ),
    );
  }
}
