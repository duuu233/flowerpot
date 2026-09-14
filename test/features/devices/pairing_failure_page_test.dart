import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/pairing_gate.dart';
import 'package:flowerpot/src/features/devices/presentation/device_search_page.dart';
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

  testWidgets('蓝牙失败：重试照原样走蓝牙，另给一条「改用热点方式」的退路', (tester) async {
    // 那条退路只在 AP 可用时存在；2026-09-11 起生产值是屏蔽的（见下一条用例）。
    PairingGate.apEnabled = true;
    addTearDown(PairingGate.reset);
    Object? pairingArguments;
    Object? searchArguments;
    await _pumpFailurePage(
      tester,
      const Size(375, 812),
      withRoutes: true,
      onPairingArguments: (value) => pairingArguments = value,
      onSelectionArguments: (value) => searchArguments = value,
      bleUuid: 'uuid-pot',
      deviceNetworks: const <DeviceWifiNetwork>[
        DeviceWifiNetwork(ssid: 'TP-LINK_2.4G', rssi: -48, sec: 3),
      ],
    );

    // 「重新配网」照原样再走一遍蓝牙那条。改之前只带 request，重试会掉进 AP 分支、
    // 又没有热点名，用户得到的是**另一个**失败。
    await tester.tap(find.byKey(const Key('retry-pairing-button')));
    await tester.pumpAndSettle();
    final retry = pairingArguments! as PairingArguments;
    expect(retry.bleUuid, 'uuid-pot');
    expect(retry.request?.password, '12345678');
    // 上一次问设备要到的列表带回去，不必再问一遍。
    expect(retry.deviceNetworks, hasLength(1));

    // 退路：回搜索页，并且**这一轮不再优选到蓝牙**（刚试过、没成）。
    await _pumpFailurePage(
      tester,
      const Size(375, 812),
      withRoutes: true,
      onSelectionArguments: (value) => searchArguments = value,
      bleUuid: 'uuid-pot',
    );
    expect(find.byKey(const Key('retry-over-hotspot-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-over-hotspot-button')));
    await tester.pumpAndSettle();
    final search = searchArguments! as DeviceSearchArguments;
    expect(search.preferHotspot, isTrue);
    expect(search.request?.ssid, 'Home_2.4G');
    expect(tester.takeException(), isNull);
  });

  testWidgets('走 AP 失败时不画「改用热点方式」——本来就是热点那条', (tester) async {
    PairingGate.apEnabled = true;
    addTearDown(PairingGate.reset);
    await _pumpFailurePage(tester, const Size(375, 812));

    expect(find.byKey(const Key('retry-over-hotspot-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AP 屏蔽后：蓝牙失败也不给「改用热点方式」', (tester) async {
    // 给了退路、用户一退就用 AP 配成了，这一轮要验的「设备支不支持蓝牙」
    // 就被盖掉了。所以屏蔽期间一律不给。
    await _pumpFailurePage(
      tester,
      const Size(375, 812),
      bleUuid: 'uuid-pot',
    );

    expect(find.byKey(const Key('retry-over-hotspot-button')), findsNothing);
    // 「重新配网」仍在，走的还是蓝牙那条。
    expect(find.byKey(const Key('retry-pairing-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 2026-09-14 产品：失败页上「等待设备回应超时……然后重试（142）/ 令牌(复用) 0ms · 失败 19131ms」
  // 这段不需要了。页面只留设计稿那一句；原因、失败码、各步耗时由 `diagnosticFor` 生成，
  // 配网页跳过来之前记进联调日志（见 pairing_page_test）。
  testWidgets('失败页只画一句笼统文案，不再画原因、失败码和各步耗时', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const PairingFailurePage(
          request: PairingRequest(ssid: 'Home_2.4G', password: '12345678'),
          code: '142',
          message: 'out of time｜令牌(复用) 0ms · 失败 19131ms',
        ),
      ),
    );
    await tester.pump();

    final subtitle = tester.widget<Text>(
      find.byKey(const Key('pairing-failure-subtitle')),
    );
    expect(subtitle.data, '设备未能成功连接到当前Wi-Fi网络');
    expect(find.textContaining('等待设备回应超时'), findsNothing);
    expect(find.textContaining('（142）'), findsNothing);
    expect(find.textContaining('19131ms'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('诊断文案：认不出的码照样带出来，涂鸦英文原文换成能照着做的话，各步耗时单独一行', () {
    // 2026-09-10 测试报回来的正是这一条：只看到「……，out of time」，没有任何码，
    // 于是判断不了失败在哪一步。码无论认不认得都带出来。
    final timeout = PairingFailurePage.diagnosticFor(
      code: '142',
      message: 'out of time｜令牌(复用) 0ms · 失败 19131ms',
    );
    expect(timeout, contains('等待设备回应超时'));
    expect(timeout, contains('（142）'));
    expect(timeout, contains('\n令牌(复用) 0ms · 失败 19131ms'));

    // 认不出的码、也没有可翻译的原文：原文照带。
    expect(
      PairingFailurePage.diagnosticFor(code: 'pair_failed', message: '配网超时'),
      '配网超时（pair_failed）',
    );
    // 认得的码换成一句能照着做的话；`｜` 之前那段原文不重复。
    final known = PairingFailurePage.diagnosticFor(
      code: 'hotspot_join_cancelled',
      message: '未连上 SmartLife-A1B2｜令牌 812ms',
    );
    expect(known, contains('手机没有连上设备热点'));
    expect(known, contains('（hotspot_join_cancelled）'));
    expect(known, contains('令牌 812ms'));
    expect(known, isNot(contains('未连上 SmartLife-A1B2')));
    // 什么都没有时返回空串（日志只记一句「配网失败 ✗」）。
    expect(PairingFailurePage.diagnosticFor(), '');
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

  // 2026-09-14 产品：「文字部分出现了折叠、滚动条的效果，不要这种效果，平铺到一个首屏
  // 里面，下面的小提示可以适当往下移」：没有可滚动的东西、按钮都在屏幕里、小提示贴着按钮上方。
  // （同日失败原因那段已不上屏，这里仍用长原文喂进来，确认它不会把版式撑坏。）
  for (final size in const <Size>[Size(375, 812), Size(320, 568)]) {
    testWidgets('一屏平铺，不出滚动条（${size.width.toInt()}x${size.height.toInt()}）', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const PairingFailurePage(
            request: PairingRequest(ssid: 'Home_2.4G', password: '12345678'),
            code: '207212',
            message: '设备连不上路由器｜令牌(复用) 3ms · 配网 118203ms · 失败 2ms',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);

      final subtitle = tester.widget<Text>(
        find.byKey(const Key('pairing-failure-subtitle')),
      );
      expect(subtitle.maxLines, isNull);
      // 失败原因那段 2026-09-14 起不上屏，只剩一句。
      expect(subtitle.data, '设备未能成功连接到当前Wi-Fi网络');

      final screen = Offset.zero & size;
      final retry = tester.getRect(find.byKey(const Key('retry-pairing-button')));
      final back = tester.getRect(
        find.byKey(const Key('return-device-selection-button')),
      );
      expect(screen.contains(back.bottomRight - const Offset(1, 1)), isTrue);
      // 小提示在按钮上方、失败原因下方。
      final tip = tester.getRect(find.text('小提示'));
      expect(tip.top, lessThan(retry.top));
      expect(
        tester.getRect(find.byKey(const Key('pairing-failure-subtitle'))).bottom,
        lessThanOrEqualTo(tip.top),
      );
    });
  }
}

Future<void> _pumpFailurePage(
  WidgetTester tester,
  Size size, {
  bool withRoutes = false,
  ValueChanged<Object?>? onSelectionArguments,
  ValueChanged<Object?>? onPairingArguments,
  String? bleUuid,
  List<DeviceWifiNetwork> deviceNetworks = const <DeviceWifiNetwork>[],
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: PairingFailurePage(
        request: const PairingRequest(
          ssid: 'Home_2.4G',
          password: '12345678',
        ),
        bleUuid: bleUuid,
        deviceNetworks: deviceNetworks,
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
