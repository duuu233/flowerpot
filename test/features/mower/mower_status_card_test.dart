import 'package:flowerpot/src/features/mower/mower_ui.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_status_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 稿子 746:2657「割草机-控制-充电中」：闪电挪进环里、整机图上方，1.4 s 循环；
/// 环下那行只剩「充电中 78%」。
///
/// ⚠️ 闪电是无限循环的动画，这里**不能用 pumpAndSettle**（永远等不到停），只按时长 pump。
void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    MowerPowerState tone, {
    bool disableAnimations = false,
  }) async {
    // MediaQuery 要套在 MaterialApp 里面：外面那层会被 MaterialApp 自己按窗口建的盖掉。
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: MowerStatusCard(
              tone: tone,
              percent: 78,
              statusLabel: '待机',
            ),
          ),
        ),
      ),
    );
    // 动画在建树那一帧里 repeat()，Ticker 从下一帧才开始计时。
    await tester.pump();
  }

  Finder assetImage(String name) => find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == name,
  );

  double boltOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(find.byKey(const Key('mower-charging-bolt')))
      .opacity
      .value;

  testWidgets('充电中：环里有闪电并且在动，环下那行不带图标', (tester) async {
    await pumpCard(tester, MowerPowerState.charging);

    expect(find.byKey(const Key('mower-charging-bolt')), findsOneWidget);
    expect(find.textContaining('充电中', findRichText: true), findsOneWidget);
    expect(assetImage(MowerAssets.batteryChargingIcon), findsNothing);

    final start = boltOpacity(tester);
    await tester.pump(const Duration(milliseconds: 700));
    final middle = boltOpacity(tester);
    expect(middle, greaterThan(start), reason: '前半程变亮');
    await tester.pump(const Duration(milliseconds: 700));
    expect(boltOpacity(tester), moreOrLessEquals(start, epsilon: .02),
        reason: '1.4 s 一个周期，回到起点');
    expect(tester.takeException(), isNull);
  });

  testWidgets('减弱动态效果：闪电停在最亮那一帧', (tester) async {
    await pumpCard(tester, MowerPowerState.charging, disableAnimations: true);

    final still = boltOpacity(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(boltOpacity(tester), still);
    expect(still, moreOrLessEquals(1));
  });

  testWidgets('非充电态没有闪电，告警态仍带图标', (tester) async {
    await pumpCard(tester, MowerPowerState.batteryWarning);

    expect(find.byKey(const Key('mower-charging-bolt')), findsNothing);
    expect(assetImage(MowerAssets.batteryWarningIcon), findsOneWidget);
  });
}
