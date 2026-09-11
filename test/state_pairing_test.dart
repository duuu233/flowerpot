import 'support/mock_tuya_repository.dart';
import 'dart:async';

import 'package:flowerpot/src/features/devices/pairing_gate.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `pairViaHotspot` 的资源收尾与回落路径。
///
/// 用 testWidgets 而不是 test：配网失败后的云端回查靠 `Future.delayed` 等几秒，
/// 假时钟下 `tester.pump(duration)` 一步跳过去，真时钟要干等。
void main() {
  testWidgets('a failed pairing releases the hotspot and drops the token', (
    tester,
  ) async {
    final repository = _PairingRepository()
      ..pairError = const TuyaException('1006', 'out of time');
    final state = await _stateFor(tester, repository);

    final pending = state.pairViaHotspot(
      ssid: 'Home_2.4G',
      password: 'secret',
      hotspotSsid: 'SmartLife-A1B2',
    );
    // 三轮回查各等两秒。
    await tester.pump(const Duration(seconds: 7));
    final result = await pending;

    expect(result.success, isFalse);
    expect(result.code, '1006');
    // 各步耗时跟在原始报错后面，卡在哪一步从文案就能看出来。
    expect(result.message, contains('令牌'));
    expect(result.message, contains('连热点(SmartLife-A1B2)'));
    expect(repository.joinCalls, 1);
    // 连上过热点就必须放掉，否则进程一直绑在一个没有互联网的网络上。
    expect(repository.leaveCalls, 1);
    // 配网已经发出去，令牌可能被设备用掉了，下次重新取。
    expect(state.activatorTokenReady, isFalse);
    expect(state.busy, isFalse);
  });

  testWidgets('a refused hotspot join keeps the token for the retry', (
    tester,
  ) async {
    final repository = _PairingRepository()
      ..joinError = const TuyaException(
        'hotspot_join_cancelled',
        '未连上 SmartLife-A1B2',
      );
    final state = await _stateFor(tester, repository);

    final first = state.pairViaHotspot(
      ssid: 'Home_2.4G',
      password: 'secret',
      hotspotSsid: 'SmartLife-A1B2',
    );
    await tester.pump(const Duration(seconds: 1));
    final refused = await first;

    expect(refused.success, isFalse);
    expect(refused.code, 'hotspot_join_cancelled');
    expect(repository.pairCalls, 0);
    // 请求发出去过，不管系统连没连上都放一次，保证没有残留。
    expect(repository.leaveCalls, 1);
    // 令牌没用过、还在有效期内。
    expect(repository.tokenCalls, 1);
    expect(state.activatorTokenReady, isTrue);

    // 重试直接复用令牌，不再去云端取。
    repository.joinError = null;
    final second = state.pairViaHotspot(
      ssid: 'Home_2.4G',
      password: 'secret',
      hotspotSsid: 'SmartLife-A1B2',
    );
    await tester.pump(const Duration(seconds: 2));
    final retried = await second;

    expect(retried.success, isTrue);
    expect(repository.tokenCalls, 1);
    expect(repository.pairCalls, 1);
    expect(retried.message, contains('令牌(复用)'));
    expect(state.devices, hasLength(1));
    expect(state.activatorTokenReady, isFalse);
  });

  testWidgets('a platform that cannot join asks for the manual path', (
    tester,
  ) async {
    // iOS / Android 9 及以下：App 连不了热点，而手机此刻还在路由器上。
    final repository = _PairingRepository()
      ..joinError = const TuyaException('hotspot_join_unsupported', '不支持')
      ..scan = const WifiScan(
        current: 'Home_2.4G',
        currentFrequency: 2437,
        networks: <WifiNetwork>[],
      );
    final state = await _stateFor(tester, repository);

    final first = state.pairViaHotspot(
      ssid: 'Home_2.4G',
      password: 'secret',
      hotspotSsid: 'SmartLife-A1B2',
    );
    await tester.pump(const Duration(seconds: 1));
    final guidance = await first;

    expect(guidance.success, isFalse);
    expect(guidance.code, 'hotspot_manual_required');
    expect(guidance.message, contains('「SmartLife-A1B2」'));
    expect(repository.pairCalls, 0);
    // 不是失败：没有东西要放，令牌留给下一次。
    expect(repository.leaveCalls, 0);
    expect(state.activatorTokenReady, isTrue);

    // 用户到系统设置连好热点后再点一次：手机已经没有外网，不能再取令牌。
    final second = state.pairViaHotspot(
      ssid: 'Home_2.4G',
      password: 'secret',
      hotspotSsid: 'SmartLife-A1B2',
      hotspotJoinedManually: true,
    );
    await tester.pump(const Duration(seconds: 2));
    final paired = await second;

    expect(paired.success, isTrue);
    expect(paired.message, contains('连热点(手动)'));
    expect(repository.tokenCalls, 1);
    expect(repository.pairCalls, 1);
    // 手动路径下没有 App 发起的连接，也就没有要放的东西。
    expect(repository.leaveCalls, 0);
  });

  testWidgets('a phone already on the hotspot pairs without guidance', (
    tester,
  ) async {
    final repository = _PairingRepository()
      ..joinError = const TuyaException('hotspot_join_unsupported', '不支持')
      ..scan = const WifiScan(
        current: 'SmartLife-A1B2',
        networks: <WifiNetwork>[],
      );
    final state = await _stateFor(tester, repository);

    final pending = state.pairViaHotspot(
      ssid: 'Home_2.4G',
      password: 'secret',
      hotspotSsid: 'SmartLife-A1B2',
    );
    await tester.pump(const Duration(seconds: 2));
    final result = await pending;

    expect(result.success, isTrue);
    expect(repository.pairCalls, 1);
    expect(repository.leaveCalls, 0);
  });

  testWidgets('a cancelled pairing does not wait for the cloud recheck', (
    tester,
  ) async {
    final repository = _PairingRepository()
      ..pairError = const TuyaException('pair_cancelled', '配网已被中止');
    final state = await _stateFor(tester, repository);

    final pending = state.pairViaHotspot(
      ssid: 'Home_2.4G',
      password: 'secret',
      hotspotSsid: 'SmartLife-A1B2',
    );
    // 一秒够了：中止后不再做三轮两秒的回查。
    await tester.pump(const Duration(seconds: 1));
    final result = await pending;

    expect(result.success, isFalse);
    expect(result.code, 'pair_cancelled');
    expect(repository.deviceListCalls, 0);
    expect(repository.leaveCalls, 1);
    expect(state.busy, isFalse);
  });

  testWidgets('a bridge that never answers is aborted and released', (
    tester,
  ) async {
    final repository = _PairingRepository()..pairHangs = true;
    final state = await _stateFor(tester, repository);

    final pending = state.pairViaHotspot(
      ssid: 'Home_2.4G',
      password: 'secret',
      hotspotSsid: 'SmartLife-A1B2',
    );
    await tester.pump(FlowerpotState.pairingDeadline + const Duration(seconds: 2));
    final result = await pending;

    expect(result.success, isFalse);
    expect(result.code, 'pair_timeout');
    // 到点后主动让原生停掉并放资源，busy 锁也随之释放。
    expect(repository.cancelCalls, 1);
    expect(repository.leaveCalls, 1);
    expect(state.busy, isFalse);
    expect(state.activatorTokenReady, isFalse);
  });

  testWidgets('cancelPairing works while the pairing holds the lock', (
    tester,
  ) async {
    final repository = _PairingRepository()..pairHangs = true;
    final state = await _stateFor(tester, repository);

    final pending = state.pairViaHotspot(
      ssid: 'Home_2.4G',
      password: 'secret',
      hotspotSsid: 'SmartLife-A1B2',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(state.busy, isTrue);

    // 不走 _guard，配网占着锁时也能调；原生随即让 pair 以 pair_cancelled 返回。
    final cancelled = await state.cancelPairing();
    await tester.pump(const Duration(seconds: 1));
    final result = await pending;

    expect(cancelled.success, isTrue);
    expect(result.code, 'pair_cancelled');
    expect(state.busy, isFalse);
  });

  testWidgets('会话一开始就把上次记下的家庭钉给涂鸦', (tester) async {
    // 家庭属于涂鸦账号，既不依赖设备也不依赖后端：记住一次之后每次会话都用同一个，
    // 不再让原生从家庭列表里重挑——那正是「重新登录后读不到已绑定设备」的来源。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tuyaHome:mock-user': '999',
    });
    final repository = _PairingRepository();
    final state = await _stateFor(tester, repository);

    await state.login(
      account: 'demo@flowerpot.local',
      credential: 'demo',
      region: LoginRegion.overseas,
      verificationCode: false,
    );

    // 会话一开始钉的就是记下来的那个；本轮 Mock 名下没有设备，随后会走作废重来
    // 那条路，所以这里看的是第一次调用。
    expect(repository.pinnedHomes.first, '999');
    // 家庭名标记跟着账号走：换手机、清数据之后 userNo 不变，标记也不变，涂鸦那边
    // 就还能按名字认回同一个家庭。
    // 后端没下发 userId 时退回涂鸦 uid（= userNo）。
    expect(repository.homeTag, 'YS-mock-user');
    expect(state.lastHomeId, isNotNull);
  });

  testWidgets('钉住的家庭读不到设备就作废重来，以涂鸦返回的为准', (tester) async {
    // 缓存里的家庭已经不是设备所在的那个（用户删过家庭、或当初记错了）。第一次
    // 读到 0 台就必须丢掉缓存、让原生按涂鸦的列表重新解析，否则用户被永久锁在
    // 「一台设备都没有」上。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tuyaHome:mock-user': '999',
    });
    final repository = _PairingRepository();
    final state = await _stateFor(tester, repository);

    await state.login(
      account: 'demo@flowerpot.local',
      credential: 'demo',
      region: LoginRegion.overseas,
      verificationCode: false,
    );

    expect(repository.pinnedHomes, <String>['999', ''], reason: '先钉住，再作废');
    expect(repository.deviceListCalls, 2, reason: '作废之后按涂鸦的列表重读一次');
    expect(state.lastHomeId, isNotNull);
  });

  testWidgets('准备阶段查不到家庭就不去碰设备热点', (tester) async {
    // 手机已经挂在设备热点上时家庭查询会失败。此时绝不能继续：连上热点后更查不
    // 到，空列表还会被当成「账号没有家庭」而新建一个。
    final repository = _PairingRepository()
      ..homeError = const TuyaException(
        'home_offline',
        '手机正连着设备热点，暂时读不到家庭列表',
      );
    final state = await _stateFor(tester, repository);

    final result = await state.prepareForPairing();

    expect(result.success, isFalse);
    expect(result.code, 'home_offline');
    expect(repository.tokenCalls, 0);
    expect(repository.joinCalls, 0);
    expect(state.busy, isFalse);
  });

  testWidgets('准备阶段确认家庭后才取令牌', (tester) async {
    final repository = _PairingRepository();
    final state = await _stateFor(tester, repository);

    final result = await state.prepareForPairing();

    expect(result.success, isTrue);
    expect(result.message, contains('123456'));
    expect(repository.homeCalls, 1);
    expect(repository.tokenCalls, 1);
    expect(state.activatorTokenReady, isTrue);
    // 令牌还在有效期内就不再取第二遍。
    await state.prepareForPairing();
    expect(repository.tokenCalls, 1);
  });

  testWidgets('旧原生包没有 currentHomeId 时不拦路', (tester) async {
    final repository = _PairingRepository()
      ..homeError = const TuyaException('sdk_unavailable', '原生涂鸦 SDK 尚未接入');
    final state = await _stateFor(tester, repository);

    final result = await state.prepareForPairing();

    expect(result.success, isTrue);
    expect(repository.tokenCalls, 1);
  });

}

