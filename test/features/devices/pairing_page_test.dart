import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/pairing_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('pairing page exposes the Figma content', (tester) async {
    await _pumpPairingPage(tester, const Size(375, 812));

    expect(find.text('连接Wi-Fi'), findsOneWidget);
    expect(find.text('请将设备连接到2.4GHz Wi-Fi网络'), findsOneWidget);
    expect(find.text('仅支持2.4GHz Wi-Fi网络'), findsOneWidget);
    expect(find.text('请确保设备连接的是稳定的2.4GHz网络'), findsOneWidget);
    expect(find.text('Wi-Fi名称'), findsOneWidget);
    // Prefilled from the scan, not from a placeholder: the network the phone is
    // on is the one the planter has to join. The password is never guessed.
    final ssidField = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssidField.controller?.text, 'TP-LINK_2.4G');
    expect(ssidField.readOnly, isFalse);
    final password = tester.widget<TextField>(
      find.byKey(const Key('pairing-password-field')),
    );
    expect(password.controller?.text, isEmpty);
    expect(password.obscureText, isTrue);
    expect(find.text('切换'), findsOneWidget);
    expect(find.text('Wi-Fi密码'), findsOneWidget);
    expect(find.text('连接过程中请保持设备靠近路由器'), findsOneWidget);
    // 只有 AP 一种配网方式，没有模式切换；一次点击走完。
    expect(find.byKey(const Key('pairing-mode-switch')), findsNothing);
    expect(find.text('开始配网'), findsOneWidget);
    expect(
      findAssetImage(AppAssets.pairingWifiSetupIllustration),
      findsOneWidget,
    );
    final background = tester.widget<Image>(
      findAssetImage(AppAssets.accountBackground),
    );
    // Fitted to width and top-aligned, matching the Figma frames.
    expect(background.fit, BoxFit.fitWidth);
    expect(
      tester.getSize(find.byKey(const Key('wifi-connection-illustration'))),
      const Size(339, 270),
    );
    final noticeCard = tester.widget<DecoratedBox>(
      find.byKey(const Key('wifi-notice-card')),
    );
    expect(
      (noticeCard.decoration as BoxDecoration).color,
      AppColors.surfaceTranslucent,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wifi sheet offers the 2.4G networks the phone can see', (
    tester,
  ) async {
    await _pumpPairingPage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('switch-wifi-button')));
    await tester.pumpAndSettle();
    expect(find.text('选择Wi-Fi'), findsOneWidget);
    expect(find.text('仅显示可用的2.4GHzWi-Fi网络'), findsOneWidget);
    expect(find.byKey(const Key('wifi-option-TP-LINK_2.4G')), findsOneWidget);
    expect(find.byKey(const Key('wifi-option-Xiaomi_2.4G')), findsOneWidget);
    // 5 GHz cannot carry provisioning, and the planter's own hotspot is not a
    // network it can be told to join.
    expect(find.byKey(const Key('wifi-option-TP-LINK_5G')), findsNothing);
    expect(find.byKey(const Key('wifi-option-SmartLife-A1B2')), findsNothing);

    await tester.tap(find.byKey(const Key('wifi-option-Xiaomi_2.4G')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('wifi-selection-confirm')));
    await tester.pumpAndSettle();

    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, 'Xiaomi_2.4G');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a platform without a network list keeps manual entry', (
    tester,
  ) async {
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      // iOS reports the current SSID and nothing else.
      repository: _ScanRepository(
        const WifiScan(current: 'Home_2.4G', networks: <WifiNetwork>[]),
      ),
    );

    await tester.tap(find.byKey(const Key('switch-wifi-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wifi-selection-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wifi-selection-cancel')));
    await tester.pumpAndSettle();

    // The band is unknown there, so the current network is still offered.
    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, 'Home_2.4G');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pairing content remains usable at 320x568', (tester) async {
    await _pumpPairingPage(tester, const Size(320, 568));

    final info = find.text('连接过程中请保持设备靠近路由器');
    await tester.ensureVisible(info);
    await tester.pump();

    expect(info, findsOneWidget);
    expect(find.byKey(const Key('start-pairing-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the connected device from the selection step is shown', (
    tester,
  ) async {
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      arguments: const PairingArguments(
        deviceName: 'SmartLife-A1B2',
        hotspotSsid: 'SmartLife-A1B2',
        request: PairingRequest(ssid: 'TP-LINK_2.4G', password: '87654321'),
      ),
    );

    expect(find.byKey(const Key('pairing-connected-device')), findsOneWidget);
    expect(find.text('已连接 SmartLife-A1B2'), findsOneWidget);
    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, 'TP-LINK_2.4G');
    expect(tester.takeException(), isNull);
  });

  testWidgets('AP provisioning runs token, hotspot and pairing in one tap', (
    tester,
  ) async {
    Object? successArguments;
    final repository = _TokenRepository();
    final state = await _pumpPairingPage(
      tester,
      const Size(375, 812),
      repository: repository,
      arguments: const PairingArguments(hotspotSsid: 'SmartLife-A1B2'),
      onSuccessArguments: (value) => successArguments = value,
    );

    // 一次点击走完三步，所以按钮直接就是「开始配网」，页面上只说明系统会弹框。
    expect(find.text('开始配网'), findsOneWidget);
    expect(find.byKey(const Key('pairing-hotspot-step')), findsOneWidget);
    expect(find.textContaining('「SmartLife-A1B2」'), findsOneWidget);

    await _enterPassword(tester);
    await tester.tap(find.byKey(const Key('start-pairing-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // 令牌只能在还连着路由器时取，所以它和配网必须在同一次操作里按序完成。
    expect(repository.tokenCalls, 1);
    expect(repository.pairCalls, 1);
    expect(repository.lastRequest?.mode, 'ap');
    expect(find.text('pairing-success-target'), findsOneWidget);
    expect(successArguments, 'vdevo17235508413621');
    // The token is single use; the bridge drops its cached copy on success.
    expect(state.activatorTokenReady, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a provisioning error opens the failure page', (tester) async {
    Object? failureArguments;
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      repository: _FailingRepository(),
      arguments: const PairingArguments(
        request: PairingRequest(
          ssid: 'TP-LINK_2.4G',
          password: 'wifi-password',
        ),
      ),
      onFailureArguments: (value) => failureArguments = value,
    );

    await tester.tap(find.byKey(const Key('start-pairing-button')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-failure-target'), findsOneWidget);
    final failure = failureArguments! as PairingFailureArguments;
    expect(failure.request?.ssid, 'TP-LINK_2.4G');
    // The SDK reason has to reach the failure screen, not just the request.
    expect(failure.code, 'pair_failed');
    expect(failure.message, '涂鸦-pair_failed 配网失败');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _enterPassword(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('pairing-password-field')),
    'wifi-password',
  );
  await tester.pump();
}

Future<FlowerpotState> _pumpPairingPage(
  WidgetTester tester,
  Size size, {
  PairingArguments? arguments,
  TuyaRepository? repository,
  ValueChanged<Object?>? onSuccessArguments,
  ValueChanged<Object?>? onFailureArguments,
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
        home: PairingPage(arguments: arguments),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.pairingSuccess) {
            onSuccessArguments?.call(settings.arguments);
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Center(child: Text('pairing-success-target')),
              ),
            );
          }
          if (settings.name == AppRoutes.pairingFailure) {
            onFailureArguments?.call(settings.arguments);
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Center(child: Text('pairing-failure-target')),
              ),
            );
          }
          return null;
        },
      ),
    ),
  );
  // The page reads the nearby networks after its first frame.
  await tester.pumpAndSettle();
  return state;
}

class _ScanRepository extends MockTuyaRepository {
  _ScanRepository(this.scan) : super(latency: Duration.zero);

  final WifiScan scan;

  @override
  Future<WifiScan> scanWifi() async => scan;
}

/// Counts the two provisioning calls so the AP order can be asserted.
class _TokenRepository extends MockTuyaRepository {
  _TokenRepository() : super(latency: Duration.zero);

  int tokenCalls = 0;
  int pairCalls = 0;
  PairingRequest? lastRequest;

  @override
  Future<void> prepareActivatorToken() async => tokenCalls++;

  @override
  Future<SmartPlanterDevice> pair(PairingRequest request) {
    pairCalls++;
    lastRequest = request;
    return super.pair(request);
  }
}

class _FailingRepository extends MockTuyaRepository {
  _FailingRepository() : super(latency: Duration.zero);

  @override
  Future<SmartPlanterDevice> pair(PairingRequest request) async {
    throw const TuyaException('pair_failed', '配网失败');
  }
}
