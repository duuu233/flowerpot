import '../../support/mock_tuya_repository.dart';
import 'dart:async';

import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/pairing_gate.dart';
import 'package:flowerpot/src/features/devices/presentation/device_search_page.dart';
import 'package:flowerpot/src/features/devices/presentation/pairing_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_config.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

/// 搜索页上「已发现设备」列表的 key，与页面里的 `_FoundDeviceList.listKey` 同值。
abstract final class _FoundListKey {
  static const key = Key('device-search-found-list');
}

void main() {
  // 本文件里**绝大多数用例验的是 AP（热点）那条动线**，而 2026-09-11 起 AP 被
  // `PairingGate` 整条屏蔽了（只走蓝牙，为的是验设备支不支持）。
  //
  // 这里统一把它开回来，既保住既有覆盖，也正是「屏蔽不是删除」那句话的守护：
  // AP 的代码必须一直是能跑的，将来翻回 true 不需要重写。
  // 屏蔽之后的行为由文件末尾单独的用例覆盖。
  setUp(() {
    PairingGate.apEnabled = true;
    PairingGate.showUnfilteredBleScan = false;
  });
  tearDown(PairingGate.reset);

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

  testWidgets('扫到的设备列出来，由用户点该行的「连接」进下一步', (tester) async {
    // 2026-09-10 定稿动线：搜到设备 → **列出来，每行一颗「连接」** → 用户手动点 →
    // 选路由器 Wi-Fi、输密码 → 配网。短暂试过「扫到就自动连热点并带走」，产品要求改回
    // 手动：连热点会弹系统入网授权框，自己冒出来时用户不知道发生了什么；由用户点触发，
    // 框出现在他刚表达意图的那一刻。热点本身在点「开始配网」时才连。
    Object? pairingArguments = 'unset';
    const request = PairingRequest(ssid: 'Home_2.4G', password: '12345678');
    final state = await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      request: request,
      onPairingArguments: (value) => pairingArguments = value,
    );
    await tester.pump();
    await tester.pump();

    // ⚠️ **先等过蓝牙的抢答窗口**（`_bleGrace`，4 秒）。双模是主路径，而 Wi-Fi 那条
    // 会先答（读缓存不占配额、几乎不耗时），所以窗口期内热点行是被压着不画的——
    // 否则用户会在 BLE 答出来之前就点走更差的那条路。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 先看得见：列表画出来了，页面还没被带走。
    expect(state.wifiScan?.deviceHotspots, hasLength(1));
    expect(find.byKey(_FoundListKey.key), findsOneWidget);
    expect(find.text('SmartLife-A1B2'), findsOneWidget);
    expect(find.textContaining('点设备右侧的「连接」'), findsOneWidget);
    expect(pairingArguments, 'unset');
    // 搜到设备了就不该再画「重新扫描」。
    expect(find.byKey(const Key('device-search-rescan')), findsNothing);

    // 扫到之后就停下来等用户，**不会自己跳走**。
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(pairingArguments, 'unset');

    // 点该行的「连接」：**真的去连这台设备的热点**，连上了才进下一步。
    expect(find.byKey(const Key('device-search-connect-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('device-search-connect-0')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-wifi-target'), findsOneWidget);
    final arguments = pairingArguments! as PairingArguments;
    expect(arguments.hotspotSsid, 'SmartLife-A1B2');
    // 2026-09-11：`deviceName` 字段已删（传了没人读）。这条是 AP 回落路径，
    // 所以没有 BLE uuid、也没有设备自己扫到的网络。
    expect(arguments.bleUuid, isNull);
    expect(arguments.deviceNetworks, isEmpty);
    // 连热点**之前**抓到的路由器名要带过去：连上之后手机离开路由器，下一页就读不到
    // 当前网络了，没有这一项用户得自己再挑一遍 Wi-Fi。
    expect(arguments.routerSsid, 'TP-LINK_2.4G');
    expect(arguments.request, same(request));
    expect(tester.takeException(), isNull);
  });

  testWidgets('刚开始搜不画「重新扫描」，40 秒还没搜到就立刻给出（并提示断电重启）', (tester) async {
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
    await tester.pump();
    await tester.pump();

    // 刚开始搜：不画。点了也只是白烧一次系统配额。
    expect(find.byKey(const Key('device-search-rescan')), findsNothing);

    // 40 秒还一台都没有就别让用户继续干等：**设备静置一段时间会退出配网模式**，
    // 那之后扫多久都没用。这时要告诉他断电重启，并把「重新扫描」立刻交出去——
    // 不是等满 3 分钟窗口。
    //
    // （真扫的节奏 2026-09-11 由 32 秒放到 62 秒：`startScan` 配额按 UID 算，涂鸦 SDK
    // 和搜索页共用，把 4 次用满会让 SDK 连不上设备热点。空档由 1 秒一次的读缓存补。）
    await tester.pump(const Duration(seconds: 41));
    await tester.pump();
    // 2026-09-14 文案改成一句话，插图换成配网失败那张（与蓝牙那条同一套）。
    expect(find.text('还没搜索到设备'), findsOneWidget);
    expect(find.text('请确认设备处于配网状态后，点击重新扫描'), findsOneWidget);
    expect(find.textContaining('断电重启'), findsNothing);
    expect(findAssetImage(AppAssets.pairingFailureIllustration), findsOneWidget);
    expect(find.byKey(const Key('device-search-rescan')), findsOneWidget);

    await _runOutSearchWindow(tester);

    // 窗口也走完了：标题回到最终结论。
    expect(find.text('未发现设备'), findsOneWidget);
    expect(find.byKey(const Key('device-search-rescan')), findsOneWidget);
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

  testWidgets('中途出现的设备热点由 1 秒一次的读缓存捡到，不必等下一次真扫', (tester) async {
    // 设备上电到热点广播出来要几十秒。主动扫描受 Android 配额限制（每 2 分钟
    // 4 次 ⇒ 32 秒一次），中间那 32 秒如果什么都不做，设备在这期间冒出来也要
    // 等到下一次真扫才看得见——那就是「搜了一分钟才搜到」。读缓存不受配额限制，
    // 1 秒一次把这个空档补上。
    //
    // `silentScans: 2` 对应进页面时的两次取数：① 开窗口前那次**免费的读缓存**
    // （权限框就挡在这一步，见 `_startSearchWindow`）、② 紧接着的第一次真扫。
    // 两次都只看得到路由器，热点要到第三次取数才出现——也就是由读缓存捡到。
    final state = await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: _LateHotspotRepository(silentScans: 2),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_FoundListKey.key), findsNothing);

    // 紧接着的那次读缓存（≤1 秒后）就该**拿到**热点，而不是等 32 秒后的下一次真扫。
    // 这一条才是本用例要守的东西，所以断言读的是扫描结果本身。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(state.wifiScan?.deviceHotspots, hasLength(1));

    // **画出来**还要再等过蓝牙的抢答窗口（`_bleGrace`，4 秒）：双模是主路径，那几秒
    // 先不画热点，免得用户抢在 BLE 答出来之前点走更差的那条路。拿到 ≠ 立刻画出来。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.byKey(_FoundListKey.key), findsOneWidget);
    expect(find.text('SmartLife-A1B2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 之后会自动跳走，把定时器跑完，别留下待处理的 Timer。
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
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

  testWidgets('iOS 列不出设备时给一个无条件的「下一步」', (tester) async {
    // iOS 没有任何公开 API 能枚举附近 Wi-Fi，这一页在 iOS 上永远列不出设备。
    // 但配网不需要先列出来（`NEHotspotConfiguration(ssidPrefix:)` 按前缀连），
    // 加上「设备开机即可配网」，也没有要用户确认的东西——所以直接给下一步。
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    Object? pairingArguments;
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: _ScanRepository(
        const WifiScan(current: 'Home_2.4G', currentFrequency: 2437),
      ),
      onPairingArguments: (value) => pairingArguments = value,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('下一步'), findsOneWidget);
    expect(find.byKey(const Key('device-search-rescan')), findsNothing);

    await tester.tap(find.byKey(const Key('device-search-continue')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-wifi-target'), findsOneWidget);
    // 不带热点名：iOS 侧按前缀连。
    expect((pairingArguments! as PairingArguments).hotspotSsid, isNull);
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

  // ⚠️ 下面这几条用**生产值**（AP 屏蔽、只走蓝牙）。雷达在转，别用 pumpAndSettle——
  // 扫描窗口里动画一直在跑，它等不到"安定"。

  testWidgets('蓝牙扫到设备：名字查回来之前整行不画，查回来连名带行一起出现', (tester) async {
    // 2026-09-14 产品：「搜索出设备名称会闪一下，先显示一串字符再显示设备的名称」。
    // 09-12 那版先画「正在识别设备…」占位——行先出来、字后定，照样要换一次字。
    PairingGate.reset();
    final repository = _SlowNameRepository();
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: repository,
    );
    await tester.pump();
    await tester.pump();

    repository.pushBleDevice(_ourPlanter);
    await tester.pump();
    await tester.pump();

    // 名字还在查：一行都不画，也不出现任何过渡字样。
    expect(find.byKey(_FoundListKey.key), findsNothing);
    expect(find.textContaining('uuid-pot'), findsNothing);
    expect(find.text('正在识别设备…'), findsNothing);
    expect(find.text('搜索附近设备...'), findsOneWidget);

    repository.names.complete(const BleProductInfo(name: '智能花盆'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(_FoundListKey.key), findsOneWidget);
    expect(find.text('智能花盆'), findsOneWidget);
    expect(find.text('发现 1 台设备'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('名字一直查不回来：最多等 5 秒就退回广播里的名字，设备不会一直不出现', (
    tester,
  ) async {
    PairingGate.reset();
    final repository = _SlowNameRepository();
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: repository,
    );
    await tester.pump();
    await tester.pump();

    repository.pushBleDevice(_ourPlanter);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(_FoundListKey.key), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byKey(_FoundListKey.key), findsOneWidget);
    // mac 尾号：`AA:BB:CC:00:00:02` → 「设备 0002」。
    expect(find.text('设备 0002'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('40 秒没搜到：换失败插图和一句话；点「重新扫描」和进页面一样是全新一轮', (
    tester,
  ) async {
    PairingGate.reset();
    final repository = MockTuyaRepository(latency: Duration.zero);
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: repository,
    );
    await tester.pump();
    await tester.pump();
    expect(repository.bleScanStarts, 1);
    expect(
      findAssetImage(AppAssets.pairingDeviceSearchIllustration),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 41));
    await tester.pump();
    expect(find.text('还没搜索到设备'), findsOneWidget);
    expect(find.text('请确认设备处于配网状态后，点击重新扫描'), findsOneWidget);
    expect(find.textContaining('断电重启'), findsNothing);
    expect(findAssetImage(AppAssets.pairingFailureIllustration), findsOneWidget);
    expect(
      findAssetImage(AppAssets.pairingDeviceSearchIllustration),
      findsNothing,
    );
    expect(find.byKey(const Key('device-search-rescan')), findsOneWidget);

    // 原生扫描自己到时停了。09-14 之前真机就卡在这里：状态里仍记着"在扫"，
    // 「重新扫描」被挡掉，原生根本没有重新开扫。
    repository.endBleScan();
    await tester.pump();

    await tester.tap(find.byKey(const Key('device-search-rescan')));
    await tester.pump();
    await tester.pump();

    // 和进页面同一条路：原生真的重新开扫，页面回到「搜索中」和雷达插图。
    expect(repository.bleScanStarts, 2);
    expect(find.text('搜索附近设备...'), findsOneWidget);
    expect(
      findAssetImage(AppAssets.pairingDeviceSearchIllustration),
      findsOneWidget,
    );

    // 设备这回处于配网状态：照常搜出来。
    repository.pushBleDevice(_ourPlanter);
    await tester.pump();
    await tester.pump();
    expect(find.text('智能花盆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从「连接 Wi-Fi」页退回来：重开一轮，不把上一轮的旧列表原样摆出来', (
    tester,
  ) async {
    // 2026-09-14 产品：「关闭了设备，去搜索还是会搜索出设备……不要缓存」。
    PairingGate.reset();
    final repository = MockTuyaRepository(latency: Duration.zero);
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: repository,
    );
    await tester.pump();
    await tester.pump();

    repository.pushBleDevice(_ourPlanter);
    await tester.pump();
    await tester.pump();
    expect(find.text('智能花盆'), findsOneWidget);

    await tester.tap(find.byKey(const Key('device-search-connect-0')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('pairing-wifi-target'), findsOneWidget);
    expect(repository.bleScanStarts, 1);

    // 用户在输密码页点了返回；这期间设备关机了（不再有广播上来）。
    Navigator.of(tester.element(find.text('pairing-wifi-target'))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(repository.bleScanStarts, 2);
    expect(find.byKey(_FoundListKey.key), findsNothing);
    expect(find.text('智能花盆'), findsNothing);
    expect(find.text('搜索附近设备...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 本产品的一台花盆，照真机的样子：广播里带的是 broadcastId，名字是空的。
const BleDevice _ourPlanter = BleDevice(
  uuid: 'uuid-pot',
  name: '',
  mac: 'AA:BB:CC:00:00:02',
  productId: TuyaConfig.broadcastId,
  rssi: -48,
  bound: false,
  supportWifiList: false,
);

/// 云端产品名要等用例放行（[names]）才回来；不放行就一直不回。
class _SlowNameRepository extends MockTuyaRepository {
  _SlowNameRepository() : super(latency: Duration.zero);

  final Completer<BleProductInfo> names = Completer<BleProductInfo>();

  @override
  Future<BleProductInfo> queryDeviceProductInfo({
    required String productId,
    required String uuid,
    required String mac,
  }) => names.future;
}

/// 跑满一整轮搜索窗口：窗口内页面一直显示「搜索中」，走完才给出结论。
Future<void> _runOutSearchWindow(WidgetTester tester) async {
  await tester.pump(DeviceSearchPage.searchWindow + const Duration(seconds: 1));
  await tester.pumpAndSettle();

  testWidgets('蓝牙抢答窗口：BLE 还在扫的头几秒不画 Wi-Fi 热点', (tester) async {
    final repository = MockTuyaRepository(latency: Duration.zero);
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: repository,
    );
    await tester.pump();
    await tester.pump();

    // 缓存里本来就有设备热点（系统自己一直在扫），但这几秒先不画——
    // 双模是主路径，得给 BLE 答出来的机会。
    expect(find.byKey(_FoundListKey.key), findsNothing);
    expect(find.text('SmartLife-A1B2'), findsNothing);

    // 窗口到点、BLE 一台都没扫到 ⇒ 回落到热点列表。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(_FoundListKey.key), findsOneWidget);
    expect(find.text('SmartLife-A1B2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BLE 扫到设备时走蓝牙那条：只列 BLE、不预告系统框、带上设备扫到的 Wi-Fi', (
    tester,
  ) async {
    Object? pairingArguments = 'unset';
    final repository = MockTuyaRepository(latency: Duration.zero);
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: repository,
      onPairingArguments: (value) => pairingArguments = value,
    );
    await tester.pump();
    await tester.pump();

    // 设备开始广播 BLE。
    repository.pushBleDevice(
      const BleDevice(
        uuid: 'uuid-pot',
        name: '花盆',
        mac: 'AA:BB:CC:DD:11:22',
        productId: 'pid1',
        rssi: -44,
        bound: false,
        supportWifiList: true,
      ),
    );
    await tester.pumpAndSettle();

    // **只列 BLE 那台**：同一台设备同时在广播 BLE 和拉热点，两条都列就是同一台
    // 花盆出现两行，而两边没有可靠的共同标识、去重做不干净。
    expect(find.text('花盆'), findsOneWidget);
    expect(find.text('SmartLife-A1B2'), findsNothing);
    // 走蓝牙没有系统入网授权框，别预告一件不会发生的事。
    expect(find.byKey(const Key('device-search-consent-hint')), findsNothing);
    expect(find.textContaining('系统会弹一次确认框'), findsNothing);

    await tester.tap(find.byKey(const Key('device-search-connect-0')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-wifi-target'), findsOneWidget);
    final arguments = pairingArguments! as PairingArguments;
    // 走的是双模：带 uuid、不带热点名。
    expect(arguments.bleUuid, 'uuid-pot');
    expect(arguments.hotspotSsid, isNull);
    // `supportWifiList` 为真 ⇒ 上一步已经问设备要过它自己扫到的 Wi-Fi 列表，
    // 下一页的「切换」直接列这份，不再依赖手机的 Wi-Fi 扫描。
    expect(
      arguments.deviceNetworks.map((item) => item.ssid),
      <String>['TP-LINK_2.4G', 'Xiaomi_2.4G'],
    );
    // 双模全程不离开路由器，所以当前网络就是用户要让设备加入的那个。
    expect(arguments.routerSsid, 'TP-LINK_2.4G');
    // 连之前要停扫：一边扫一边连是在抢同一个射频。
    expect(repository.bleScanStops, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AP 屏蔽后：只用蓝牙搜，热点一台都不列，页面上写清楚', (tester) async {
    PairingGate.reset(); // 用生产值：apEnabled = false、不过滤
    final repository = MockTuyaRepository(latency: Duration.zero);
    final state = await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: repository,
    );
    await tester.pump();
    await tester.pump();
    // 抢答窗口过掉也不该冒出热点——AP 整条关着。
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();

    // mock 的扫描结果里是有 `SmartLife-A1B2` 这个设备热点的。
    expect(state.wifiScan?.deviceHotspots, hasLength(1));
    // 但一行都不画。
    expect(find.byKey(_FoundListKey.key), findsNothing);
    expect(find.text('SmartLife-A1B2'), findsNothing);
    // 页面上要写清楚现在用的是什么、扫到了什么、过滤了没有。
    final status = tester.widget<Text>(
      find.byKey(const Key('device-search-ble-status')),
    );
    expect(status.data, contains('搜索方式：蓝牙'));
    expect(status.data, contains('AP 已屏蔽'));
    expect(status.data, contains('过滤：无'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AP 屏蔽后：蓝牙扫到什么就列什么，已绑定的也列出来但点不动', (tester) async {
    PairingGate.reset();
    final repository = MockTuyaRepository(latency: Duration.zero);
    await _pumpDeviceSearchPage(
      tester,
      const Size(375, 812),
      repository: repository,
    );
    await tester.pump();
    await tester.pump();

    repository
      ..pushBleDevice(
        const BleDevice(
          uuid: 'uuid-free',
          name: '花盆',
          mac: 'AA:BB:CC:DD:11:22',
          productId: 'pid1',
          rssi: -44,
          bound: false,
          supportWifiList: true,
        ),
      )
      // 已被绑定：**照样列出来**。这一轮要的是「蓝牙看见了什么」，
      // 藏起来等于把证据删掉——设备若因故被报成已绑定，过滤后页面上就是
      // 「什么都没扫到」，结论正好反了。
      ..pushBleDevice(
        const BleDevice(
          uuid: 'uuid-bound',
          name: '别人的',
          mac: 'AA:BB:CC:DD:99:99',
          productId: 'pid1',
          rssi: -40,
          bound: true,
          supportWifiList: false,
        ),
      );
    await tester.pumpAndSettle();

    expect(find.text('花盆'), findsOneWidget);
    expect(find.text('别人的'), findsOneWidget);
    // 行上的小字要把事实摆出来：绑定状态、能力位。
    expect(find.textContaining('已被绑定'), findsOneWidget);
    expect(find.textContaining('固件不支持读 Wi-Fi 列表'), findsOneWidget);
    // 已绑定那行点不动（信号更强，排在第 0 行）。
    final boundButton = tester.widget<FilledButton>(
      find.byKey(const Key('device-search-connect-0')),
    );
    expect(boundButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
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
        // 和 `FlowerpotApp` 一样挂上：搜索页靠它知道「上面那页退掉了」。
        navigatorObservers: <NavigatorObserver>[AppRoutes.routeObserver],
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
  Future<WifiScan> scanWifi({bool refresh = true}) async => scan;
}

/// 前 [silentScans] 次扫描只看得到路由器，之后设备热点才出现。
class _LateHotspotRepository extends MockTuyaRepository {
  _LateHotspotRepository({required this.silentScans})
    : super(latency: Duration.zero);

  final int silentScans;
  int _calls = 0;

  @override
  Future<WifiScan> scanWifi({bool refresh = true}) async {
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
  Future<WifiScan> scanWifi({bool refresh = true}) async =>
      throw const TuyaException('wifi_disabled', '手机 Wi-Fi 未开启，无法扫描');
}
