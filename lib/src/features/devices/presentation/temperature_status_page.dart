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
    final values = FlowerpotScope.of(
      context,
    ).chartSeries(widget.deviceId, SensorMetric.temperature, ReportRange.day);
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
                  if (values.isEmpty)
                    const MetricHistoryEmptyCard(title: '暂无温度历史')
                  else
                    TemperatureTrendChartCard(
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
