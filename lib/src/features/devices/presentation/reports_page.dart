import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';
import '../models/history_period.dart';

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

  /// 日视图当前看的是哪一天，默认今天。
  ///
  /// 设备日包一次上报 **7 天**（当天 + 往前 6 天，2026-09-17 固件），左右切日期就
  /// 在这个窗口里走，窗口外设备根本没报，所以到边箭头点不动（[_DayPicker]）。
  late DateTime date;

  late Future<List<double>> history;
  bool historyInitialized = false;

  @override
  void initState() {
    super.initState();
    range = widget.arguments.metric == SensorMetric.dli
        ? ReportRange.week
        : ReportRange.day;
    date = _startOfToday();
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

  Future<List<double>> _load() => FlowerpotScope.of(context).historyFor(
    widget.arguments.deviceId,
    widget.arguments.metric,
    range,
    // 周 / 月包是「每天一个平均值」的一整段，没有按天取这回事。
    date: range == ReportRange.day ? date : null,
  );

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
              // 日视图才有日期可切；没有日历史 DP 的指标（PPFD）切了也没数据。
              if (_hasDayPicker)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _DayPicker(
                    date: date,
                    onChanged: (value) => setState(() {
                      date = value;
                      history = _load();
                    }),
                  ),
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
                  // 没有历史功能点的指标留空，不拿当前读数画一条假曲线。
                  if (values.isEmpty) {
                    return GlassCard(
                      child: SizedBox(
                        height: 270,
                        child: Center(
                          child: Text(
                            _emptyMessage(info),
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
                            // 翻到过去某一天时右端是那天的 23:45，不是「当前」。
                            Text(_endLabel(range)),
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

  /// 曲线空着时说哪一句。三种情况要分开说，混成一句用户就没法判断是等一等、
  /// 还是根本没有这个数据：
  ///
  /// 1. **这个指标没有历史 DP**（电池、PPFD、DLI）——再等也不会有
  ///    （2026-09-11 产品反馈「报表里电池数据为空」）。历史 DP 是 131–139 加
  ///    164/165：水位 / 土壤湿度 / 光照各三个周期，空气温度 / 空气湿度只有日。
  /// 2. **日包里没有这一天**——日包一次带 7 天，某一天空着说明设备那天没报
  ///    （断电、离线）。用户正对着日期在翻，说成「还没上报」会让人以为整个功能
  ///    没通。
  /// 3. 其余：这条 DP 设备还没报过。
  String _emptyMessage(_MetricInfo info) {
    if (!_MetricInfo.hasHistorySource(widget.arguments.metric, range)) {
      return '${info.title}没有历史曲线：设备当前的功能点里没有导出这一项的历史数据，'
          '只有实时值。';
    }
    if (_hasDayPicker) {
      // 日包整条都没到过 ≠ 到了但缺这一天。前者说「没有这一天」会让人以为只差
      // 这天，翻两下发现每天都没有。
      final reported = FlowerpotScope.of(
        context,
      ).reportedDays(widget.arguments.deviceId, widget.arguments.metric);
      if (reported.isNotEmpty) {
        return '设备上报的 7 天日数据里没有${_dayLabel(date)}这一天。';
      }
    }
    return '设备还没有上报${info.title}历史数据。';
  }

  /// 这一页有没有日期切换条：日视图 + 这个指标确实有日历史 DP。
  bool get _hasDayPicker =>
      range == ReportRange.day &&
      _MetricInfo.hasHistorySource(widget.arguments.metric, ReportRange.day);

  String _startLabel(ReportRange range) => switch (range) {
    ReportRange.day => '00:00',
    ReportRange.week => '7 天前',
    ReportRange.month => '30 天前',
  };

  String _endLabel(ReportRange range) {
    if (range != ReportRange.day) return '当前';
    return _daysAgo(date) == 0 ? '当前' : '23:45';
  }

  String _rangeLabel(ReportRange range) => switch (range) {
    ReportRange.day => '日',
    ReportRange.week => '周',
    ReportRange.month => '月',
  };
}

/// 今天，只到日（不带时分）。日期比较、差天数一律用这个口径，免得一会儿带时分
/// 一会儿不带，`difference().inDays` 差一天。
DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// [date] 距今几天：今天 0，昨天 1。
int _daysAgo(DateTime date) => _startOfToday()
    .difference(DateTime(date.year, date.month, date.day))
    .inDays;

/// 往前 / 往后挪 [delta] 天。用构造函数进位，跨月跨年都对；不用
/// `add(Duration(days:))`——夏令时那天加 24 小时会落到前一天的 23 点。
DateTime _shiftDay(DateTime date, int delta) =>
    DateTime(date.year, date.month, date.day + delta);

/// 日期标签：`9月17日（今天）`。
String _dayLabel(DateTime date) {
  final base = '${date.month}月${date.day}日';
  return switch (_daysAgo(date)) {
    0 => '$base（今天）',
    1 => '$base（昨天）',
    _ => base,
  };
}

/// 日视图的日期切换条。
///
/// **窗口固定 7 天：当天 + 往前 6 天**（规则在 [HistoryPeriod]，跟着设备日包一次带
/// 的天数走）。窗口外的日期设备根本没报，所以这里不是一个能一直往前翻的日历——
/// **到边箭头就点不动**，而不是翻过去看一页空的。
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.date, required this.onChanged});

  static const prevKey = Key('report-day-prev');
  static const nextKey = Key('report-day-next');
  static const labelKey = Key('report-day-label');

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    // 窗口规则和四个状态页共用一处（[HistoryPeriod]）：那边按 `periodOffset`
    // 记「往前第几期」，这边记的是日期本身，换算一下就是 `-daysAgo`。
    final offset = -_daysAgo(date);
    return Row(
      children: <Widget>[
        IconButton(
          key: prevKey,
          tooltip: '前一天',
          onPressed: HistoryPeriod.canGoBack(ReportRange.day, offset)
              ? () => onChanged(_shiftDay(date, -1))
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            _dayLabel(date),
            key: labelKey,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: nextKey,
          tooltip: '后一天',
          // 今天就是最右边，没有「明天」可看。
          onPressed: HistoryPeriod.canGoForward(offset)
              ? () => onChanged(_shiftDay(date, 1))
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
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

  /// 这个指标在这个周期上到底**有没有历史 DP**。
  ///
  /// 水位（131/132/133）、土壤湿度（134/135/136）、光照（137/138/139）各有日 / 周 / 月；
  /// 空气温度（164）和空气湿度（165）是 2026-09-16 补的，**只有日**。电池、PPFD、DLI
  /// 一个都没有。没有的那些**只有实时值、没有历史曲线**——这是产品功能点决定的，
  /// 不是"还没上报"，两种情况在空态里要分开说。
  static bool hasHistorySource(SensorMetric metric, ReportRange range) =>
      switch (metric) {
        SensorMetric.waterLevel ||
        SensorMetric.soilMoisture ||
        SensorMetric.light => true,
        SensorMetric.temperature ||
        SensorMetric.humidity => range == ReportRange.day,
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
