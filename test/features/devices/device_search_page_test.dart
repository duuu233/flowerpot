import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_search_page.dart';
import 'package:flowerpot/src/features/devices/presentation/pairing_page.dart';
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
    expect(find.text('搜索附近设备...'), findsOneWidget);
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
    // Fitted to width and top-aligned, matching the Figma frames.
    expect(background.fit, BoxFit.fitWidth);
    // Lets the scan started after the first frame finish.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('device search content remains usable at 320x568', (
    tester,
  ) async {
    await _pumpDeviceSearchPage(tester, const Size(320, 568));

    expect(find.byKey(const Key('device-search-content')), findsOneWidget);
    expect(find.text('搜索附近设备...'), findsOneWidget);
    expect(find.text('小提示'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a planter hotspot in the scan opens the selection page', (
    tester,
  ) async {
    Object? selectionArguments = 'unset';
    final state = await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      onSelectionArguments: (value) => selectionArguments = value,
    );
    await tester.pumpAndSettle();

    // The mock scan carries a SmartLife-* access point, which is the only real
    // evidence the app has that a planter is waiting to be provisioned.
    expect(state.wifiScan?.deviceHotspots, hasLength(1));
    expect(find.text('device-selection-target'), findsOneWidget);
    expect(selectionArguments, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a retry carries the credentials to the selection step', (
    tester,
  ) async {
    Object? selectionArguments;
    const request = PairingRequest(ssid: 'Home_2.4G', password: '12345678');
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      request: request,
      onSelectionArguments: (value) => selectionArguments = value,
    );
    await tester.pumpAndSettle();

    expect(find.text('device-selection-target'), findsOneWidget);
    expect(selectionArguments, same(request));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scan without a hotspot stays put and offers a way on', (
    tester,
  ) async {
    Object? pairingArguments;
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: _ScanRepository(
        const WifiScan(
          current: 'TP-LINK_5G',
          currentFrequency: 5180,
          networks: <WifiNetwork>[
            WifiNetwork(ssid: 'TP-LINK_5G', level: -52, frequency: 5180),
          ],
        ),
      ),
      onPairingArguments: (value) => pairingArguments = value,
    );
    await tester.pumpAndSettle();

    expect(find.text('device-selection-target'), findsNothing);
    expect(find.text('未发现配网中的设备'), findsOneWidget);
    expect(
      find.textContaining('手机当前连接：TP-LINK_5G（5G，配网需要 2.4G）'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('device-search-rescan')), findsOneWidget);

    // Provisioning still has to be reachable: the scan is evidence, not a gate.
    await tester.tap(find.byKey(const Key('device-search-continue')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-wifi-target'), findsOneWidget);
    expect((pairingArguments! as PairingArguments).request, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a platform that cannot enumerate networks is not "no device"', (
    tester,
  ) async {
    // iOS answers with the current SSID and an empty list.
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: _ScanRepository(
        const WifiScan(current: 'Home_2.4G', networks: <WifiNetwork>[]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法列出附近设备'), findsOneWidget);
    expect(find.byKey(const Key('device-search-continue')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refused scan explains the platform reason', (tester) async {
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: _FailingScanRepository(),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法扫描附近设备'), findsOneWidget);
    expect(find.text('请先打开手机 Wi-Fi 再重新扫描。'), findsOneWidget);
    expect(find.byKey(const Key('device-search-rescan')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<FlowerpotState> _pumpDeviceSearchPage(
  WidgetTester tester,
  Size size, {
  PairingRequest? request,
  TuyaRepository? repository,
  ValueChanged<Object?>? onSelectionArguments,
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
        home: DeviceSearchPage(request: request),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.deviceSelection) {
            onSelectionArguments?.call(settings.arguments);
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Center(child: Text('device-selection-target')),
              ),
            );
          }
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
  // One frame only: the scan runs after the first frame, so this is the
  // "searching" state every caller starts from.
  await tester.pump();
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
  Future<WifiScan> scanWifi() async =>
      throw const TuyaException('wifi_disabled', '手机 Wi-Fi 未开启，无法扫描');
}
