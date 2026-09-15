import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
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
  late Future<List<double>> history;
  bool initialized = false;

  /// 上次取曲线时设备快照里的那一段历史，用来认出「涂鸦又推来了新的历史 DP」。
  List<double> _loadedSeries = const <double>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      history = _load();
      initialized = true;
      // 同需水状态页：进页面把 112/113/146 的原始上报值打进联调日志框。
      unawaited(
        FlowerpotScope.of(context).logStatusDps(
          widget.deviceId,
          '空气温度',
          TemperatureStatusPageModel.reportedDps,
          hasHistoryDp: false,
        ),
      );
    } else if (FlowerpotScope.of(context).historyReportedSince(
      widget.deviceId,
      '空气温度',
      SensorMetric.temperature,
      ReportRange.day,
      _loadedSeries,
    )) {
      // 和需水 / 光照页同一套：功能点表目前没有这项的历史 DP，快照里这一段恒为空，
      // 这个分支真机上不会进；将来固件补了历史 DP、仓库接上解码，曲线同样跟着上报刷新。
      history = _load();
    }
  }

  Future<List<double>> _load() {
    final state = FlowerpotScope.of(context);
    _loadedSeries = state.reportedHistory(
      widget.deviceId,
      SensorMetric.temperature,
      ReportRange.day,
    );
    return state.historyFor(
      widget.deviceId,
      SensorMetric.temperature,
      ReportRange.day,
    );
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
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '空气温度', leading: AppBackButton()),
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
                  TemperatureStatusSummaryCard(model: summaryModel),
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
                              title: '温度历史读取失败',
                              message: '请稍后重试。',
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const AppSurfaceCard(
                          child: SizedBox(
                            height: 236,
                            child: AppLoading(label: '正在读取温度历史'),
                          ),
                        );
                      }
                      final values = snapshot.data!;
                      // No temperature history function point in the DP table.
                      if (values.isEmpty) {
                        return const MetricHistoryEmptyCard(title: '暂无温度历史');
                      }
                      return TemperatureTrendChartCard(
                        unit: summaryModel.temperatureSymbol,
                        // The axis follows the unit the device reports in.
                        maxValue: device.settings.temperatureFromCelsius(50),
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