/// 建一个状态对象并挂一棵空树，让测试假时钟推进。
Future<FlowerpotState> _stateFor(
  WidgetTester tester,
  TuyaRepository repository,
) async {
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await tester.pumpWidget(const SizedBox());
  return state;
}

/// 可编排三步的 Mock：取令牌、连热点、配网各自可以成功、报错或挂起。
class _PairingRepository extends MockTuyaRepository {
  _PairingRepository() : super(latency: Duration.zero, seedDevice: false);

  int tokenCalls = 0;
  int joinCalls = 0;
  int leaveCalls = 0;
  int cancelCalls = 0;
  int pairCalls = 0;
  int deviceListCalls = 0;

  TuyaException? joinError;

  /// 配网准备阶段查到的家庭；抛错表示这时查不到（例如手机已经在设备热点上）。
  String homeId = '123456';
  TuyaException? homeError;
  /// 每次 `useHome` 的入参，按顺序记下来：空串表示作废当前固定的家庭。
  final List<String> pinnedHomes = <String>[];

  /// 会话开始下发的家庭名标记。
  String? homeTag;
  int homeCalls = 0;
  TuyaException? pairError;

  /// 双模配网要报的错误码（涂鸦那边是 int）；null 表示照常成功。
  int? blePairError;
  bool pairHangs = false;
  WifiScan scan = const WifiScan(networks: <WifiNetwork>[]);

