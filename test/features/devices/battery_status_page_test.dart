import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/battery_status_page_model.dart';
import 'package:flowerpot/src/features/devices/presentation/battery_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/battery_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/battery_trend_chart_card.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('battery widgets expose the Figma content', (tester) async {
    await _pumpBatteryWidgets(tester, const Size(375, 812));

    expect(find.text('充电中'), findsOneWidget);
    expect(find.text('94 %'), findsOneWidget);
    expect(find.text('当前电池状态'), findsOneWidget);
    expect(find.text('电池电量变化'), findsOneWidget);
    expect(find.byType(ChargingBatteryBadge), findsNWidgets(2));
    expect(find.text('建议'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('battery content remains usable at 320x568', (tester) async {
    await _pumpBatteryWidgets(tester, const Size(320, 568));

    final chart = find.byType(BatteryTrendChartCard);
    await tester.ensureVisible(chart);
    await tester.pump();

    expect(chart, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('battery page loads charging device data and history', (
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
          home: BatteryStatusPage(deviceId: state.devices.single.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('电池状态'), findsOneWidget);
    expect(find.text('充电中'), findsOneWidget);
    expect(find.text('94 %'), findsOneWidget);
    final chart = tester.widget<BatteryTrendChartCard>(
      find.byType(BatteryTrendChartCard),
    );
    expect(chart.values, contains(94));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpBatteryWidgets(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const model = BatteryStatusPageModel(
    deviceId: 'device-01',
    status: '充电中',
    description: '已连接电源，建议长期连接电源使用。',
    battery: 94,
    charging: true,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              const BatteryStatusSummaryCard(model: model),
              const SizedBox(height: 12),
              const BatteryTrendChartCard(
                values: <double>[90, 90, 100, 88, 94, 100, 82, 82],
                labels: <String>[
                  '00:00',
                  '05:00',
                  '10:00',
                  '15:00',
                  '20:00',
                  '00:00',
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
