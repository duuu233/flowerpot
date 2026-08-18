import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import '../models/light_status_page_model.dart';
import 'widgets/light_dli_bar_chart.dart';
import 'widgets/light_status_summary_card.dart';

class LightStatusPage extends StatefulWidget {
  const LightStatusPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<LightStatusPage> createState() => _LightStatusPageState();
}

class _LightStatusPageState extends State<LightStatusPage> {
  ReportRange range = ReportRange.week;
  int periodOffset = 0;
  late Future<List<double>> history;
  bool initialized = false;

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
  ).historyFor(widget.deviceId, SensorMetric.dli, range);

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '光照状态', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final summaryModel = LightStatusPageModel.fromDevice(device);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '光照状态', leading: AppBackButton()),
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
                  LightStatusSummaryCard(model: summaryModel),
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
                              title: '光照历史读取失败',
                              message: '请稍后重试。',
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const AppSurfaceCard(
                          child: SizedBox(
                            height: 236,
                            child: AppLoading(label: '正在读取光照历史'),
                          ),
                        );
                      }
                      final values = snapshot.data!;
                      return MetricChartCard(
                        leading: Image.asset(
                          AppAssets.infoIcon,
                          width: 16,
                          height: 16,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
                        ),
                        title: 'DLI（每日光量积分）',
                        unit: 'mol/m²/天',
                        height: 188,
                        titleStyle: AppTypography.body,
                        unitStyle: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        chart: LightDliBarChart(
                          values: values,
                          labels: _chartLabels(values.length),
                        ),
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

  void _changeRange(ReportRange value) {
    setState(() {
      range = value;
      periodOffset = 0;
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

  List<String> _chartLabels(int count) => switch (range) {
    ReportRange.week => const <String>[
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ],
    ReportRange.day => List<String>.generate(
      count,
      (index) => index % 6 == 0 ? '$index时' : '',
    ),
    ReportRange.month => List<String>.generate(
      count,
      (index) => index % 5 == 0 ? '${index + 1}日' : '',
    ),
  };
}
