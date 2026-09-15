import 'dart:async';

import 'package:flowerpot/src/app/app_route_tracker.dart';
import 'package:flowerpot/src/app/network_alert.dart';
import 'package:flowerpot/src/core/network/network_status.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mock_tuya_repository.dart';

void main() {
  var online = false;

  setUp(() {
    online = false;
    NetworkStatus.probe = () async => online;
  });

  Future<void> pumpHost(
    WidgetTester tester, {
    Widget home = const _PlainPage(),
    bool enabled = false,
  }) async {
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    final routes = AppRouteTracker();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[routes],
        builder: (context, child) => NetworkAlertHost(
          state: state,
          routes: routes,
          enabled: enabled,
          child: child!,
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  NavigatorState navigatorOf(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator));

  Future<void> tapRetry(WidgetTester tester) async {
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(NetworkAlertHost.retrySpinner);
    await tester.pumpAndSettle();
  }

  testWidgets('offline at start-up shows the alert with the product copy', (
    tester,
  ) async {
    await pumpHost(tester, enabled: true);

    expect(find.text('网络异常'), findsOneWidget);
    expect(find.text('当前网络不可用，请检查网络后重试'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('网络异常'), findsNothing);

    // 取消后的冷却期内，再来的失败不弹。
    NetworkStatus.reportFailure();
    await tester.pumpAndSettle();
    expect(find.text('网络异常'), findsNothing);
    await tester.pump(NetworkAlertHost.cancelCooldown);
  });

  testWidgets('online at start-up shows nothing', (tester) async {
    online = true;
    await pumpHost(tester, enabled: true);

    expect(find.text('网络异常'), findsNothing);
  });

  testWidgets('retry while still offline asks again', (tester) async {
    await pumpHost(tester);
    NetworkStatus.reportFailure();
    await tester.pumpAndSettle();
    expect(find.text('网络异常'), findsOneWidget);

    await tapRetry(tester);
    expect(find.text('网络异常'), findsOneWidget);

    online = true;
    await tapRetry(tester);
    expect(find.text('网络异常'), findsNothing);
  });

  testWidgets('retry once back online reloads only the current page', (
    tester,
  ) async {
    var below = 0;
    var current = 0;
    await pumpHost(tester, home: _RetryPage(onReload: () => below++));
    unawaited(
      navigatorOf(tester).push(
        MaterialPageRoute<void>(
          builder: (_) => _RetryPage(onReload: () => current++),
        ),
      ),
    );
    await tester.pumpAndSettle();

    NetworkStatus.reportFailure();
    await tester.pumpAndSettle();
    expect(find.text('网络异常'), findsOneWidget);

    online = true;
    await tapRetry(tester);

    expect(find.text('网络异常'), findsNothing);
    expect(current, 1);
    expect(below, 0);
  });

  testWidgets('pairing pages stay quiet', (tester) async {
    await pumpHost(tester);
    unawaited(
      navigatorOf(tester).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: AppRoutes.pairing),
          builder: (_) => const _PlainPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    NetworkStatus.reportFailure();
    await tester.pumpAndSettle();

    expect(find.text('网络异常'), findsNothing);
  });

  testWidgets('waits for another dialog to close before alerting', (
    tester,
  ) async {
    await pumpHost(tester);
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('page')),
        builder: (_) => const Dialog(child: Text('other dialog')),
      ),
    );
    await tester.pumpAndSettle();

    NetworkStatus.reportFailure();
    await tester.pumpAndSettle();
    expect(find.text('网络异常'), findsNothing);

    Navigator.of(tester.element(find.text('other dialog'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('网络异常'), findsOneWidget);
  });
}

class _PlainPage extends StatelessWidget {
  const _PlainPage();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('page')));
}

class _RetryPage extends StatefulWidget {
  const _RetryPage({required this.onReload});

  final VoidCallback onReload;

  @override
  State<_RetryPage> createState() => _RetryPageState();
}

class _RetryPageState extends State<_RetryPage>
    with NetworkRetryAware<_RetryPage> {
  @override
  Future<void> reloadForNetworkRetry() async => widget.onReload();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('page')));
}
