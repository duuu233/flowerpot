import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/water_status_page_model.dart';
import 'package:flowerpot/src/features/devices/presentation/water_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/water_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/water_trend_chart_card.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('water status widgets expose the Figma content', (tester) async {
    await _pumpWaterWidgets(tester, const Size(375, 812));

    expect(find.text('喝水中'), findsOneWidget);
    expect(find.text('当前水仓水位'), findsOneWidget);
    expect(find.text('当前土壤湿度'), findsOneWidget);
    expect(find.text('适中'), findsOneWidget);
    expect(find.text('水仓水位变化'), findsOneWidget);
    expect(find.text('建议'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('metric groups keep clear of the divider', (tester) async {
    // 2026-09-13 产品反馈：中间竖线和右边那组重叠。竖线两边要各留 9，375 与 320
    // 两种宽度都不能贴上去，也不能溢出。
    for (final size in const <Size>[Size(375, 812), Size(320, 568)]) {
      await _pumpWaterWidgets(tester, size);

      final divider = tester.getRect(
        find.byKey(const Key('water-metric-divider')),
      );
      final level = tester.getRect(find.byKey(const Key('water-metric-level')));
      final soil = tester.getRect(find.byKey(const Key('water-metric-soil')));

      expect(divider.width, 1, reason: '$size');
      expect(level.right, lessThanOrEqualTo(divider.left - 9 + 0.01));
      expect(soil.left, greaterThanOrEqualTo(divider.right + 9 - 0.01));
      // 两组各占一半，宽度一致，左右看起来才对齐。
      expect((level.width - soil.width).abs(), lessThan(0.01));
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('water status content scrolls at 320x568', (tester) async {
    await _pumpWaterWidgets(tester, const Size(320, 568));

    final advice = find.text('建议');
    await tester.ensureVisible(advice);
    await tester.pump();

    expect(advice, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('water page: day range, soil moisture as enum text only', (
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
          home: WaterStatusPage(deviceId: state.devices.single.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('需水状态'), findsOneWidget);
    expect(find.text('喝水中'), findsOneWidget);
    expect(find.text('80 ml'), findsOneWidget);
    // 2026-11-23：DP 106 只报 dry / moderate，只显示档位文字，不显示数值。
    expect(find.text('适中'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(
      tester
          .widget<TimeRangeSelector<ReportRange>>(
            find.byType(TimeRangeSelector<ReportRange>),
          )
          .selected,
      ReportRange.day,
    );

    // 只剩水仓水位一条曲线，没有切换菜单，也没有土壤湿度曲线。
    final chart = tester.widget<WaterTrendChartCard>(
      find.byType(WaterTrendChartCard),
    );
    expect(chart.metric, WaterStatusMetric.waterLevel);
    expect(find.text('水仓水位变化'), findsOneWidget);
    expect(find.text('土壤湿度变化'), findsNothing);
    expect(find.byType(PopupMenuButton<WaterStatusMetric>), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpWaterWidgets(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const model = WaterStatusPageModel(
    deviceId: 'device-01',
    status: '喝水中',
    description: '正在慢慢吸收水分。',
    waterLevel: 80,
    soilMoisture: '适中',
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
