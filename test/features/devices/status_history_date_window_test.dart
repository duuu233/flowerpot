import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/history_period.dart';
import 'package:flowerpot/src/features/devices/presentation/humidity_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/humidity_trend_chart_card.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_history_codec.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 状态页那条日期切换条的窗口。
///
/// 2026-09-17 用户实测报的 BUG：**历史数据日期可以无限调**——四个状态页的
/// `onPrevious` 都是裸的 `periodOffset--`，一直点能翻到去年，而设备根本没有那些天
/// 的数据。往后翻本来就有界，坏的一直只有往前这一侧。
void main() {
  // 2026-10-28 产品：光照状态页周 / 月补日期。口径同「N天前」：最后一点 = 昨天，往左逐天回推。
  group('HistoryPeriod 周 / 月日期', () {
    test('最后一点是昨天，第一点是今天往前 count 天', () {
      expect(HistoryPeriod.barDate(6, 7), HistoryPeriod.dayFor(-1));
      expect(HistoryPeriod.barDate(0, 7), HistoryPeriod.dayFor(-7));
      expect(HistoryPeriod.barDate(0, 1), HistoryPeriod.dayFor(-1));
    });

    test('柱状图日期标在原来「N天前」的位置', () {
      final labels = HistoryPeriod.dateBarLabels(28);
      final relative = HistoryPeriod.relativeBarLabels(28);
      expect(labels.length, 28);
      for (var i = 0; i < 28; i++) {
        expect(labels[i].isEmpty, relative[i].isEmpty, reason: '第 $i 根');
      }
      expect(labels.last, HistoryPeriod.shortDate(HistoryPeriod.dayFor(-1)));
      expect(labels[20], HistoryPeriod.shortDate(HistoryPeriod.dayFor(-8)));
    });

    test('折线图日期刻度与相对刻度取同样的点', () {
      final dates = HistoryPeriod.dateTicks(28);
      expect(dates.length, HistoryPeriod.relativeTicks(28).length);
      expect(dates.first, HistoryPeriod.shortDate(HistoryPeriod.dayFor(-28)));
      expect(dates.last, HistoryPeriod.shortDate(HistoryPeriod.dayFor(-1)));
      expect(HistoryPeriod.dateTicks(3), <String>[
        HistoryPeriod.shortDate(HistoryPeriod.dayFor(-3)),
        HistoryPeriod.shortDate(HistoryPeriod.dayFor(-2)),
        HistoryPeriod.shortDate(HistoryPeriod.dayFor(-1)),
      ]);
      expect(HistoryPeriod.dateTicks(0), isEmpty);
    });

    test('日期条写首尾日期，没有点时退回窗口文案', () {
      final first = HistoryPeriod.dayFor(-7);
      final last = HistoryPeriod.dayFor(-1);
      expect(
        HistoryPeriod.windowDateLabel(ReportRange.week, 7),
        '${first.month}月${first.day}日 - ${last.month}月${last.day}日',
      );
      expect(HistoryPeriod.windowDateLabel(ReportRange.week, 0), '近 4 周');
      expect(HistoryPeriod.windowDateLabel(ReportRange.month, 0), '近半年');
    });
  });

  group('HistoryPeriod 窗口规则', () {
    test('日视图就是设备日包那 7 天：当天 + 往前 6 天', () {
      expect(HistoryPeriod.maxBack(ReportRange.day), 6);
      expect(TuyaHistoryCodec.maxDailyWindow, 7);

      for (var offset = 0; offset > -6; offset--) {
        expect(
          HistoryPeriod.canGoBack(ReportRange.day, offset),
          isTrue,
          reason: 'offset $offset 还该能往前',
        );
      }
      // 6 天前就是左边缘，到这儿点不动。
      expect(HistoryPeriod.canGoBack(ReportRange.day, -6), isFalse);
      // 更离谱的值（真出现了也别放行）同样是 false。
      expect(HistoryPeriod.canGoBack(ReportRange.day, -7), isFalse);
      expect(HistoryPeriod.canGoBack(ReportRange.day, -400), isFalse);
    });

    test('周 / 月：设备只有当期那一包，一格都不给往前翻', () {
      for (final range in <ReportRange>[
        ReportRange.week,
        ReportRange.month,
      ]) {
        expect(HistoryPeriod.maxBack(range), 0, reason: '$range');
        expect(HistoryPeriod.canGoBack(range, 0), isFalse, reason: '$range');
        expect(HistoryPeriod.canGoBack(range, -1), isFalse, reason: '$range');
      }
    });

    test('往后翻：当期就是最右边，没有「明天」', () {
      expect(HistoryPeriod.canGoForward(0), isFalse);
      expect(HistoryPeriod.canGoForward(-1), isTrue);
      expect(HistoryPeriod.canGoForward(-6), isTrue);
    });

    test('offset → 日期：只到日，往前第 N 天就差 N 天', () {
      final today = HistoryPeriod.dayFor(0);
      expect(today.hour, 0);
      expect(today.minute, 0);
      expect(today.second, 0);

      for (var days = 1; days <= 6; days++) {
        final past = HistoryPeriod.dayFor(-days);
        expect(
          today.difference(past).inDays,
          days,
          reason: '往前 $days 天',
        );
      }
    });
  });

  group('相对湿度状态页的日期切换（用户报 BUG 的那条路）', () {
    testWidgets('往前最多 6 天，到边箭头点不动，再点也不动', (tester) async {
      final state = await _pumpHumidityPage(tester);

      // 今天：往前能点，往后不能。
      expect(_prevEnabled(tester), isTrue);
      expect(_nextEnabled(tester), isFalse);
      final todayLabel = _label(tester);

      for (var step = 1; step <= 6; step++) {
        expect(_prevEnabled(tester), isTrue, reason: '第 $step 次往前');
        await tester.tap(_prevButton());
        await tester.pumpAndSettle();
      }

      // 6 天前：到左边缘了。
      final edgeLabel = _label(tester);
      expect(edgeLabel, isNot(todayLabel));
      expect(_prevEnabled(tester), isFalse);
      expect(_nextEnabled(tester), isTrue);

      // ⚠️ 这里就是原来的 BUG：接着点还能一直往前翻。现在按钮禁用，点了标签不变。
      await tester.tap(_prevButton(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_label(tester), edgeLabel);

      // 一路点回今天，往后又到边。
      for (var step = 1; step <= 6; step++) {
        await tester.tap(_nextButton());
        await tester.pumpAndSettle();
      }
      expect(_label(tester), todayLabel);
      expect(_nextEnabled(tester), isFalse);
      expect(state.devices, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('曲线跟着日期换：翻到设备没报过的那天是空态，不再画今天那条', (tester) async {
      await _pumpHumidityPage(tester);

      // 今天有数据（演示仓库造的日包）。
      expect(find.byType(HumidityTrendChartCard), findsOneWidget);
      final today = tester
          .widget<HumidityTrendChartCard>(find.byType(HumidityTrendChartCard))
          .values;
      expect(today, isNotEmpty);

      await tester.tap(_prevButton());
      await tester.pumpAndSettle();

      // ⚠️ 原来这里画的还是今天那条曲线（`chartSeries` 压根不看 periodOffset），
      // 标签翻了、图没换。演示仓库的设备只有「最新那天」一包，所以昨天是空态。
      expect(find.byType(HumidityTrendChartCard), findsNothing);
      expect(find.text('暂无湿度历史'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Finder _navigator() => find.byType(DateRangeNavigator);

/// 条子里就两颗 `IconButton`，顺序是 [前一天, 后一天]（`DateRangeNavigator` 的 Row
/// 是「左箭头 / 标签 / 右箭头」，标签这两页没传 `onLabelTap`，不是按钮）。
Finder _prevButton() =>
    find.descendant(of: _navigator(), matching: find.byType(IconButton)).first;

Finder _nextButton() =>
    find.descendant(of: _navigator(), matching: find.byType(IconButton)).last;

bool _prevEnabled(WidgetTester tester) =>
    tester.widget<IconButton>(_prevButton()).onPressed != null;

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<IconButton>(_nextButton()).onPressed != null;

String _label(WidgetTester tester) =>
    tester.widget<DateRangeNavigator>(_navigator()).label;

Future<FlowerpotState> _pumpHumidityPage(WidgetTester tester) async {
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
        home: HumidityStatusPage(deviceId: state.devices.single.id),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return state;
}
