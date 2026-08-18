import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import '../models/water_status_page_model.dart';
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
  late Future<List<double>> history;
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
      history = _load();
      initialized = true;
    }
  }

  Future<List<double>> _load() => FlowerpotScope.of(
    context,
  ).historyFor(widget.deviceId, metric.sensorMetric, range);

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '需水状态', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final summaryModel = WaterStatusPageModel.fromDevice(device);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '需水状态', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
              maxWidth: 375,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.xxxl,
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
                  const SizedBox(height: AppSpacing.sm),
                  DateRangeNavigator(
                    label: _dateLabel(),
                    onPrevious: () => setState(() => periodOffset--),
                    onNext: periodOffset < 0
                        ? () => setState(() => periodOffset++)
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FutureBuilder<List<double>>(
                    future: history,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const AppSurfaceCard(
                          child: SizedBox(
                            height: 220,
                            child: AppErrorView(
                              title: '水分历史读取失败',
                              message: '请稍后重试。',
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const AppSurfaceCard(
                          child: SizedBox(
                            height: 236,
                            child: AppLoading(label: '正在读取水分历史'),
                          ),
                        );
                      }
                      final values = snapshot.data!.isEmpty
                          ? <double>[_currentValue(summaryModel)]
                          : snapshot.data!;
                      return WaterTrendChartCard(
                        metric: metric,
                        values: values,
                        labels: _chartLabels(),
                        onMetricChanged: _changeMetric,
                      );
                    },
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

  double _currentValue(WaterStatusPageModel model) => switch (metric) {
    WaterStatusMetric.waterLevel => model.waterLevel.toDouble(),
    WaterStatusMetric.soilMoisture => model.soilMoisture.toDouble(),
  };

  void _changeRange(ReportRange value) {
    if (value == range) return;
    setState(() {
      range = value;
      periodOffset = 0;
      history = _load();
    });
  }

  void _changeMetric(WaterStatusMetric value) {
    if (value == metric) return;
    setState(() {
      metric = value;
      history = _load();
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
      ReportRange.day => _formatDay(now.add(Duration(days: periodOffset))),
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
