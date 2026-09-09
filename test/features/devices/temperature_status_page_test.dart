import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/temperature_status_page_model.dart';
import 'package:flowerpot/src/features/devices/presentation/temperature_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/temperature_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/temperature_trend_chart_card.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('temperature widgets expose the Figma content', (tester) async {
    await _pumpTemperatureWidgets(tester, const Size(375, 812));

    expect(find.text('正舒适'), findsOneWidget);
    expect(find.text('26.9°C'), findsOneWidget);
    expect(find.text('当前空气温度'), findsOneWidget);
    expect(find.text('空气温度变化'), findsOneWidget);
    expect(find.text('建议'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temperature content scrolls at 320x568', (tester) async {
    await _pumpTemperatureWidgets(tester, const Size(320, 568));

    final advice = find.text('建议');
    await tester.ensureVisible(advice);
    await tester.pump();

    expect(advice, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temperature page loads device data and day history', (
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
        account: '13800138000',
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
          home: TemperatureStatusPage(deviceId: state.devices.single.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('空气温度'), findsOneWidget);
    expect(find.text('正舒适'), findsOneWidget);
    expect(find.text('26.9°C'), findsOneWidget);
    expect(find.byType(TemperatureTrendChartCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpTemperatureWidgets(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const model = TemperatureStatusPageModel(
    deviceId: 'device-01',
    status: '正舒适',
    description: '温度刚刚好，植物正舒服地长着呢，继续保持。',
    temperature: 26.9,
    advice: '适宜温度范围为18°C~28°C。\n温度过高或过低都会影响植物健康生长哦。',
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              const TemperatureStatusSummaryCard(model: model),
              const SizedBox(height: 12),
              const TemperatureTrendChartCard(
                values: <double>[25, 25, 30, 24, 26.9, 30, 21, 21],
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
