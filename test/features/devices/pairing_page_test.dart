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
    // Nothing is prefilled: a placeholder SSID/password would be sent to the
    // SDK as-is on a real pairing attempt.
    expect(find.text('输入 2.4G 名称'), findsOneWidget);
    final ssidField = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssidField.controller?.text, isEmpty);
    expect(ssidField.readOnly, isFalse);
    expect(find.text('切换'), findsOneWidget);
    expect(find.text('Wi-Fi密码'), findsOneWidget);
    expect(find.text('连接过程中请保持设备靠近路由器'), findsOneWidget);
    expect(find.text('开始配网'), findsOneWidget);
    // Debug builds expose the provisioning mode and default to AP.
    expect(find.text('真实 SDK · AP 配网'), findsOneWidget);
    expect(find.byKey(const Key('pairing-mode-switch')), findsOneWidget);
    expect(
      findAssetImage(AppAssets.pairingWifiSetupIllustration),
      findsOneWidget,
    );
    final background = tester.widget<Image>(
      findAssetImage(AppAssets.accountBackground),
    );
    expect(background.fit, BoxFit.cover);
    expect(
      tester.getSize(find.byKey(const Key('wifi-connection-illustration'))),
      const Size(335, 270),
    );
    final noticeCard = tester.widget<DecoratedBox>(
      find.byKey(const Key('wifi-notice-card')),
    );
    expect(
      (noticeCard.decoration as BoxDecoration).color,
      AppColors.surfaceTranslucent,
    );

    final password = tester.widget<TextField>(
      find.byKey(const Key('pairing-password-field')),
    );
    expect(password.obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wifi selection sheet updates the network name', (tester) async {
    await _pumpPairingPage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('switch-wifi-button')));
    await tester.pumpAndSettle();
    expect(find.text('选择Wi-Fi'), findsOneWidget);
    expect(find.text('仅显示可用的2.4GHzWi-Fi网络'), findsOneWidget);
    expect(find.byKey(const Key('wifi-option-Home_2.4G')), findsOneWidget);
    expect(find.byKey(const Key('wifi-option-TP-LINK_2.4G')), findsOneWidget);
    expect(find.byKey(const Key('wifi-option-Xiaomi_2.4G')), findsOneWidget);
    expect(find.text('模拟网络列表'), findsOneWidget);
    // Nothing is selected until the user picks one, because the field starts
    // empty rather than on a placeholder network.
    expect(find.byKey(const Key('wifi-selected-check')), findsNothing);

    await tester.tap(find.byKey(const Key('wifi-option-TP-LINK_2.4G')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('wifi-selection-confirm')));
    await tester.pumpAndSettle();

    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, 'TP-LINK_2.4G');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pairing content remains usable at 320x568', (tester) async {
    await _pumpPairingPage(tester, const Size(320, 568));

    final info = find.text('连接过程中请保持设备靠近路由器');
    await tester.ensureVisible(info);
    await tester.pump();

    expect(info, findsOneWidget);
    expect(find.text('开始配网'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the connected device from the selection step is shown', (
    tester,
  ) async {
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      arguments: const PairingArguments(
        deviceName: 'YSplanter-01',
        request: PairingRequest(ssid: 'TP-LINK_2.4G', password: '87654321'),
      ),
    );

    expect(find.byKey(const Key('pairing-connected-device')), findsOneWidget);
    expect(find.text('已连接 YSplanter-01'), findsOneWidget);
    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, 'TP-LINK_2.4G');
    expect(tester.takeException(), isNull);
  });

  testWidgets('start pairing binds the device and opens the success page', (
    tester,
  ) async {
    Object? successArguments;
    final state = await _pumpPairingPage(
      tester,
      const Size(375, 812),
      onSuccessArguments: (value) => successArguments = value,
    );

    await _enterCredentials(tester);
    await tester.tap(find.byKey(const Key('start-pairing-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('pairing-success-target'), findsOneWidget);
    expect(successArguments, 'planter-demo-01');
    expect(state.devices, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a provisioning error opens the failure page', (tester) async {
    Object? failureArguments;
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      repository: _FailingRepository(),
      onFailureArguments: (value) => failureArguments = value,
    );

    await _enterCredentials(tester);
    await tester.tap(find.byKey(const Key('start-pairing-button')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-failure-target'), findsOneWidget);
    final failure = failureArguments! as PairingFailureArguments;
    expect(failure.request?.ssid, 'TP-LINK_2.4G');
    // The SDK reason has to reach the failure screen, not just the request.
    expect(failure.code, 'pair_failed');
    expect(failure.message, '配网失败');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _enterCredentials(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('pairing-ssid-field')),
    'TP-LINK_2.4G',
  );
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
  await tester.pump();
  return state;
}

class _FailingRepository extends MockTuyaRepository {
  _FailingRepository() : super(latency: Duration.zero);

  @override
  Future<SmartPlanterDevice> pair(PairingRequest request) async {
    throw const TuyaException('pair_failed', '配网失败');
  }
}