  Completer<SmartPlanterDevice>? _hanging;

  @override
  Future<void> prepareActivatorToken() async => tokenCalls++;

  @override
  Future<SmartPlanterDevice> pairBleDevice({
    required String uuid,
    required String ssid,
    required String password,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final code = blePairError;
    if (code != null) {
      throw TuyaException('$code', '双模配网失败');
    }
    return super.pairBleDevice(
      uuid: uuid,
      ssid: ssid,
      password: password,
      timeout: timeout,
    );
  }

  @override
  Future<String> currentHomeId() async {
    homeCalls++;
    final error = homeError;
    if (error != null) throw error;
    return homeId;
  }

  @override
  Future<void> useHome(String homeId) async => pinnedHomes.add(homeId);

  @override
  Future<void> useHomeTag(String tag) async => homeTag = tag;

  @override
  Future<bool> joinDeviceHotspot({String? ssid, String? prefix}) async {
    joinCalls++;
    final error = joinError;
    if (error != null) throw error;
    return true;
  }

  @override
  Future<void> leaveDeviceHotspot() async => leaveCalls++;

  @override
  Future<void> cancelPairing() async {
    cancelCalls++;
    // 和原生一致：进行中的配网以 pair_cancelled 返回。
    final hanging = _hanging;
    _hanging = null;
    if (hanging != null && !hanging.isCompleted) {
      hanging.completeError(
        const TuyaException('pair_cancelled', '配网已被中止'),
      );
    }
  }

  @override
  Future<WifiScan> scanWifi({bool refresh = true}) async => scan;

  @override
  Future<SmartPlanterDevice> pair(PairingRequest request) {
    pairCalls++;
    if (pairHangs) {
      final completer = Completer<SmartPlanterDevice>();
      _hanging = completer;
      return completer.future;
    }
    final error = pairError;
    if (error != null) return Future<SmartPlanterDevice>.error(error);
    return super.pair(request);
  }

  @override
  Future<List<SmartPlanterDevice>> getDevices() {
    deviceListCalls++;
    return super.getDevices();
  }

  test('AP 热点配网：连热点 → 取令牌 → 下发凭据 → 退出时还原网络', () async {
    // 这是**唯一**一条配网路径（2026-09-11 定稿）。EZ、涂鸦「新流程」、扩展 SDK
    // 三条都已删掉，原因见 `FlowerpotState.pairViaHotspot` 的说明。
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);

    // ① 搜索页那颗「连接」：只连热点，不配网。
    final connected = await state.connectDeviceHotspot(hotspotSsid: 'SmartLife-1234');
    expect(connected.success, isTrue);

    // ② 下一页输完密码才真配网。
    final paired = await state.pairViaHotspot(
      ssid: 'Home_2.4G',
      password: '12345678',
      hotspotSsid: 'SmartLife-1234',
    );
    expect(paired.success, isTrue);
    expect(state.selectedDevice, isNotNull);
    expect(state.pairingStage, PairingStage.idle);

    // ③ 退出动线必须把手机的 Wi-Fi 还回去（`PRODUCT_RULES` §1.4.1）。
    await state.stopDevicePairing();
    expect(state.pairingStage, PairingStage.idle);
  });

