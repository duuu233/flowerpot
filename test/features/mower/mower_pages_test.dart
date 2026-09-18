import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/pairing_gate.dart';
import 'package:flowerpot/src/features/devices/presentation/device_search_page.dart';
import 'package:flowerpot/src/features/mower/mower_demo.dart';
import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/presentation/mower_home_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';

void main() {
  // ⚠️ MowerDevice 是单例：上一条用例改过的开关会漏到下一条，每条前后都要复位。
  setUp(MowerDevice.instance.resetForTest);
  tearDown(() {
    MowerDemo.reset();
    MowerDevice.instance.resetForTest();
  });

  testWidgets('搜索页的设备列表下面固定列着割草机，点「连接」进割草机首页', (tester) async {
    await _pumpSearchPage(tester);

    expect(
      find.byKey(const Key('device-search-mower-demo')),
      findsOneWidget,
    );
    expect(find.text('YSmower-01'), findsOneWidget);
    // 这一行是静态数据，不是扫到的设备——行上必须写明，否则在配网动线里会被
    // 当成"真的搜到了一台割草机"。
    expect(find.textContaining('静态演示数据'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('device-search-mower-demo-connect')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('mower-home-target'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('门禁关掉之后搜索页不再列那条静态数据', (tester) async {
    MowerDemo.enabled = false;
    await _pumpSearchPage(tester);

    expect(find.byKey(const Key('device-search-mower-demo')), findsNothing);
    expect(find.text('YSmower-01'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('割草机首页画出电量环、今日计划和四颗操作按钮', (tester) async {
    await _pumpMowerHome(tester);

    expect(find.byKey(const Key('mower-battery-ring')), findsOneWidget);
    expect(find.text('电量 78%'), findsOneWidget);
    expect(find.byKey(const Key('mower-today-plan')), findsOneWidget);
    expect(find.text('09:00  →  12:30'), findsOneWidget);
    expect(find.byKey(const Key('mower-safety-notice')), findsOneWidget);
    // 左三＝DP3 的三个可下发模式，最右＝DP2 开关
    for (final key in <String>[
      'mower-action-smart',
      'mower-action-spot',
      'mower-action-gotoCharge',
      'mower-action-switch',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('停止态下左边三颗点不动，点「继续」（DP2=true）之后才能点', (tester) async {
    await _pumpMowerHome(tester);

    // 初始 DP2=false：按钮显示「继续」，左三点了没反应（状态胶囊仍是待机）
    expect(find.text('继续'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pump();
    expect(find.text('待机'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mower-action-switch')));
    await tester.pump();
    // DP2=true：按钮变「停止」，这时「自动」才点得动（DP3=smart → DP5=mowing）
    expect(find.text('停止'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pump();
    expect(find.text('割草中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一个模式不重复下发：点过「自动」之后它置灰', (tester) async {
    await _pumpMowerHome(tester);
    await tester.tap(find.byKey(const Key('mower-action-switch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pump();

    expect(MowerDevice.instance.isCurrentMode(MowerMode.smart), isTrue);
    // 再点一次不该有任何变化（按钮此时 onTap 为 null）
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pump();
    expect(MowerDevice.instance.mode, MowerMode.smart);
    expect(tester.takeException(), isNull);
  });

  testWidgets('停止再启动，按上一次点过的模式走（记忆）', (tester) async {
    await _pumpMowerHome(tester);
    await tester.tap(find.byKey(const Key('mower-action-switch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mower-action-spot')));
    await tester.pump();
    expect(find.text('定点割草'), findsOneWidget);

    // 停止
    await tester.tap(find.byKey(const Key('mower-action-switch')));
    await tester.pump();
    expect(find.text('已暂停'), findsOneWidget);

    // 再启动：回到「定点」，不是回到待机
    await tester.tap(find.byKey(const Key('mower-action-switch')));
    await tester.pump();
    expect(MowerDevice.instance.mode, MowerMode.spot);
    expect(find.text('定点割草'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('盖子没合（DP118=false）时点「自动」弹窗且不下发', (tester) async {
    await _pumpMowerHome(tester);

    // 没有真机，只读 DP 由模拟上报面板改：长按电量环 → 点盖子那一行
    await tester.longPress(find.byKey(const Key('mower-battery-ring')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-report-cover')));
    await tester.pumpAndSettle();
    expect(MowerDevice.instance.coverClosed, isFalse);
    Navigator.of(
      tester.element(find.byKey(const Key('mower-report-cover'))),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mower-action-switch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pumpAndSettle();

    expect(find.text('盖子未合上'), findsOneWidget);
    expect(
      MowerDevice.instance.mode,
      isNot(MowerMode.smart),
      reason: '弹窗之后不许下发 DP3',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('割草计划页按勾选的那几天合计工作时间', (tester) async {
    await _pumpMowerHome(tester);
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pump();

    expect(find.text('总工作时间：5小时23分钟'), findsOneWidget);
    // 周日那两段（08:00–09:00、14:00–15:00）一取消勾选就从合计里去掉。
    await tester.tap(find.byKey(const Key('mower-plan-day-0')));
    await tester.pump();
    expect(find.text('总工作时间：3小时23分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('「恢复默认」先问一句，确认之后计划回到默认', (tester) async {
    await _pumpMowerHome(tester);
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('mower-plan-day-0')));
    await tester.pump();
    expect(find.text('总工作时间：3小时23分钟'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mower-plan-restore')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('mower-plan-restore-dialog')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('mower-plan-restore-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('总工作时间：5小时23分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页列着八项，「设备参数」进得去', (tester) async {
    await _pumpMowerHome(tester);
    await tester.tap(find.byKey(const Key('mower-nav-settings')));
    await tester.pump();

    expect(find.byKey(const Key('mower-settings-区域设置')), findsOneWidget);
    expect(find.byKey(const Key('mower-settings-delete')), findsOneWidget);

    await tester.tap(find.byKey(const Key('mower-settings-设备参数')));
    await tester.pumpAndSettle();

    expect(find.text('YM-1200'), findsOneWidget);
    expect(find.text('YM202608240018'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _tapRing(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('mower-battery-ring')));
  await tester.pump();
}

Future<void> _pumpMowerHome(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // ⚠️ 必须套 FlowerpotScope：割草机各页进页面都会往联调日志里记一条
  // （`FlowerpotScope.of(context).logMowerInteraction`），没有 scope 会断言失败。
  final state = FlowerpotState(
    repository: MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const MowerHomePage(),
        onGenerateRoute: (settings) =>
            AppRoutes.onGenerateRoute(settings, authenticated: true),
      ),
    ),
  );
  // 各页的 postFrameCallback（记日志、弹「还没有支持的 DPID」）在这一拍跑完
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpSearchPage(WidgetTester tester) async {
  // 搜索页本身要 `FlowerpotState`；这一轮只看它下面那条静态行，扫描结果无关紧要。
  PairingGate.apEnabled = true;
  addTearDown(PairingGate.reset);
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        navigatorObservers: <NavigatorObserver>[AppRoutes.routeObserver],
        home: const DeviceSearchPage(),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.mowerHome) {
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Center(child: Text('mower-home-target')),
              ),
            );
          }
          return null;
        },
      ),
    ),
  );
  await tester.pump();
}
