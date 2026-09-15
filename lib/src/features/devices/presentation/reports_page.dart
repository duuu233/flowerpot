import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
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

class _ReportsPageState extends State<ReportsPage>
    with NetworkRetryAware<ReportsPage> {
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
      // 同需水状态页：把九条历史 DP 的到货情况打进联调日志框。
      unawaited(
        FlowerpotScope.of(
          context,
        ).logHistoryDiagnostics(widget.arguments.deviceId, '报表'),
      );
    }
  }

  /// 「网络异常」弹窗点「重试」：重读设备（历史 DP 在设备快照里），再重画曲线。
  @override
  Future<void> reloadForNetworkRetry() async {
    await FlowerpotScope.of(context).reloadDevices();
    if (!mounted) return;
    setState(() {
      history = _load();
    });
  }

  Future<List<double>> _load() => FlowerpotScope.of(
    context,
  ).historyFor(widget.arguments.deviceId, widget.arguments.metric, range);

  @override
  Widget build(BuildContext context) {
    // `temp_unit_convert` (DP 146) decides the unit the device reports in, so
    // the temperature report is labelled from the device rather than fixed to
    // Celsius. Readings are never converted here — only the app's own advice
    // range is.
    final settings =
        FlowerpotScope.of(
          context,
        ).deviceById(widget.arguments.deviceId)?.settings ??
        const DeviceControlSettings();
    final info = _MetricInfo.of(
      widget.arguments.metric,
    ).withTemperatureUnit(settings);
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
                  // Only water level, soil moisture and light have history
                  // function points; the rest have no data source yet and are
                  // left empty rather than drawn from the current reading.
                  if (values.isEmpty) {
                    return GlassCard(
                      child: SizedBox(
                        height: 270,
                        child: Center(
                          child: Text(
                            // ⚠️ **「还没上报」和「根本没有这个数据源」要分开说**
                            // （2026-09-11 产品反馈「报表里电池数据为空」）。
                            //
                            // 设备只导出 9 个历史 DP（131–139）：水位 / 土壤湿度 / 光照
                            // 各三个周期。**电池、温度、湿度、PPFD、DLI 没有历史 DP**，
                            // 再等也不会有。说成「还没有上报」会让人一直等一个不存在的东西。
                            _MetricInfo.hasHistorySource(widget.arguments.metric)
                                ? '设备还没有上报${info.title}历史数据。'
                                : '${info.title}没有历史曲线：设备当前的功能点里没有导出'
                                      '这一项的历史数据，只有实时值。',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    );
                  }
                  final average =
                      values.reduce((a, b) => a + b) / values.length;
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

  /// The temperature report in the device's own unit. Every other metric is
  /// returned unchanged.
  _MetricInfo withTemperatureUnit(DeviceControlSettings settings) {
    if (unit != '°C') return this;
    return _MetricInfo(
      title,
      settings.temperatureSymbol,
      icon,
      color,
      '多数室内植物在 ${settings.formatCelsiusRange(18, 28)} 生长较舒适，避免温度骤变。',
      decimals,
    );
  }

  /// 这个指标有没有**历史数据源**。
  ///
  /// 设备导出的历史 DP 只有 131–139 九个：水位（131/132/133）、土壤湿度（134/135/136）、
  /// 光照（137/138/139），各对应日 / 周 / 月。其余指标（电池、温度、湿度、PPFD、DLI）
  /// **只有实时值、没有历史曲线**——这是产品功能点决定的，不是"还没上报"。
  static bool hasHistorySource(SensorMetric metric) => switch (metric) {
    SensorMetric.waterLevel ||
    SensorMetric.soilMoisture ||
    SensorMetric.light => true,
    _ => false,
  };

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
