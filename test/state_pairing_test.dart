import 'support/mock_tuya_repository.dart';
import 'dart:async';

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
  bool pairHangs = false;
  WifiScan scan = const WifiScan(networks: <WifiNetwork>[]);

  Completer<SmartPlanterDevice>? _hanging;

  @override
  Future<void> prepareActivatorToken() async => tokenCalls++;

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
  Future<WifiScan> scanWifi() async => scan;

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
}
