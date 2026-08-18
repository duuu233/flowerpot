import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_selection_page.dart';
import 'package:flowerpot/src/features/devices/presentation/pairing_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('device selection page exposes the Figma content', (
    tester,
  ) async {
    await _pumpDeviceSelectionPage(tester, const Size(375, 812));

    expect(find.text('选择设备'), findsOneWidget);
    expect(find.text('请选择需要连接的设备'), findsOneWidget);
    expect(find.text('模拟设备列表'), findsOneWidget);
    expect(find.text('YSplanter-01'), findsOneWidget);
    expect(find.text('YSplanter-02'), findsOneWidget);
    expect(find.text('YSplanter-03'), findsOneWidget);
    expect(find.text('连接'), findsNWidgets(3));
    expect(
      findAssetImage(AppAssets.pairingDeviceSelectionIllustration),
      findsOneWidget,
    );
    final background = tester.widget<Image>(
      findAssetImage(AppAssets.accountBackground),
    );
    expect(background.fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device selection content remains usable at 320x568', (
    tester,
  ) async {
    await _pumpDeviceSelectionPage(tester, const Size(320, 568));

    final lastDevice = find.text('YSplanter-03');
    await tester.ensureVisible(lastDevice);
    await tester.pump();

    expect(lastDevice, findsOneWidget);
    expect(find.byKey(const Key('connect-device-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connect opens the Wi-Fi step with the picked device', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    Object? pairingArguments;

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceSelectionPage(),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.pairing) {
              pairingArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('pairing-wifi-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('connect-device-0')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('pairing-wifi-target'), findsOneWidget);
    final arguments = pairingArguments! as PairingArguments;
    expect(arguments.deviceName, 'YSplanter-01');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a retry carries the previous credentials to the Wi-Fi step', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    Object? pairingArguments;

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceSelectionPage(
            request: PairingRequest(ssid: 'TP-LINK_2.4G', password: '87654321'),
          ),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.pairing) {
              pairingArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('pairing-wifi-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('connect-device-1')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    final arguments = pairingArguments! as PairingArguments;
    expect(arguments.deviceName, 'YSplanter-02');
    expect(arguments.request?.ssid, 'TP-LINK_2.4G');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDeviceSelectionPage(WidgetTester tester, Size size) async {
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
        home: const DeviceSelectionPage(),
      ),
    ),
  );
  await tester.pump();
}