  testWidgets('BLE 发现：先弹授权框、答完再探测（首次进入才不会误报"缺权限"）', (
    tester,
  ) async {
    final repository = MockTuyaRepository(
      latency: Duration.zero,
      seedDevice: false,
    );
    final state = await _stateFor(tester, repository);

    expect(await state.startBleDiscovery(), isTrue);
    // ⚠️ 顺序就是这条路的命门：授权必须在探测**之前**跑完。2026-09-11 真机上
    // 「第一次进搜不到、退出去重进就好了」，根因正是探测抢在授权框被回答之前完成、
    // 报了个假的"未授予"，而且之后再没人重新探测。
    expect(repository.blePermissionRequests, 1);
    expect(repository.bleScanStarts, 1);

    await state.stopBleDiscovery();
  });

  testWidgets('BLE 发现：扫到的设备逐台进列表，已绑的不列', (tester) async {
    // 这一条验的是**过滤开着**时的口径。2026-09-11 起生产值是「不过滤」
    // （`PairingGate.showUnfilteredBleScan`，为了验设备支不支持蓝牙），
    // 但过滤那套逻辑必须一直是能跑的——将来关掉排查模式就靠它。
    PairingGate.showUnfilteredBleScan = false;
    addTearDown(PairingGate.reset);
    final repository = MockTuyaRepository(
      latency: Duration.zero,
      seedDevice: false,
    );
    final state = await _stateFor(tester, repository);

    expect(await state.startBleDiscovery(), isTrue);
    expect(repository.bleScanStarts, 1);
    expect(state.bleScanning, isTrue);

    repository
      ..pushBleDevice(
        const BleDevice(
          uuid: 'uuid-far',
          name: '',
          mac: 'AA:BB:CC:DD:3F:A2',
          productId: 'pid1',
          rssi: -80,
          bound: false,
          supportWifiList: true,
        ),
      )
      ..pushBleDevice(
        const BleDevice(
          uuid: 'uuid-near',
          name: '花盆',
          mac: 'AA:BB:CC:DD:11:22',
          productId: 'pid1',
          rssi: -42,
          bound: false,
          supportWifiList: false,
        ),
      )
      // 已经绑在某个账号下的不该出现：点进去只会得到一次配网失败。
      ..pushBleDevice(
        const BleDevice(
          uuid: 'uuid-bound',
          name: '别人的',
          mac: 'AA:BB:CC:DD:99:99',
          productId: 'pid1',
          rssi: -40,
          bound: true,
          supportWifiList: true,
        ),
      );
    await tester.pump();

    expect(
      state.bleDevices.map((item) => item.uuid),
      // 信号强的在前。
      <String>['uuid-near', 'uuid-far'],
    );
    // 广播里没有名字时退到 mac 尾号，别画一个空行。
    expect(state.bleDevices.last.label, '设备 3FA2');

    // 退出动线必须停扫：回调在原生侧握着 Activity，而且在真的耗电。
    await state.stopBleDiscovery();
    expect(repository.bleScanStops, 1);
    expect(state.bleScanning, isFalse);
  });

