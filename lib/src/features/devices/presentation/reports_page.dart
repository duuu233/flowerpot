import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';

class ReportArguments {
  const ReportArguments({required this.deviceId, required this.metric});

  final String deviceId;
  final SensorMetric metric;
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({required this.arguments, super.key});

  final ReportArguments arguments;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late ReportRange range;
  late Future<List<double>> history;
  bool historyInitialized = false;

  @override
  void initState() {
    super.initState();
    range = widget.arguments.metric == SensorMetric.dli
        ? ReportRange.week
        : ReportRange.day;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!historyInitialized) {
      history = _load();
      historyInitialized = true;
    }
  }

  Future<List<double>> _load() => FlowerpotScope.of(
    context,
  ).historyFor(widget.arguments.deviceId, widget.arguments.metric, range);

  @override
  Widget build(BuildContext context) {
    final info = _MetricInfo.of(widget.arguments.metric);
    final ranges = switch (widget.arguments.metric) {
      SensorMetric.dli => const <ReportRange>[
        ReportRange.week,
        ReportRange.month,
      ],
      SensorMetric.ppfd => const <ReportRange>[ReportRange.day],
      _ => ReportRange.values,
    };
    return Scaffold(
      appBar: AppBar(title: Text('${info.title}报表')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: <Widget>[
              if (ranges.length == 1)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    label: '今日数据',
                    icon: Icons.today_outlined,
                    color: AppColors.leaf,
                  ),
                )
              else
                SegmentedButton<ReportRange>(
                  segments: <ButtonSegment<ReportRange>>[
                    for (final item in ranges)
                      ButtonSegment(
                        value: item,
                        label: Text(_rangeLabel(item)),
                      ),
                  ],
                  selected: <ReportRange>{range},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => setState(() {
                    range = value.first;
                    history = _load();
                  }),
                ),
              const SizedBox(height: 20),
              FutureBuilder<List<double>>(
                future: history,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const GlassCard(
                      child: SizedBox(
                        height: 270,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }
                  final values = snapshot.data!;
                  final average = values.isEmpty
                      ? 0
                      : values.reduce((a, b) => a + b) / values.length;
                  return GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: info.color.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(info.icon, color: info.color),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  info.title,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                Text(
                                  '${average.toStringAsFixed(info.decimals)} ${info.unit}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        AppLineChart(
                          values: values,
                          color: info.color,
                          height: 210,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(_startLabel(range)),
                            const Text('当前'),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              GlassCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.auto_awesome_outlined, color: info.color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '养护建议',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(info.tip),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _startLabel(ReportRange range) => switch (range) {
    ReportRange.day => '00:00',
    ReportRange.week => '7 天前',
    ReportRange.month => '30 天前',
  };

  String _rangeLabel(ReportRange range) => switch (range) {
    ReportRange.day => '日',
    ReportRange.week => '周',
    ReportRange.month => '月',
  };
}

class _MetricInfo {
  const _MetricInfo(
    this.title,
    this.unit,
    this.icon,
    this.color,
    this.tip,
    this.decimals,
  );

  final String title;
  final String unit;
  final IconData icon;
  final Color color;
  final String tip;
  final int decimals;

  static _MetricInfo of(SensorMetric metric) => switch (metric) {
    SensorMetric.waterLevel => const _MetricInfo(
      '水仓水位',
      '%',
      Icons.water_outlined,
      AppColors.water,
      '水位低于 25% 时及时补水，避免水泵空转。',
      0,
    ),
    SensorMetric.soilMoisture => const _MetricInfo(
      '土壤湿度',
      '%',
      Icons.water_drop_outlined,
      Color(0xFF4B9AB0),
      '观察趋势比单次读数更重要，避免短时间内反复浇水。',
      0,
    ),
    SensorMetric.light => const _MetricInfo(
      '环境光照',
      'lx',
      Icons.wb_sunny_outlined,
      AppColors.sun,
      '尽量提供稳定的明亮散射光，避免正午强光灼伤。',
      0,
    ),
    SensorMetric.ppfd => const _MetricInfo(
      'PPFD',
      'μmol/m²/s',
      Icons.wb_sunny_outlined,
      AppColors.sun,
      'PPFD 反映瞬时有效光强，可结合 DLI 判断全天光照总量。',
      0,
    ),
    SensorMetric.dli => const _MetricInfo(
      'DLI',
      'mol/m²/d',
      Icons.bar_chart_rounded,
      AppColors.sun,
      'DLI 需要按周或月观察，以评估植物累计获得的有效光照。',
      1,
    ),
    SensorMetric.temperature => const _MetricInfo(
      '空气温度',
      '°C',
      Icons.thermostat_rounded,
      AppColors.danger,
      '多数室内植物在 18–28°C 生长较舒适，避免温度骤变。',
      1,
    ),
    SensorMetric.humidity => const _MetricInfo(
      '相对湿度',
      '%',
      Icons.air_rounded,
      Color(0xFF7F8BC4),
      '适度通风有助于稳定湿度，也能降低叶片病害风险。',
      0,
    ),
    SensorMetric.battery => const _MetricInfo(
      '电池电量',
      '%',
      Icons.battery_5_bar_rounded,
      AppColors.leaf,
      '低于 20% 时及时充电，保持设备在线以免中断数据记录。',
      0,
    ),
  };
}
