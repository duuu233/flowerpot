import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import '../models/history_period.dart';
import '../models/temperature_status_page_model.dart';
import 'widgets/metric_history_empty_card.dart';
import 'widgets/temperature_status_summary_card.dart';
import 'widgets/temperature_trend_chart_card.dart';

class TemperatureStatusPage extends StatefulWidget {
  const TemperatureStatusPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<TemperatureStatusPage> createState() => _TemperatureStatusPageState();
}

class _TemperatureStatusPageState extends State<TemperatureStatusPage> {
  int periodOffset = 0;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      // 同需水状态页：进页面把 112/113/146 的原始上报值，以及 164 日历史的到货
      // 情况打进联调日志框。
      final state = FlowerpotScope.of(context);
      unawaited(
        state.logStatusDps(
          widget.deviceId,
          '空气温度',
          TemperatureStatusPageModel.reportedDps,
        ),
      );
      unawaited(
        state.logHistoryDiagnostics(
          widget.deviceId,
          '空气温度',
          metrics: const <String>{'temperature'},
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '空气温度', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final summaryModel = TemperatureStatusPageModel.fromDevice(
      device,
      language: FlowerpotScope.of(context).languageCode,
    );
    // 温度日历史读 164（`temp_daily_hist`），解出来是十分之一度、已经在仓库里还原过；
    // 后面再接上 112 的实时推送。和上面的读数一样现读，涂鸦一推送曲线就往前走一格。
    final chart = FlowerpotScope.of(context).chartData(
      widget.deviceId,
      SensorMetric.temperature,
      ReportRange.day,
      // 曲线要跟着上面那条日期条走：翻到过去某天就画那天的日包
      // （2026-09-17 起日包一次带 7 天）。⚠️ 原来这里不传日期，标签翻了、曲线
      // 还是今天那条，看着像「翻了没反应」。
      date: HistoryPeriod.dayFor(periodOffset),
    );
    final values = chart.values;
    // 横轴按点的真实时刻标：今天那条只到现在，不能拉满 00:00–24:00。
    final ticks = HistoryPeriod.timeTicks(chart.minutes);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '空气温度', leading: AppBackButton()),
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
                  TemperatureStatusSummaryCard(model: summaryModel),
                  const SizedBox(height: 10),
                  DateRangeNavigator(
                    label: _dateLabel(),
                    // 窗口就是设备日包的 7 天（当天 + 往前 6 天），到边点不动。
                    // ⚠️ 原来这里是裸的 `periodOffset--`，能一直往前翻到去年，
                    // 而设备没有那些天的数据（2026-09-17 用户实测报的 BUG）。
                    onPrevious:
                        HistoryPeriod.canGoBack(ReportRange.day, periodOffset)
                        ? () => setState(() => periodOffset--)
                        : null,
                    onNext: HistoryPeriod.canGoForward(periodOffset)
                        ? () => setState(() => periodOffset++)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  if (values.isEmpty)
                    const MetricHistoryEmptyCard(title: '暂无温度历史')
                  else
                    TemperatureTrendChartCard(
                      unit: summaryModel.temperatureSymbol,
                      // The axis follows the unit the device reports in.
                      maxValue: device.settings.temperatureFromCelsius(50),
                      values: values,
                      gaps: chart.gaps,
                      labels: ticks.labels,
                      labelPositions: ticks.positions,
                    ),
                  const SizedBox(height: AppSpacing.xl),
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

  String _dateLabel() {
    final date = HistoryPeriod.dayFor(periodOffset);
    return '${date.month}月${date.day}日';
  }
}
