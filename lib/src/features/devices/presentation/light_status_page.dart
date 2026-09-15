import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import '../models/light_status_page_model.dart';
import 'widgets/light_dli_bar_chart.dart';
import 'widgets/light_status_summary_card.dart';
import 'widgets/metric_history_empty_card.dart';

class LightStatusPage extends StatefulWidget {
  const LightStatusPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<LightStatusPage> createState() => _LightStatusPageState();
}

class _LightStatusPageState extends State<LightStatusPage> {
  ReportRange range = ReportRange.week;
  int periodOffset = 0;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      // 同需水状态页：进页面把 108/109/110 的原始上报值和 137–139 的到货情况打进
      // 联调日志框。
      final state = FlowerpotScope.of(context);
      unawaited(
        state.logStatusDps(
          widget.deviceId,
          '光照状态',
          LightStatusPageModel.reportedDps,
        ),
      );
      unawaited(
        state.logHistoryDiagnostics(
          widget.deviceId,
          '光照状态',
          metrics: const <String>{'illuminance'},
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '光照状态', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final summaryModel = LightStatusPageModel.fromDevice(
      device,
      language: FlowerpotScope.of(context).languageCode,
    );
    // 光照历史读 137/138/139（`light_*_hist`，日 / 周 / 月），解出来是 lux；日视图再接上
    // 109 的实时推送。和上面的读数一样现读，涂鸦一推送曲线就跟着往前走。
    //
    // ⚠️ 2026-09-15 以前这里读的是 [SensorMetric.dli]，而仓库把 137–139 解出来存在
    // [SensorMetric.light] 名下——功能点表里压根没有 DLI 历史 DP，真机上永远空态。
    final values = FlowerpotScope.of(
      context,
    ).chartSeries(widget.deviceId, SensorMetric.light, range);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '光照状态', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
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
                  if (values.isEmpty)
                    const MetricHistoryEmptyCard(title: '暂无光照历史')
                  else
                    MetricChartCard(
                      leading: Image.asset(
                        AppAssets.infoIcon,
                        width: 16,
                        height: 16,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        excludeFromSemantics: true,
                      ),
                      // 137–139 报的是照度（lux，0–9000），不是 DLI：标题和单位跟着
                      // 功能点走，不拿 lux 冒充 mol/m²/天。
                      title: '光照强度',
                      unit: 'lux',
                      height: 188,
                      titleStyle: AppTypography.body,
                      unitStyle: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      chart: LightDliBarChart(
                        values: values,
                        labels: _chartLabels(values.length),
                        maxValue: _axisMax(values),
                        decimals: 0,
                      ),
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
    // 日包 96 个点、一刻钟一个（见 TuyaHistoryCodec），每 6 小时标一次。
    ReportRange.day => List<String>.generate(count, (index) {
      final perHour = count >= 24 ? count ~/ 24 : 1;
      return index % (perHour * 6) == 0 ? '${index ~/ perHour}时' : '';
    }),
    ReportRange.month => List<String>.generate(
      count,
      (index) => index % 5 == 0 ? '${index + 1}日' : '',
    ),
  };

  /// 纵轴上限：比峰值大的第一个「整」刻度（1/2/5×10ⁿ 一格，共五格）。
  ///
  /// 柱状图原来是给 DLI 画的，纵轴写死 0–1；lux 动辄几百上千，不按数据定上限整根
  /// 柱子都会顶出去。夜里全是 0 时按 5 lux 画，坐标轴不至于塌成一条线。
  static double _axisMax(List<double> values) {
    final peak = values.fold<double>(0, math.max);
    final step = math.max(peak, 5.0) / 5;
    var magnitude = 1.0;
    while (true) {
      for (final factor in const <double>[1, 2, 5]) {
        if (factor * magnitude >= step) return factor * magnitude * 5;
      }
      magnitude *= 10;
    }
  }
}
