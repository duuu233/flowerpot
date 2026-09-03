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
  testWidgets('device selection page lists the planters the scan saw', (
    tester,
  ) async {
    await _pumpDeviceSelectionPage(tester, const Size(375, 812));

    expect(find.text('选择设备'), findsOneWidget);
    expect(find.text('请选择需要连接的设备'), findsOneWidget);
    // Real rows only: the SmartLife-* access point from the scan, not a
    // hardcoded YSplanter-01/02/03 list.
    expect(find.text('SmartLife-A1B2'), findsOneWidget);
    expect(find.text('TP-LINK_2.4G'), findsNothing);
    expect(find.text('连接'), findsOneWidget);
    expect(
      findAssetImage(AppAssets.pairingDeviceSelectionIllustration),
      findsOneWidget,
    );
    final background = tester.widget<Image>(
      findAssetImage(AppAssets.accountBackground),
    );
    // Fitted to width and top-aligned, matching the Figma frames.
    expect(background.fit, BoxFit.fitWidth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device selection content remains usable at 320x568', (
    tester,
  ) async {
    await _pumpDeviceSelectionPage(tester, const Size(320, 568));

    final device = find.text('SmartLife-A1B2');
    await tester.ensureVisible(device);
    await tester.pump();

    expect(device, findsOneWidget);
    expect(find.byKey(const Key('connect-device-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connect opens the Wi-Fi step with the picked hotspot', (
    tester,
  ) async {
    Object? pairingArguments;
    await _pumpDeviceSelectionPage(
      tester,
      const Size(375, 812),
      onPairingArguments: (value) => pairingArguments = value,
    );

    await tester.tap(find.byKey(const Key('connect-device-0')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-wifi-target'), findsOneWidget);
    final arguments = pairingArguments! as PairingArguments;
    expect(arguments.deviceName, 'SmartLife-A1B2');
    // AP provisioning has to name the hotspot the phone must join next.
    expect(arguments.hotspotSsid, 'SmartLife-A1B2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a retry carries the previous credentials to the Wi-Fi step', (
    tester,
  ) async {
    Object? pairingArguments;
    await _pumpDeviceSelectionPage(
      tester,
      const Size(375, 812),
      request: const PairingRequest(ssid: 'TP-LINK_2.4G', password: '87654321'),
      onPairingArguments: (value) => pairingArguments = value,
    );

    await tester.tap(find.byKey(const Key('connect-device-0')));
    await tester.pumpAndSettle();

    final arguments = pairingArguments! as PairingArguments;
    expect(arguments.deviceName, 'SmartLife-A1B2');
    expect(arguments.request?.ssid, 'TP-LINK_2.4G');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a SmartLift-style hotspot is recognized like SmartLife', (
    tester,
  ) async {
    // Reported from a real planter: the AP is called SmartLift-8987, which the
    // old `smartlife` prefix did not match. The SDK debug console listed it,
    // the pairing pages reported "no device".
    Object? pairingArguments;
    await _pumpDeviceSelectionPage(
      tester,
      const Size(375, 812),
      repository: _ScanRepository(
        const WifiScan(
          current: 'TP-LINK_2.4G',
          currentFrequency: 2437,
          networks: <WifiNetwork>[
            WifiNetwork(ssid: 'TP-LINK_2.4G', level: -46, frequency: 2437),
            WifiNetwork(ssid: 'SmartLift-8987', level: -58, frequency: 2412),
            WifiNetwork(ssid: 'TP-LINK_5G', level: -40, frequency: 5180),
          ],
        ),
      ),
      onPairingArguments: (value) => pairingArguments = value,
    );

    // Recognized, so it is the only row: the routers stay behind "show all".
    expect(find.text('请选择需要连接的设备'), findsOneWidget);
    expect(find.text('SmartLift-8987'), findsOneWidget);
    expect(find.text('TP-LINK_2.4G'), findsNothing);
    expect(find.byKey(const Key('device-selection-empty')), findsNothing);
    expect(
      find.byKey(const Key('device-selection-manual-notice')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('connect-device-0')));
    await tester.pumpAndSettle();

    final arguments = pairingArguments! as PairingArguments;
    expect(arguments.hotspotSsid, 'SmartLift-8987');
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing recognized falls back to the raw scan', (tester) async {
    Object? pairingArguments;
    await _pumpDeviceSelectionPage(
      tester,
      const Size(375, 812),
      repository: _ScanRepository(
        const WifiScan(
          current: 'TP-LINK_2.4G',
          currentFrequency: 2437,
          networks: <WifiNetwork>[
            WifiNetwork(ssid: 'TP-LINK_2.4G', level: -46, frequency: 2437),
            WifiNetwork(ssid: 'YS-8987', level: -58, frequency: 2412),
          ],
        ),
      ),
      onPairingArguments: (value) => pairingArguments = value,
    );

    // No SSID matched, so both networks are offered rather than reporting
    // "no device": the planter is in this list under a name we cannot guess.
    expect(find.text('请从附近的网络中选择设备'), findsOneWidget);
    expect(
      find.byKey(const Key('device-selection-manual-notice')),
      findsOneWidget,
    );
    expect(find.text('TP-LINK_2.4G'), findsOneWidget);
    expect(find.text('YS-8987'), findsOneWidget);
    expect(find.byKey(const Key('device-selection-empty')), findsNothing);
    // Everything is already on screen, so there is nothing left to reveal.
    expect(find.byKey(const Key('device-selection-show-all')), findsNothing);

    // The notice pushes the footer past the fold on a 812pt screen.
    final continueButton = find.byKey(const Key('device-selection-continue'));
    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(find.text('pairing-wifi-target'), findsOneWidget);
    // Nothing was picked, so no device name is invented for the next page.
    expect((pairingArguments! as PairingArguments).hotspotSsid, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rest of the scan is one tap away when a hotspot matched', (
    tester,
  ) async {
    await _pumpDeviceSelectionPage(tester, const Size(375, 812));

    expect(find.text('TP-LINK_2.4G'), findsNothing);

    final showAll = find.byKey(const Key('device-selection-show-all'));
    await tester.ensureVisible(showAll);
    await tester.pumpAndSettle();
    await tester.tap(showAll);
    await tester.pumpAndSettle();

    // The recognized hotspot keeps the top spot, the routers follow it.
    expect(find.text('SmartLife-A1B2'), findsOneWidget);
    expect(find.text('TP-LINK_2.4G'), findsOneWidget);
    expect(find.text('Xiaomi_2.4G'), findsOneWidget);
    expect(find.text('TP-LINK_5G'), findsNothing);
    expect(find.byKey(const Key('device-selection-show-all')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scan with nothing on 2.4 GHz leaves a rescan and a way on', (
    tester,
  ) async {
    Object? pairingArguments;
    await _pumpDeviceSelectionPage(
      tester,
      const Size(375, 812),
      repository: _ScanRepository(
        const WifiScan(
          current: 'TP-LINK_5G',
          currentFrequency: 5180,
          networks: <WifiNetwork>[
            WifiNetwork(ssid: 'TP-LINK_5G', level: -46, frequency: 5180),
          ],
        ),
      ),
      onPairingArguments: (value) => pairingArguments = value,
    );

    expect(find.text('未发现配网中的设备'), findsOneWidget);
    expect(find.byKey(const Key('device-selection-empty')), findsOneWidget);
    expect(find.byKey(const Key('connect-device-0')), findsNothing);
    expect(find.byKey(const Key('device-selection-rescan')), findsOneWidget);

    await tester.tap(find.byKey(const Key('device-selection-continue')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-wifi-target'), findsOneWidget);
    // Nothing was observed, so no device name is invented for the next page.
    expect((pairingArguments! as PairingArguments).hotspotSsid, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refused scan explains the platform reason', (tester) async {
    await _pumpDeviceSelectionPage(
      tester,
      const Size(375, 812),
      repository: _FailingScanRepository(),
    );

    expect(
      find.text('Android 9–12 扫描 Wi-Fi 需要打开系统定位开关。'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('device-selection-rescan')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<FlowerpotState> _pumpDeviceSelectionPage(
  WidgetTester tester,
  Size size, {
  PairingRequest? request,
  TuyaRepository? repository,
  ValueChanged<Object?>? onPairingArguments,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: repository ?? MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: DeviceSelectionPage(request: request),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.pairing) {
            onPairingArguments?.call(settings.arguments);
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
  // The page scans after its first frame when the state has no result yet.
  await tester.pumpAndSettle();
  return state;
}

class _ScanRepository extends MockTuyaRepository {
  _ScanRepository(this.scan) : super(latency: Duration.zero);

  final WifiScan scan;

  @override
  Future<WifiScan> scanWifi() async => scan;
}

class _FailingScanRepository extends MockTuyaRepository {
  _FailingScanRepository() : super(latency: Duration.zero);

  @override
  Future<WifiScan> scanWifi() async => throw const TuyaException(
    'location_disabled',
    '系统定位未开启；Android 9-12 扫描 Wi-Fi 必须打开定位开关',
  );
}
