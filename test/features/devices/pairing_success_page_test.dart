import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/pairing_success_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('pairing success page exposes the Figma content', (tester) async {
    await _pumpSuccessPage(tester, const Size(375, 812));

    expect(find.text('连接设备'), findsOneWidget);
    expect(find.text('连接成功'), findsOneWidget);
    expect(find.text('设备已成功连接，可以开始添加植物了'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('添加植物'), findsNothing);
    expect(find.text('返回首页'), findsNothing);
    expect(find.byKey(const Key('success-add-plant-button')), findsNothing);
    expect(
      findAssetImage(AppAssets.pairingSuccessIllustration),
      findsOneWidget,
    );
    final background = tester.widget<Image>(
      findAssetImage(AppAssets.accountBackground),
    );
    // Fitted to width and top-aligned, matching the Figma frames.
    expect(background.fit, BoxFit.fitWidth);
    final title = tester.widget<Text>(
      find.byKey(const Key('pairing-success-title')),
    );
    expect(title.style?.fontSize, 24);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the finish action remains usable at 320x568', (tester) async {
    await _pumpSuccessPage(tester, const Size(320, 568));

    final homeButton = find.byKey(const Key('success-return-home-button'));
    await tester.ensureVisible(homeButton);
    await tester.pump();

    expect(homeButton, findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finishing opens the app shell', (tester) async {
    await _pumpSuccessPage(tester, const Size(375, 812), withRoutes: true);

    await tester.tap(find.byKey(const Key('success-return-home-button')));
    await tester.pumpAndSettle();

    expect(find.text('home-target'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSuccessPage(
  WidgetTester tester,
  Size size, {
  bool withRoutes = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: const PairingSuccessPage(deviceId: 'planter-demo-01'),
      onGenerateRoute: withRoutes
          ? (settings) {
              if (settings.name == AppRoutes.shell) {
                return MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: Center(child: Text('home-target'))),
                );
              }
              return null;
            }
          : null,
    ),
  );
  await tester.pump();
}
