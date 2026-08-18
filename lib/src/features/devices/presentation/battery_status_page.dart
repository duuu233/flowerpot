import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import '../models/battery_status_page_model.dart';
import 'widgets/battery_status_summary_card.dart';
import 'widgets/battery_trend_chart_card.dart';

class BatteryStatusPage extends StatefulWidget {
  const BatteryStatusPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<BatteryStatusPage> createState() => _BatteryStatusPageState();
}

class _BatteryStatusPageState extends State<BatteryStatusPage> {
  int periodOffset = 0;
  late Future<List<double>> history;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      history = FlowerpotScope.of(
        context,
      ).historyFor(widget.deviceId, SensorMetric.battery, ReportRange.day);
      initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '电池状态', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final summaryModel = BatteryStatusPageModel.fromDevice(device);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '电池状态', leading: AppBackButton()),
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
                  BatteryStatusSummaryCard(model: summaryModel),
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
                              title: '电量历史读取失败',
                              message: '请稍后重试。',
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const AppSurfaceCard(
                          child: SizedBox(
                            height: 236,
                            child: AppLoading(label: '正在读取电量历史'),
                          ),
                        );
                      }
                      final values = snapshot.data!.isEmpty
                          ? <double>[summaryModel.battery.toDouble()]
                          : snapshot.data!;
                      return BatteryTrendChartCard(
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
