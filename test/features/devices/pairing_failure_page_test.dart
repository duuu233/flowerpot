import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/pairing_failure_page.dart';
import 'package:flowerpot/src/features/devices/presentation/pairing_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('pairing failure page exposes the Figma content', (tester) async {
    await _pumpFailurePage(tester, const Size(375, 812));

    expect(find.text('连接设备'), findsOneWidget);
    expect(find.text('配网失败，请重试'), findsOneWidget);
    expect(find.text('设备未能成功连接到当前Wi-Fi网络'), findsOneWidget);
    expect(find.text('小提示'), findsOneWidget);
    expect(find.text('重新配网'), findsOneWidget);
    expect(find.text('返回搜索设备'), findsOneWidget);
    expect(
      findAssetImage(AppAssets.pairingFailureIllustration),
      findsOneWidget,
    );
    final background = tester.widget<Image>(
      findAssetImage(AppAssets.accountBackground),
    );
    // Fitted to width and top-aligned, matching the Figma frames.
    expect(background.fit, BoxFit.fitWidth);
    final title = tester.widget<Text>(
      find.byKey(const Key('pairing-failure-title')),
    );
    expect(title.style?.fontSize, 24);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure actions remain usable at 320x568', (tester) async {
    await _pumpFailurePage(tester, const Size(320, 568));

    final returnButton = find.byKey(
      const Key('return-device-selection-button'),
    );
    await tester.ensureVisible(returnButton);
    await tester.pump();

    expect(find.byKey(const Key('retry-pairing-button')), findsOneWidget);
    expect(returnButton, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry returns to Wi-Fi pairing with the previous attempt', (
    tester,
  ) async {
    Object? pairingArguments;
    await _pumpFailurePage(
      tester,
      const Size(375, 812),
      withRoutes: true,
      onPairingArguments: (value) => pairingArguments = value,
    );

    await tester.tap(find.byKey(const Key('retry-pairing-button')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-target'), findsOneWidget);
    // The Wi-Fi page starts blank now, so the retry has to carry the
    // credentials back or they are lost on every failure.
    expect(pairingArguments, isA<PairingArguments>());
    final request = (pairingArguments! as PairingArguments).request;
    expect(request?.ssid, 'Home_2.4G');
    expect(request?.password, '12345678');
    expect(tester.takeException(), isNull);
  });

  testWidgets('debug builds show the SDK failure code', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const PairingFailurePage(
          request: PairingRequest(ssid: 'Home_2.4G', password: '12345678'),
          code: 'pair_failed',
          message: '配网超时',
        ),
      ),
    );
    await tester.pump();

    final subtitle = tester.widget<Text>(
      find.byKey(const Key('pairing-failure-subtitle')),
    );
    // An unknown code shows the state's message as it came: it already carries
    // the source tag and the per-step timings, so nothing is prepended.
    expect(subtitle.data, contains('配网超时'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('认不出的失败码也要显示出来，涂鸦的英文原文换成能照着做的话', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const PairingFailurePage(
          request: PairingRequest(ssid: 'Home_2.4G', password: '12345678'),
          code: 'pair_failed',
          message: 'out of time',
        ),
      ),
    );
    await tester.pump();

    final subtitle = tester.widget<Text>(
      find.byKey(const Key('pairing-failure-subtitle')),
    );
    // 2026-09-10 测试报回来的正是这一条：只看到「……，out of time」，没有任何码，
    // 于是判断不了失败在哪一步。码现在无论认不认得都带出来。
    expect(subtitle.data, contains('（pair_failed）'));
    expect(subtitle.data, contains('等待设备回应超时'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a known failure code is explained in plain words', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const PairingFailurePage(
          request: PairingRequest(ssid: 'Home_2.4G', password: '12345678'),
          code: 'hotspot_join_cancelled',
          message: '未连上 SmartLife-A1B2｜令牌 812ms',
        ),
      ),
    );
    await tester.pump();

    final subtitle = tester.widget<Text>(
      find.byKey(const Key('pairing-failure-subtitle')),
    );
    // The raw code stays visible for diagnosis, after the actionable line.
    expect(subtitle.data, contains('手机没有连上设备热点'));
    expect(subtitle.data, contains('（hotspot_join_cancelled）'));
    // 2026-09-10 起**各步耗时单独一行保留**（原来是断言它被藏掉）。失败码只说
    // 「哪一类」，耗时才说「死在哪一步」——比如「连热点」那一段有耗时就说明热点
    // 确实连上了、失败在之后，这是真机排查唯一能拿到的线索。
    expect(subtitle.data, contains('令牌 812ms'));
    // 但 `｜` 之前的那段原文仍然不重复显示：提示语已经把它说清楚了。
    expect(subtitle.data, isNot(contains('未连上 SmartLife-A1B2')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('return keeps the request and reopens the search page', (
    tester,
  ) async {
    Object? selectionArguments;
    await _pumpFailurePage(
      tester,
      const Size(375, 812),
      withRoutes: true,
      onSelectionArguments: (value) => selectionArguments = value,
    );

    await tester.tap(find.byKey(const Key('return-device-selection-button')));
    await tester.pumpAndSettle();

    expect(find.text('selection-target'), findsOneWidget);
    expect(selectionArguments, isA<PairingRequest>());
    expect((selectionArguments! as PairingRequest).ssid, 'Home_2.4G');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFailurePage(
  WidgetTester tester,
  Size size, {
  bool withRoutes = false,
  ValueChanged<Object?>? onSelectionArguments,
  ValueChanged<Object?>? onPairingArguments,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: const PairingFailurePage(
        request: PairingRequest(ssid: 'Home_2.4G', password: '12345678'),
      ),
      onGenerateRoute: withRoutes
          ? (settings) {
              if (settings.name == AppRoutes.pairing) {
                onPairingArguments?.call(settings.arguments);
                return MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('pairing-target')),
                  ),
                );
              }
              if (settings.name == AppRoutes.deviceSearch) {
                onSelectionArguments?.call(settings.arguments);
                return MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('selection-target')),
                  ),
                );
              }
              return null;
            }
          : null,
    ),
  );
  await tester.pump();
}
