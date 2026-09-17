import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import '../models/history_period.dart';
import '../models/humidity_status_page_model.dart';
import 'widgets/humidity_status_summary_card.dart';
import 'widgets/humidity_trend_chart_card.dart';
import 'widgets/metric_history_empty_card.dart';

class HumidityStatusPage extends StatefulWidget {
  const HumidityStatusPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<HumidityStatusPage> createState() => _HumidityStatusPageState();
}

class _HumidityStatusPageState extends State<HumidityStatusPage> {
  int periodOffset = 0;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      // 同需水状态页：进页面把 114/115 的原始上报值，以及 165 日历史的到货情况
      // 打进联调日志框。
      final state = FlowerpotScope.of(context);
      unawaited(
        state.logStatusDps(
          widget.deviceId,
          '相对湿度',
          HumidityStatusPageModel.reportedDps,
        ),
      );
      unawaited(
        state.logHistoryDiagnostics(
          widget.deviceId,
          '相对湿度',
          metrics: const <String>{'humidity'},
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '相对湿度', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final summaryModel = HumidityStatusPageModel.fromDevice(
      device,
      language: FlowerpotScope.of(context).languageCode,
    );
    // 湿度日历史读 165（`humi_daily_hist`）：固件 1.0.12 起每点是 2 字节大端 ×10
    // （与 164 对称，此前是 1 字节整数 %），解出来的十分之一个百分点已经在仓库里
    // 还原过；后面再接上 114 的实时推送。和上面的读数一样现读，推送一到就往前走一格。
    final values = FlowerpotScope.of(context).chartSeries(
      widget.deviceId,
      SensorMetric.humidity,
      ReportRange.day,
      // 曲线要跟着上面那条日期条走：翻到过去某天就画那天的日包
      // （2026-09-17 起日包一次带 7 天）。⚠️ 原来这里不传日期，标签翻了、曲线
      // 还是今天那条，看着像「翻了没反应」。
      date: HistoryPeriod.dayFor(periodOffset),
    );
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '相对湿度', leading: AppBackButton()),
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
                  HumidityStatusSummaryCard(model: summaryModel),
                  const SizedBox(height: AppSpacing.sm),
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
                  const SizedBox(height: AppSpacing.sm),
                  if (values.isEmpty)
                    const MetricHistoryEmptyCard(title: '暂无湿度历史')
                  else
                    HumidityTrendChartCard(
                      values: values,
                      labels: const <String>[
                        '00:00',
                        '05:00',
                        '10:00',
                        '15:00',
                        '20:00',
                        '00:00',
                      ],
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
