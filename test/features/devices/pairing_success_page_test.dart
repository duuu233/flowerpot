import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/pairing_success_page.dart';
import 'package:flowerpot/src/features/devices/presentation/plant_picker_page.dart';
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
    expect(find.text('添加植物'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);
    expect(
      findAssetImage(AppAssets.pairingSuccessIllustration),
      findsOneWidget,
    );
    final background = tester.widget<Image>(
      findAssetImage(AppAssets.accountBackground),
    );
    expect(background.fit, BoxFit.cover);
    final title = tester.widget<Text>(
      find.byKey(const Key('pairing-success-title')),
    );
    expect(title.style?.fontSize, 24);
    expect(tester.takeException(), isNull);
  });

  testWidgets('success actions remain usable at 320x568', (tester) async {
    await _pumpSuccessPage(tester, const Size(320, 568));

    final homeButton = find.byKey(const Key('success-return-home-button'));
    await tester.ensureVisible(homeButton);
    await tester.pump();

    expect(find.byKey(const Key('success-add-plant-button')), findsOneWidget);
    expect(homeButton, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add plant opens the picker with the connected device', (
    tester,
  ) async {
    Object? pickerArguments;
    await _pumpSuccessPage(
      tester,
      const Size(375, 812),
      withRoutes: true,
      onPickerArguments: (value) => pickerArguments = value,
    );

    await tester.tap(find.byKey(const Key('success-add-plant-button')));
    await tester.pumpAndSettle();

    expect(find.text('plant-picker-target'), findsOneWidget);
    final arguments = pickerArguments! as PlantPickerArguments;
    expect(arguments.deviceId, 'planter-demo-01');
    expect(arguments.mode, PlantPickerMode.add);
    expect(tester.takeException(), isNull);
  });

  testWidgets('return home opens the app shell', (tester) async {
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
  ValueChanged<Object?>? onPickerArguments,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: const PairingSuccessPage(deviceId: 'planter-demo-01'),
      onGenerateRoute: withRoutes
          ? (settings) {
              if (settings.name == AppRoutes.plantPicker) {
                onPickerArguments?.call(settings.arguments);
                return MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('plant-picker-target')),
                  ),
                );
              }
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
