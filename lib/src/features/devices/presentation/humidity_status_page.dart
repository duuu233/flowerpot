import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
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
  late Future<List<double>> history;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      history = FlowerpotScope.of(
        context,
      ).historyFor(widget.deviceId, SensorMetric.humidity, ReportRange.day);
      initialized = true;
      // 同需水状态页：进页面把 114/115 的原始上报值打进联调日志框。
      unawaited(
        FlowerpotScope.of(context).logStatusDps(
          widget.deviceId,
          '相对湿度',
          HumidityStatusPageModel.reportedDps,
          hasHistoryDp: false,
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
                              title: '湿度历史读取失败',
                              message: '请稍后重试。',
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const AppSurfaceCard(
                          child: SizedBox(
                            height: 236,
                            child: AppLoading(label: '正在读取湿度历史'),
                          ),
                        );
                      }
                      final values = snapshot.data!;
                      // No humidity history function point in the DP table.
                      if (values.isEmpty) {
                        return const MetricHistoryEmptyCard(title: '暂无湿度历史');
                      }
                      return HumidityTrendChartCard(
                        values: values,
                        labels: const <String>[
                          '00:00',
                          '05:00',
                          '10:00',
                          '15:00',
                          '20:00',
                          '00:00',
                        ],
                      );
                    },
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
    final date = DateTime.now().add(Duration(days: periodOffset));
    return '${date.month}月${date.day}日';
  }
}
