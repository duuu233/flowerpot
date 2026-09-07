import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/humidity_status_page_model.dart';
import 'package:flowerpot/src/features/devices/presentation/humidity_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/humidity_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/humidity_trend_chart_card.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('humidity widgets expose the Figma content', (tester) async {
    await _pumpHumidityWidgets(tester, const Size(375, 812));

    expect(find.text('正舒服'), findsOneWidget);
    expect(find.text('52 %'), findsOneWidget);
    expect(find.text('当前相对湿度'), findsOneWidget);
    expect(find.text('相对湿度变化'), findsOneWidget);
    expect(find.text('建议'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('humidity content scrolls at 320x568', (tester) async {
    await _pumpHumidityWidgets(tester, const Size(320, 568));

    final advice = find.text('建议');
    await tester.ensureVisible(advice);
    await tester.pump();

    expect(advice, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('humidity page loads device data and day history', (
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
          home: HumidityStatusPage(deviceId: state.devices.single.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('相对湿度'), findsOneWidget);
    expect(find.text('正舒服'), findsOneWidget);
    expect(find.text('52 %'), findsOneWidget);
    final chart = tester.widget<HumidityTrendChartCard>(
      find.byType(HumidityTrendChartCard),
    );
    expect(chart.values, contains(52));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpHumidityWidgets(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const model = HumidityStatusPageModel(
    deviceId: 'device-01',
    status: '正舒服',
    description: '湿度刚刚好，叶子呼吸很顺畅，继续保持。',
    humidity: 52,
    advice: '当前湿度适宜，继续保持现有养护环境，有助于植物健康生长。',
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              const HumidityStatusSummaryCard(model: model),
              const SizedBox(height: 12),
              const HumidityTrendChartCard(
                values: <double>[50, 50, 60, 48, 52, 60, 42, 42],
                labels: <String>[
                  '00:00',
                  '05:00',
                  '10:00',
                  '15:00',
                  '20:00',
                  '00:00',
                ],
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
