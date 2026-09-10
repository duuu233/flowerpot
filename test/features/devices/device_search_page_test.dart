import '../../support/mock_tuya_repository.dart';
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

/// 搜索页上「已发现设备」列表的 key，与页面里的 `_FoundDeviceList.listKey` 同值。
abstract final class _FoundListKey {
  static const key = Key('device-search-found-list');
}

void main() {
  testWidgets('device search page exposes the Figma content', (tester) async {
    await _pumpDeviceSearchPage(tester, const Size(375, 812));

    expect(find.text('搜索设备'), findsOneWidget);
    expect(find.text('搜索附近设备...'), findsOneWidget);
    // The planter provisions over 2.4G Wi-Fi only; no Bluetooth is involved.
    expect(find.text('请确认设备已开机，并确认手机连接的是 2.4GHz Wi-Fi'), findsOneWidget);
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

  testWidgets('扫到的设备直接列在页面下方，不再跳页', (tester) async {
    Object? pairingArguments = 'unset';
    final state = await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      onPairingArguments: (value) => pairingArguments = value,
    );
    await tester.pump();
    await tester.pump();

    // The mock scan carries a SmartLife-* access point, which is the only real
    // evidence the app has that a planter is waiting to be provisioned.
    expect(state.wifiScan?.deviceHotspots, hasLength(1));
    // 列在页面上，而不是把用户带走。
    expect(find.byKey(_FoundListKey.key), findsOneWidget);
    expect(find.text('SmartLife-A1B2'), findsOneWidget);
    expect(find.text('发现 1 台设备'), findsOneWidget);
    expect(pairingArguments, 'unset');
    expect(tester.takeException(), isNull);
  });

  testWidgets('点中列表里的设备，带着它的热点名进连接 Wi-Fi', (tester) async {
    Object? pairingArguments;
    const request = PairingRequest(ssid: 'Home_2.4G', password: '12345678');
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      request: request,
      onPairingArguments: (value) => pairingArguments = value,
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('device-search-found-0')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-wifi-target'), findsOneWidget);
    final arguments = pairingArguments! as PairingArguments;
    expect(arguments.hotspotSsid, 'SmartLife-A1B2');
    expect(arguments.request, same(request));
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
    await _runOutSearchWindow(tester);

    expect(find.text('未发现设备'), findsOneWidget);
    // 扫描台数、手机当前连接、手动选择这三段都已下线。
    expect(find.textContaining('扫描到'), findsNothing);
    expect(find.textContaining('手机当前连接'), findsNothing);
    expect(find.byKey(const Key('device-search-manual-pick')), findsNothing);
    expect(find.byKey(const Key('device-search-rescan')), findsOneWidget);

    // 「设备已在配网状态，继续」2026-09-10 已按产品要求删除。
    expect(find.byKey(const Key('device-search-continue')), findsNothing);
    expect(find.text('设备已在配网状态，继续'), findsNothing);
    expect(pairingArguments, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('认不出热点时不再提供手动选择，只剩重新扫描和继续', (tester) async {
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: _ScanRepository(
        const WifiScan(
          current: 'TP-LINK_2.4G',
          currentFrequency: 2437,
          networks: <WifiNetwork>[
            WifiNetwork(ssid: 'TP-LINK_2.4G', level: -46, frequency: 2437),
          ],
        ),
      ),
    );
    await _runOutSearchWindow(tester);

    expect(find.text('未发现设备'), findsOneWidget);
    expect(find.textContaining('手动选择'), findsNothing);
    expect(find.byKey(const Key('device-search-manual-pick')), findsNothing);
    expect(find.byKey(const Key('device-search-rescan')), findsOneWidget);
    expect(find.byKey(const Key('device-search-continue')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窗口内会按节奏反复扫描，中途出现的设备热点照样会列出来', (tester) async {
    // 用户长按设备让它进配网时，第一次扫描往往还看不到热点。窗口没走完就一直
    // 重扫，热点一出现就列在下面，不用用户自己点「重新扫描」。
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: _LateHotspotRepository(silentScans: 2),
    );
    // 头两次是 3 秒一次的快扫，第三次要等 30 秒的慢节奏——这就是系统配额
    // （Android 每 2 分钟 4 次）逼出来的间隔，扫得更密只会拿回旧缓存。
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(_FoundListKey.key), findsNothing);
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(find.byKey(_FoundListKey.key), findsOneWidget);
    expect(find.text('SmartLife-A1B2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('被系统限流时不下「未发现设备」的结论', (tester) async {
    // Android 9 起前台应用每 2 分钟只允许 4 次 startScan，超了就返回上一次的缓存。
    // 「先进搜索页、再给设备上电」时缓存里当然没有那台设备——把它当成「附近没有
    // 设备」是撒谎，这正是 2026-09-08 那版每 2 秒重扫留下的坑。
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: _ScanRepository(
        const WifiScan(
          current: 'TP-LINK_2.4G',
          currentFrequency: 2437,
          throttled: true,
          networks: <WifiNetwork>[
            WifiNetwork(ssid: 'TP-LINK_2.4G', level: -46, frequency: 2437),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // 搜索中就明说在等配额，不装作还在查。
    expect(find.textContaining('系统限制了 Wi-Fi 扫描频率'), findsOneWidget);

    await _runOutSearchWindow(tester);

    expect(find.text('未发现设备'), findsNothing);
    expect(find.text('无法确认附近设备'), findsOneWidget);
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
    await _runOutSearchWindow(tester);

    expect(find.text('无法列出附近设备'), findsOneWidget);
    expect(find.byKey(const Key('device-search-continue')), findsNothing);
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

/// 跑满一整轮搜索窗口：窗口内页面一直显示「搜索中」，走完才给出结论。
Future<void> _runOutSearchWindow(WidgetTester tester) async {
  await tester.pump(DeviceSearchPage.searchWindow + const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<FlowerpotState> _pumpDeviceSearchPage(
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
        home: DeviceSearchPage(request: request),
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

/// 前 [silentScans] 次扫描只看得到路由器，之后设备热点才出现。
class _LateHotspotRepository extends MockTuyaRepository {
  _LateHotspotRepository({required this.silentScans})
    : super(latency: Duration.zero);

  final int silentScans;
  int _calls = 0;

  @override
  Future<WifiScan> scanWifi() async {
    final seen = _calls++;
    if (seen < silentScans) {
      return const WifiScan(
        current: 'TP-LINK_2.4G',
        currentFrequency: 2437,
        networks: <WifiNetwork>[
          WifiNetwork(ssid: 'TP-LINK_2.4G', level: -46, frequency: 2437),
        ],
      );
    }
    return const WifiScan(
      current: 'TP-LINK_2.4G',
      currentFrequency: 2437,
      networks: <WifiNetwork>[
        WifiNetwork(ssid: 'TP-LINK_2.4G', level: -46, frequency: 2437),
        WifiNetwork(ssid: 'SmartLife-A1B2', level: -58, frequency: 2412),
      ],
    );
  }
}

class _FailingScanRepository extends MockTuyaRepository {
  _FailingScanRepository() : super(latency: Duration.zero);

  @override
  Future<WifiScan> scanWifi() async =>
      throw const TuyaException('wifi_disabled', '手机 Wi-Fi 未开启，无法扫描');
}
