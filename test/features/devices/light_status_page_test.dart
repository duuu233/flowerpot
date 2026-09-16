import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/light_status_page_model.dart';
import 'package:flowerpot/src/features/devices/presentation/light_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/light_dli_bar_chart.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/light_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/water_trend_line_chart.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('light status widgets expose the Figma content', (tester) async {
    await _pumpLightStatus(tester, const Size(375, 812));

    expect(find.text('阳光明媚'), findsOneWidget);
    expect(find.text('305'), findsOneWidget);
    expect(find.text('5.642'), findsOneWidget);
    expect(find.text('DLI（每日光量积分）'), findsOneWidget);
    expect(find.text('建议'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light status content scrolls at 320x568', (tester) async {
    await _pumpLightStatus(tester, const Size(320, 568));

    final advice = find.text('建议');
    await tester.ensureVisible(advice);
    await tester.pump();

    expect(advice, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light status page uses device data and switches range', (
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
          home: LightStatusPage(deviceId: state.devices.single.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('光照状态'), findsOneWidget);
    expect(find.text('阳光明媚'), findsOneWidget);
    expect(find.text('305'), findsOneWidget);
    expect(find.text('5.642'), findsOneWidget);
    // 2026-09-16 产品：进页面默认就是日历史，不再停在周。
    expect(
      tester
          .widget<TimeRangeSelector<ReportRange>>(
            find.byType(TimeRangeSelector<ReportRange>),
          )
          .selected,
      ReportRange.day,
    );
    // 历史图读的是 137–139 的光照（lux），不再是功能点表里没有的 DLI。
    expect(find.text('光照强度'), findsOneWidget);
    expect(find.text('DLI（每日光量积分）'), findsNothing);
    expect(find.text('暂无光照历史'), findsNothing);
    // 日视图是折线：96 根一刻钟一根的柱子挤在一张卡片里没法看。
    expect(find.byType(WaterTrendLineChart), findsOneWidget);
    expect(find.byType(LightDliBarChart), findsNothing);
    // 同需水状态页：进页面在联调日志里记这一页的 DP。
    expect(
      state.interactionLog.any((line) => line.contains('读取 ← [光照状态]')),
      isTrue,
    );

    await tester.tap(find.text('周'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester
          .widget<TimeRangeSelector<ReportRange>>(
            find.byType(TimeRangeSelector<ReportRange>),
          )
          .selected,
      ReportRange.week,
    );
    // 周 / 月还是柱状图，7 根 / 31 根柱子看得清。
    expect(find.byType(LightDliBarChart), findsOneWidget);
    expect(find.byType(WaterTrendLineChart), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpLightStatus(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const model = LightStatusPageModel(
    deviceId: 'device-01',
    status: '阳光明媚',
    description: '今天的阳光正好。',
    illuminance: 305,
    ppfd: 5.642,
    dliValues: <double>[.74, .67, .58, .61, .90, .63, .45],
    advice: '当前光照基本够用，建议保持在明亮散射光处；若叶色变浅可每天补光1小时。',
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              const LightStatusSummaryCard(model: model),
              const SizedBox(height: 12),
              MetricChartCard(
                title: 'DLI（每日光量积分）',
                unit: 'mol/m²/天',
                chart: LightDliBarChart(
                  values: model.dliValues,
                  labels: <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
                ),
              ),
              const SizedBox(height: 12),
              AppInfoCard(title: '建议', message: model.advice),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
