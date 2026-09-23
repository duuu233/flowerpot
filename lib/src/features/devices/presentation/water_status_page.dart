import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import '../models/history_period.dart';
import '../models/water_status_page_model.dart';
import 'widgets/metric_history_empty_card.dart';
import 'widgets/water_status_summary_card.dart';
import 'widgets/water_trend_chart_card.dart';

class WaterStatusPage extends StatefulWidget {
  const WaterStatusPage({
    required this.deviceId,
    super.key,
    this.initialMetric = WaterStatusMetric.waterLevel,
  });

  final String deviceId;
  final WaterStatusMetric initialMetric;

  @override
  State<WaterStatusPage> createState() => _WaterStatusPageState();
}

class _WaterStatusPageState extends State<WaterStatusPage> {
  ReportRange range = ReportRange.day;
  late WaterStatusMetric metric;
  int periodOffset = 0;
  bool initialized = false;

  @override
  void initState() {
    super.initState();
    metric = widget.initialMetric;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      // 「为什么没有历史记录」只能在真机上分辨：把这一页的历史 DP（131–136）到货
      // 情况打进页面底部的联调日志框，一眼看出是设备没报还是报了解不出来。
      // 光照、温度、湿度三个状态页照同一套写法，只是 DP 不同。
      final state = FlowerpotScope.of(context);
      unawaited(
        state.logStatusDps(
          widget.deviceId,
          '需水状态',
          WaterStatusPageModel.reportedDps,
        ),
      );
      unawaited(
        state.logHistoryDiagnostics(
          widget.deviceId,
          '需水状态',
          metrics: const <String>{'waterLevel', 'soilMoisture'},
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '需水状态', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final summaryModel = WaterStatusPageModel.fromDevice(
      device,
      language: FlowerpotScope.of(context).languageCode,
    );
    // 和上面的读数一样现读：涂鸦一推送，页面重建，曲线跟着往前走。
    final values = FlowerpotScope.of(context).chartSeries(
      widget.deviceId,
      metric.sensorMetric,
      range,
      // 曲线跟着日期条走：日视图翻到过去某天就画那天的日包（2026-09-17 起日包
      // 一次带 7 天）。周 / 月只有当期一包，传了也用不上。⚠️ 原来这里不传日期，
      // 标签翻了、曲线还是今天那条，看着像「翻了没反应」。
      date: HistoryPeriod.dayFor(periodOffset),
    );
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '需水状态', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                23,
                AppSpacing.pageMargin,
                32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  WaterStatusSummaryCard(model: summaryModel),
                  const SizedBox(height: AppSpacing.md),
                  TimeRangeSelector<ReportRange>(
                    values: ReportRange.values,
                    selected: range,
                    labelBuilder: _rangeLabel,
                    onChanged: _changeRange,
                  ),
                  const SizedBox(height: 12),
                  DateRangeNavigator(
                    label: _dateLabel(),
                    // 窗口按周期来：日 = 设备日包的 7 天（当天 + 往前 6 天）；
                    // 周 / 月设备只有当期那一包，往前没有第二份，所以一格都不给翻。
                    // ⚠️ 原来这里是裸的 `periodOffset--`，能一直往前翻到去年
                    // （2026-09-17 用户实测报的 BUG）。规则见 [HistoryPeriod]。
                    onPrevious: HistoryPeriod.canGoBack(range, periodOffset)
                        ? () => setState(() => periodOffset--)
                        : null,
                    onNext: HistoryPeriod.canGoForward(periodOffset)
                        ? () => setState(() => periodOffset++)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  if (values.isEmpty)
                    const MetricHistoryEmptyCard(title: '暂无历史数据')
                  else
                    WaterTrendChartCard(
                      metric: metric,
                      values: values,
                      labels: _chartLabels(),
                      onMetricChanged: _changeMetric,
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  CareAdviceCard(
                    message: summaryModel.advice,
                    emphasized: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _changeRange(ReportRange value) {
    if (value == range) return;
    setState(() {
      range = value;
      periodOffset = 0;
    });
  }

  void _changeMetric(WaterStatusMetric value) {
    if (value == metric) return;
    setState(() {
      metric = value;
    });
  }

  String _rangeLabel(ReportRange value) => switch (value) {
    ReportRange.day => '日',
    ReportRange.week => '周',
    ReportRange.month => '月',
  };

  String _dateLabel() {
    final now = DateTime.now();
    return switch (range) {
      ReportRange.day => _formatDay(HistoryPeriod.dayFor(periodOffset)),
      ReportRange.week => _formatWeek(
        now.add(Duration(days: periodOffset * 7)),
      ),
      ReportRange.month => _formatMonth(
        DateTime(now.year, now.month + periodOffset),
      ),
    };
  }

  String _formatDay(DateTime date) => '${date.month}月${date.day}日';

  String _formatWeek(DateTime anchor) {
    final start = anchor.subtract(Duration(days: anchor.weekday - 1));
    final end = start.add(const Duration(days: 6));
    return '${start.month}月${start.day}日 - ${end.month}月${end.day}日';
  }

  String _formatMonth(DateTime date) => '${date.year}年${date.month}月';

  List<String> _chartLabels() => switch (range) {
    ReportRange.day => const <String>[
      '00:00',
      '05:00',
      '10:00',
      '15:00',
      '20:00',
      '00:00',
    ],
    ReportRange.week => const <String>[
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ],
    ReportRange.month => const <String>['1日', '6日', '11日', '16日', '21日', '26日'],
  };
}
