import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/water_status_page_model.dart';
import 'package:flowerpot/src/features/devices/presentation/water_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/water_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/water_trend_chart_card.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('water status widgets expose the Figma content', (tester) async {
    await _pumpWaterWidgets(tester, const Size(375, 812));

    expect(find.text('喝水中'), findsOneWidget);
    expect(find.text('当前水仓水位'), findsOneWidget);
    expect(find.text('当前土壤湿度'), findsOneWidget);
    expect(find.text('水仓水位变化'), findsOneWidget);
    expect(find.text('建议'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('water status content scrolls at 320x568', (tester) async {
    await _pumpWaterWidgets(tester, const Size(320, 568));

    final advice = find.text('建议');
    await tester.ensureVisible(advice);
    await tester.pump();

    expect(advice, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('water status page starts at day and switches metric', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    await tester.runAsync(
      () => state.login(
        account: 'demo@flowerpot.local',
        credential: 'demo',
        region: LoginRegion.domestic,
        verificationCode: false,
      ),
    );

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: WaterStatusPage(deviceId: state.devices.single.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('需水状态'), findsOneWidget);
    expect(find.text('喝水中'), findsOneWidget);
    expect(find.text('80 ml'), findsOneWidget);
    expect(find.text('97 %'), findsOneWidget);
    expect(
      tester
          .widget<TimeRangeSelector<ReportRange>>(
            find.byType(TimeRangeSelector<ReportRange>),
          )
          .selected,
      ReportRange.day,
    );

    await tester.tap(find.text('水仓水位变化'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('土壤湿度变化'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      tester
          .widget<WaterTrendChartCard>(find.byType(WaterTrendChartCard))
          .metric,
      WaterStatusMetric.soilMoisture,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('soil moisture mode can be opened directly', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    await tester.runAsync(
      () => state.login(
        account: 'demo@flowerpot.local',
        credential: 'demo',
        region: LoginRegion.domestic,
        verificationCode: false,
      ),
    );

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: WaterStatusPage(
            deviceId: state.devices.single.id,
            initialMetric: WaterStatusMetric.soilMoisture,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final chart = tester.widget<WaterTrendChartCard>(
      find.byType(WaterTrendChartCard),
    );
    expect(chart.metric, WaterStatusMetric.soilMoisture);
    expect(chart.values, contains(97));
    expect(find.text('土壤湿度变化'), findsOneWidget);
    expect(find.text('97 %'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpWaterWidgets(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const model = WaterStatusPageModel(
    deviceId: 'device-01',
    status: '喝水中',
    description: '植物正在从水仓中直接吸取水分，请保持当前状态。',
    waterLevel: 80,
    soilMoisture: 97,
    advice: '当前湿度适宜，建议保持现有浇水频率，避免盆土长期过湿，确保植物根系健康。',
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              const WaterStatusSummaryCard(model: model),
              const SizedBox(height: 12),
              WaterTrendChartCard(
                metric: WaterStatusMetric.waterLevel,
                values: const <double>[76, 76, 85, 73, 80, 85, 68, 68],
                labels: const <String>[
                  '00:00',
                  '05:00',
                  '10:00',
                  '15:00',
                  '20:00',
                  '00:00',
                ],
                onMetricChanged: (_) {},
              ),
              const SizedBox(height: 12),
              CareAdviceCard(message: model.advice, emphasized: true),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
