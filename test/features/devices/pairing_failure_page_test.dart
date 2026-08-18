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
    expect(find.text('返回选择设备'), findsOneWidget);
    expect(
      findAssetImage(AppAssets.pairingFailureIllustration),
      findsOneWidget,
    );
    final background = tester.widget<Image>(
      findAssetImage(AppAssets.accountBackground),
    );
    expect(background.fit, BoxFit.cover);
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

  testWidgets('return keeps the request and opens device selection', (
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
              if (settings.name == AppRoutes.deviceSelection) {
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
