import '../../support/mock_tuya_repository.dart';
import 'dart:async';

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

  testWidgets('两个凭据输入框有聚焦态，且不再被压在 24px 里', (tester) async {
    await _pumpPairingPage(tester, const Size(375, 812));

    for (final key in const <Key>[
      Key('pairing-ssid-field'),
      Key('pairing-password-field'),
    ]) {
      final field = tester.widget<TextField>(find.byKey(key));
      final decoration = field.decoration!;
      // 收起焦点时下划线透明（静态版式与设计稿一致），聚焦时是品牌色细线。
      expect(decoration.enabledBorder, isA<UnderlineInputBorder>());
      expect(
        (decoration.enabledBorder! as UnderlineInputBorder).borderSide.color,
        Colors.transparent,
      );
      expect(
        (decoration.focusedBorder! as UnderlineInputBorder).borderSide.color,
        AppColors.brandPrimary,
      );
      expect(decoration.isDense, isTrue);
      // 高度交给输入框自己撑：外面不再套固定 24 的盒子。
      expect(tester.getSize(find.byKey(key)).height, greaterThan(24));
    }

    // 点进密码框后仍在同一张卡里，行高没有把内容挤掉。
    await tester.tap(find.byKey(const Key('pairing-password-field')));
    await tester.pumpAndSettle();

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

  testWidgets('手机没连 Wi-Fi 时输入框留空，让用户自己去切换', (tester) async {
    // 2026-09-10 产品口径：连着就直接带出来，没连就留空——不猜、也不填一个
    // 上一次留下的旧名字。
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      repository: _ScanRepository(const WifiScan(networks: <WifiNetwork>[])),
    );
    await tester.pump();

    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, isEmpty);
    expect(find.byKey(const Key('switch-wifi-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机挂在设备热点上时也按「没连」处理', (tester) async {
    // 上一次配网失败会把手机留在设备热点上。把那个名字填进去等于让设备去连
    // 它自己。
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      repository: _ScanRepository(
        const WifiScan(current: 'SmartLife-A1B2', networks: <WifiNetwork>[]),
      ),
    );
    await tester.pump();

    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, isEmpty);
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

  testWidgets('the page re-reads the current network instead of the cache', (
    tester,
  ) async {
    // 用户在搜索页扫描之后换了手机连接的 Wi-Fi：缓存里是旧网络，进页面必须
    // 重扫，显示的名称才和手机实际连的一致。
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      repository: _SwitchingScanRepository(),
      primeScan: true,
    );

    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, 'New_2.4G');
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning from the system settings refreshes the network', (
    tester,
  ) async {
    final repository = _SwitchingScanRepository();
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      repository: repository,
    );

    final before = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(before.controller?.text, 'Old_2.4G');

    // 去系统设置换网络再回来。
    await _resume(tester);

    final after = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(after.controller?.text, 'New_2.4G');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a network the user picked survives the refresh', (tester) async {
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      repository: _SwitchingScanRepository(),
    );

    await tester.enterText(
      find.byKey(const Key('pairing-ssid-field')),
      'Guest_2.4G',
    );
    await tester.pump();

    await _resume(tester);

    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, 'Guest_2.4G');
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

  testWidgets('这一页不再重复显示设备，只管选网络和输密码', (tester) async {
    // 2026-09-10 动线调整：设备是在**搜索页**上点「连接」确认的，热点那时也已经连上。
    // 这一页的任务只剩「选一个要让设备加入的 Wi-Fi 并输密码」，再画一遍
    // 「已选择设备 xxx」只是占地方。（原用例断言的就是那一行，随之作废。）
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      arguments: const PairingArguments(
        deviceName: 'SmartLife-A1B2',
        hotspotSsid: 'SmartLife-A1B2',
        request: PairingRequest(ssid: 'TP-LINK_2.4G', password: '87654321'),
      ),
    );

    expect(find.byKey(const Key('pairing-connected-device')), findsNothing);
    expect(find.textContaining('已选择设备'), findsNothing);
    // 重试带回来的凭据照常填好。
    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, 'TP-LINK_2.4G');
    // 进页面不会自己弹 Wi-Fi 列表：手机这时还连着路由器，SSID 正常带出来，
    // 要换网络点「切换」即可。
    expect(find.byKey(const Key('pairing-wifi-sheet')), findsNothing);
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

    // 一次点击走完三步，所以按钮直接就是「开始配网」。
    expect(find.text('开始配网'), findsOneWidget);
    // 2026-09-10 起「系统会弹框询问是否连接…」那一整段已删：系统弹框来了用户
    // 自然看得见，提前解释一遍只是占掉半屏。
    expect(find.byKey(const Key('pairing-hotspot-step')), findsNothing);
    expect(find.textContaining('不必到系统设置里手动连'), findsNothing);

    await _enterPassword(tester);
    await tester.tap(find.byKey(const Key('start-pairing-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // `pairViaHotspot` 第①步自己取令牌（搜索页的预取在这个只挂配网页的用例里没跑），
    // 所以这里应当恰好一次；配网本身照常一次。
    expect(repository.tokenCalls, 1);
    expect(repository.pairCalls, 1);
    expect(find.text('pairing-success-target'), findsOneWidget);
    expect(successArguments, 'vdevo17235508413621');
    // The token is single use; the bridge drops its cached copy on success.
    expect(state.activatorTokenReady, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('不走「手动连热点」那条路', (tester) async {
    // 连热点由搜索页那颗「连接」按钮完成（一次系统授权框），
    // `hotspot_manual_required` 那条引导路径整体下线。
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      arguments: const PairingArguments(hotspotSsid: 'SmartLife-A1B2'),
    );
    await tester.pump();

    expect(find.byKey(const Key('pairing-hotspot-manual')), findsNothing);
    expect(find.text('已连接热点，开始配网'), findsNothing);
    expect(find.text('开始配网'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refused hotspot join opens the failure page and releases', (
    tester,
  ) async {
    Object? failureArguments;
    final repository = _RefusedHotspotRepository();
    await _pumpPairingPage(
      tester,
      const Size(375, 812),
      repository: repository,
      arguments: const PairingArguments(
        hotspotSsid: 'SmartLife-A1B2',
        request: PairingRequest(ssid: 'TP-LINK_2.4G', password: 'secret'),
      ),
      onFailureArguments: (value) => failureArguments = value,
    );

    await tester.tap(find.byKey(const Key('start-pairing-button')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-failure-target'), findsOneWidget);
    final failure = failureArguments! as PairingFailureArguments;
    expect(failure.code, 'hotspot_join_cancelled');
    expect(repository.pairCalls, 0);
    // Whatever the system did with the request, the app lets go of it.
    expect(repository.leaveCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the page during pairing cancels it', (tester) async {
    final repository = _HangingRepository();
    final state = await _pumpPairingPage(
      tester,
      const Size(375, 812),
      repository: repository,
      arguments: const PairingArguments(
        hotspotSsid: 'SmartLife-A1B2',
        request: PairingRequest(ssid: 'TP-LINK_2.4G', password: 'secret'),
      ),
    );

    await tester.tap(find.byKey(const Key('start-pairing-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(state.busy, isTrue);
    expect(repository.pairCalls, 1);

    // The page goes away with the pairing still running: the activator must
    // not keep going for two minutes with the phone stuck on the hotspot.
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(theme: buildAppTheme(), home: const SizedBox()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(repository.cancelCalls, 1);
    expect(state.busy, isFalse);
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
    // 2026-09-10 起文案不带来源前缀（`涂鸦-` / `接口-` / `APP-`），直接是原文。
    expect(failure.message, '配网失败');
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
  bool primeScan = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: repository ?? MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  // 搜索页/选择页会在进本页之前扫一次，缓存里留下的是那一刻的网络。
  if (primeScan) await state.probeWifi();
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

/// 走一遍完整的前后台切换顺序，回到 resumed。
Future<void> _resume(WidgetTester tester) async {
  for (final state in const <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

/// 第一次扫描给旧网络，之后都给新网络：模拟用户中途换了手机连的 Wi-Fi。
class _SwitchingScanRepository extends MockTuyaRepository {
  _SwitchingScanRepository() : super(latency: Duration.zero);

  int scans = 0;

  @override
  Future<WifiScan> scanWifi({bool refresh = true}) async {
    scans++;
    final ssid = scans <= 1 ? 'Old_2.4G' : 'New_2.4G';
    return WifiScan(
      current: ssid,
      currentFrequency: 2437,
      networks: <WifiNetwork>[
        WifiNetwork(ssid: ssid, level: -46, frequency: 2437),
      ],
    );
  }
}

class _ScanRepository extends MockTuyaRepository {
  _ScanRepository(this.scan) : super(latency: Duration.zero);

  final WifiScan scan;

  @override
  Future<WifiScan> scanWifi({bool refresh = true}) async => scan;
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

/// The iOS / Android 9 shape: the app cannot join the hotspot itself, and the
/// phone is still on the router when the first attempt is made.
class _RefusedHotspotRepository extends _TokenRepository {
  int leaveCalls = 0;

  @override
  Future<bool> joinDeviceHotspot({String? ssid, String? prefix}) async {
    throw const TuyaException('hotspot_join_cancelled', '未连上热点');
  }

  @override
  Future<void> leaveDeviceHotspot() async => leaveCalls++;
}

/// A bridge whose pairing only ends when it is cancelled, like the real one
/// while the activator is waiting on the device.
class _HangingRepository extends _TokenRepository {
  int cancelCalls = 0;
  Completer<SmartPlanterDevice>? _pending;

  @override
  Future<SmartPlanterDevice> pair(PairingRequest request) {
    pairCalls++;
    final completer = Completer<SmartPlanterDevice>();
    _pending = completer;
    return completer.future;
  }

  @override
  Future<void> cancelPairing() async {
    cancelCalls++;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const TuyaException('pair_cancelled', '配网已被中止'),
      );
    }
  }
}
