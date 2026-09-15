import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/battery_status_page_model.dart';
import 'package:flowerpot/src/features/devices/presentation/battery_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/battery_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/status_metric_icon.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('battery widgets expose the Figma content', (tester) async {
    await _pumpBatteryCard(tester, const Size(375, 812), _charging);

    expect(find.text('充电中'), findsOneWidget);
    expect(find.text('94 %'), findsOneWidget);
    expect(find.text('当前电池状态'), findsOneWidget);
    expect(find.byType(ChargingBatteryBadge), findsOneWidget);
    expect(find.byType(StatusMetricIcon), findsOneWidget);
    expect(find.text('建议'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('description keeps a two-line height whatever the status', (
    tester,
  ) async {
    // 2026-09-15 产品：「充电中」下面的描述长短随状态变，要固定两行高，不能跳。
    await _pumpBatteryCard(tester, const Size(375, 812), _charging);
    final charging = tester.getSize(
      find.byKey(const Key('battery-status-description')),
    );
    await _pumpBatteryCard(
      tester,
      const Size(375, 812),
      _charging.copyWithDescription('电量充足。'),
    );
    final short = tester.getSize(
      find.byKey(const Key('battery-status-description')),
    );

    expect(short.height, charging.height);
    final lineHeight = tester.getSize(find.text('电量充足。')).height;
    expect(short.height, greaterThanOrEqualTo(lineHeight * 2 - 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('battery card fits at 320x568', (tester) async {
    await _pumpBatteryCard(tester, const Size(320, 568), _charging);

    expect(find.text('当前电池状态'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('battery page shows the card and no history report', (
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
          home: BatteryStatusPage(deviceId: state.devices.single.id),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('电池状态'), findsOneWidget);
    expect(find.text('充电中'), findsOneWidget);
    expect(find.text('94 %'), findsOneWidget);
    // 电量历史报表 2026-09-15 删掉了，日期切换一并去掉。
    expect(find.byType(DateRangeNavigator), findsNothing);
    expect(find.text('暂无电量历史'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

const _charging = BatteryStatusPageModel(
  deviceId: 'device-01',
  status: '充电中',
  description: '已连接电源，建议长期连接电源使用。',
  battery: 94,
  charging: true,
);

extension on BatteryStatusPageModel {
  BatteryStatusPageModel copyWithDescription(String text) =>
      BatteryStatusPageModel(
        deviceId: deviceId,
        status: status,
        description: text,
        battery: battery,
        charging: charging,
      );
}

Future<void> _pumpBatteryCard(
  WidgetTester tester,
  Size size,
  BatteryStatusPageModel model,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: BatteryStatusSummaryCard(model: model),
        ),
      ),
    ),
  );
  await tester.pump();
}
