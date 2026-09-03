import 'dart:async';

import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

/// 建一个状态对象并挂一棵空树，让 `tester.pump(duration)` 有帧可推、假时钟能走。
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
  TuyaException? pairError;
  bool pairHangs = false;
  WifiScan scan = const WifiScan(networks: <WifiNetwork>[]);

  Completer<SmartPlanterDevice>? _hanging;

  @override
  Future<void> prepareActivatorToken() async => tokenCalls++;

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
