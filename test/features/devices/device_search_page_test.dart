import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_search_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('device search page exposes the Figma content', (tester) async {
    await _pumpDeviceSearchPage(tester, const Size(375, 812));

    expect(find.text('搜索设备'), findsOneWidget);
    expect(find.text('搜索附近设备…'), findsOneWidget);
    // The planter provisions over 2.4G Wi-Fi only; no Bluetooth is involved.
    expect(find.text('请让设备进入配网状态，并确认手机连接的是2.4GHz Wi-Fi'), findsOneWidget);
    expect(find.text('小提示'), findsOneWidget);
    expect(find.text('若长时间未搜索到设备，请确认设备已开机\n请将手机靠近设备'), findsOneWidget);
    expect(
      findAssetImage(AppAssets.pairingDeviceSearchIllustration),
      findsOneWidget,
    );
    final background = tester.widget<Image>(
      findAssetImage(AppAssets.accountBackground),
    );
    expect(background.fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device search content remains usable at 320x568', (
    tester,
  ) async {
    await _pumpDeviceSearchPage(tester, const Size(320, 568));

    expect(find.byKey(const Key('device-search-content')), findsOneWidget);
    expect(find.text('搜索附近设备…'), findsOneWidget);
    expect(find.text('小提示'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the scan advances without Wi-Fi credentials', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    Object? selectionArguments = 'unset';

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceSearchPage(),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.deviceSelection) {
              selectionArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('device-selection-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('device-selection-target'), findsOneWidget);
    expect(selectionArguments, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovered devices open the selection page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    Object? selectionArguments;
    const request = PairingRequest(ssid: 'Home_2.4G', password: '12345678');

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceSearchPage(request: request),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.deviceSelection) {
              selectionArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('device-selection-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('device-selection-target'), findsOneWidget);
    expect(selectionArguments, same(request));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDeviceSearchPage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
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
        home: const DeviceSearchPage(),
      ),
    ),
  );
  await tester.pump();
}
