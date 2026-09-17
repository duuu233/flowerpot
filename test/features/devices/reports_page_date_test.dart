import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/reports_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_history_codec.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 报表日视图的日期切换：**窗口固定 7 天（当天 + 往前 6 天）**，设备日包一次就带
/// 这么多天（2026-09-17 固件），窗口外没有数据可取。
void main() {
  const prev = Key('report-day-prev');
  const next = Key('report-day-next');
  const label = Key('report-day-label');

  testWidgets('日视图默认停在今天，没有「明天」可翻', (tester) async {
    await _pumpReports(tester, SensorMetric.waterLevel);

    expect(find.byKey(label), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(label)).data, _todayLabel());
    // 今天已经是最右边。
    expect(_enabled(tester, next), isFalse);
    expect(_enabled(tester, prev), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('往前最多翻 6 天，到边箭头点不动', (tester) async {
    await _pumpReports(tester, SensorMetric.waterLevel);

    for (var step = 1; step <= TuyaHistoryCodec.maxDailyWindow - 1; step++) {
      expect(_enabled(tester, prev), isTrue, reason: '第 $step 次往前');
      await tester.tap(find.byKey(prev));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(label)).data,
        _labelFor(_daysBack(step)),
        reason: '第 $step 次往前',
      );
    }

    // 6 天前就是窗口左边缘：再往前设备没有数据，按钮点不动。
    expect(_enabled(tester, prev), isFalse);
    expect(_enabled(tester, next), isTrue);

    // 往回翻一天又能继续往前了。
    await tester.tap(find.byKey(next));
    await tester.pumpAndSettle();
    expect(_enabled(tester, prev), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('翻到昨天时曲线右端标的是 23:45，不是「当前」', (tester) async {
    await _pumpReports(tester, SensorMetric.waterLevel);

    expect(find.text('当前'), findsOneWidget);
    expect(find.text('23:45'), findsNothing);

    await tester.tap(find.byKey(prev));
    await tester.pumpAndSettle();

    expect(find.text('当前'), findsNothing);
    expect(find.text('23:45'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('周视图没有日期可切：周包是「每天一个平均值」的一整段', (tester) async {
    await _pumpReports(tester, SensorMetric.waterLevel);

    expect(find.byKey(label), findsOneWidget);

    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();

    expect(find.byKey(label), findsNothing);
    expect(find.byKey(prev), findsNothing);

    await tester.tap(find.text('日'));
    await tester.pumpAndSettle();

    // 切回日视图还是停在今天。
    expect(tester.widget<Text>(find.byKey(label)).data, _todayLabel());
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有日历史 DP 的指标不画日期条', (tester) async {
    // PPFD 只有实时值，功能点表里没有它的历史包，翻日期没有意义。
    await _pumpReports(tester, SensorMetric.ppfd);

    expect(find.byKey(label), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key)).onPressed != null;

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _daysBack(int days) {
  final today = _today();
  return DateTime(today.year, today.month, today.day - days);
}

String _labelFor(DateTime date) {
  final base = '${date.month}月${date.day}日';
  final daysAgo = _today().difference(date).inDays;
  return switch (daysAgo) {
    0 => '$base（今天）',
    1 => '$base（昨天）',
    _ => base,
  };
}

String _todayLabel() => _labelFor(_today());

Future<void> _pumpReports(WidgetTester tester, SensorMetric metric) async {
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
        home: ReportsPage(
          arguments: ReportArguments(
            deviceId: state.devices.single.id,
            metric: metric,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