  testWidgets('BLE 查 Wi-Fi 列表：老固件直接拒，不让用户干等超时', (tester) async {
    final repository = MockTuyaRepository(
      latency: Duration.zero,
      seedDevice: false,
    );
    final state = await _stateFor(tester, repository);

    // `supportWifiList == false`（固件 TuyaOS < 3.6.1）：这条命令设备不认，
    // 调下去只会等满超时，所以在 Dart 侧就拦住。
    const legacy = BleDevice(
      uuid: 'uuid-legacy',
      name: '老固件',
      mac: 'AA:BB:CC:DD:00:01',
      productId: 'pid1',
      rssi: -50,
      bound: false,
      supportWifiList: false,
    );
    final refused = await state.loadDeviceWifiList(legacy);
    expect(refused.success, isFalse);
    expect(refused.code, 'ble_wifi_list_unsupported');
    expect(state.deviceWifiNetworks, isEmpty);

    // 支持的固件：拿回设备**自己扫到的**那份列表。
    const modern = BleDevice(
      uuid: 'uuid-modern',
      name: '新固件',
      mac: 'AA:BB:CC:DD:00:02',
      productId: 'pid1',
      rssi: -50,
      bound: false,
      supportWifiList: true,
    );
    final loaded = await state.loadDeviceWifiList(modern);
    expect(loaded.success, isTrue);
    expect(
      state.deviceWifiNetworks.map((item) => item.ssid),
      <String>['TP-LINK_2.4G', 'Xiaomi_2.4G'],
    );
    expect(state.deviceWifiNetworks.first.needsPassword, isTrue);
  });

  testWidgets('双模配网：凭据经蓝牙下发，全程不碰设备热点', (tester) async {
    final repository = _PairingRepository();
    final state = await _stateFor(tester, repository);

    final result = await state.pairViaBle(
      uuid: 'uuid-modern',
      ssid: 'Home_2.4G',
      password: '12345678',
    );

    expect(result.success, isTrue);
    expect(repository.blePairCalls, <(String, String)>[
      ('uuid-modern', 'Home_2.4G'),
    ]);
    // **一次热点都没连过。** 这正是双模那条的意义：没有 `WifiNetworkSpecifier`
    // ⇒ 没有系统入网授权框，手机也从没离开路由器。
    expect(repository.joinCalls, 0);
    expect(repository.leaveCalls, 0);
    // 令牌照旧要取——它走云端，和走哪条配网路径无关。
    expect(repository.tokenCalls, 1);
    // 耗时分步仍写进文案，卡在哪一步看得出来。
    expect(result.message, contains('令牌'));
    expect(result.message, contains('配网'));
    expect(state.selectedDevice, isNotNull);
    expect(state.pairingStage, PairingStage.idle);
    // 涂鸦的令牌是一次性的，成功后必须作废。
    expect(state.activatorTokenReady, isFalse);
  });

  testWidgets('双模配网失败：只作废令牌，不去放根本没连过的热点', (tester) async {
    final repository = _PairingRepository()..blePairError = 2;
    final state = await _stateFor(tester, repository);

    final pending = state.pairViaBle(
      uuid: 'uuid-modern',
      ssid: 'Home_2.4G',
      password: '12345678',
    );
    // 失败后有三轮云端回查，各等两秒。
    await tester.pump(const Duration(seconds: 7));
    final result = await pending;

    expect(result.success, isFalse);
    expect(repository.leaveCalls, 0);
    expect(state.activatorTokenReady, isFalse);
    expect(state.pairingStage, PairingStage.idle);
  });
}
