import 'dart:async';

import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';

const _id = 'mower-lifecycle';

void main() {
  setUp(MowerDevice.instance.resetForTest);
  testWidgets('退出重进同一设备：旧快照不能覆盖新会话', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    final oldSnapshot = Completer<Map<int, Object?>?>();
    state.snapshot = () => oldSnapshot.future;
    final oldOwner = Object();
    final oldBind = device.bind(state, owner: oldOwner, deviceId: _id);
    device.release(oldOwner);
    state.snapshot = () async => {MowerDp.battery: 77};
    await device.bind(state, owner: Object(), deviceId: _id);
    oldSnapshot.complete({MowerDp.battery: 12});
    await oldBind;
    expect(device.battery, 77);
  });

  testWidgets('退出重进同一设备：旧连接查询不能覆盖新图标', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    final oldLink = Completer<Map<String, Object?>>();
    state.link = () => oldLink.future;
    final oldOwner = Object();
    await device.bind(state, owner: oldOwner, deviceId: _id);
    device.release(oldOwner);
    state.link = () async => {'ble': true, 'wifi': true};
    await device.bind(state, owner: Object(), deviceId: _id);
    await device.refreshLink(state);
    oldLink.complete({'ble': false, 'wifi': false});
    await tester.pump();
    expect(device.wifiLinked, isTrue);
    expect(device.bleLinked, isTrue);
    expect(state.connects, 0);
  });

  testWidgets('退出重进：未发送的旧指令取消，新指令不等旧请求', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    final oldSend = Completer<ActionResult>();
    state.send = (_) => oldSend.future;
    final oldOwner = Object();
    await device.bind(state, owner: oldOwner, deviceId: _id);
    device.setMode(state, MowerMode.smart);
    device.setMode(state, MowerMode.spot);
    await tester.pump();
    expect(state.sent, hasLength(1));
    device.release(oldOwner);
    await device.bind(state, owner: Object(), deviceId: _id);
    state.send = (_) async => const ActionResult(true, 'ok');
    device.setSwitch(state, on: true);
    await tester.pump();
    expect(state.sent, hasLength(2));
    expect(state.sent.last, {MowerDp.switchGo: true});
    oldSend.complete(const ActionResult(true, 'ok'));
    await tester.pump();
    expect(state.sent, hasLength(2));
    device.resetForTest();
    await tester.pump(MowerDevice.echoTimeout);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SDK 快照异常：绑定不抛未处理异常，并提示读取失败', (tester) async {
    final state = _state();
    state.snapshot = () async => throw StateError('snapshot failed');
    final failures = <String>[];
    final sub = MowerDevice.instance.failures.listen(failures.add);
    await MowerDevice.instance.bind(state, owner: Object(), deviceId: _id);
    await tester.pump();
    expect(failures, ['设备信息读取失败，请返回后重试']);
    unawaited(sub.cancel());
    expect(tester.takeException(), isNull);
  });

  testWidgets('SDK 连接查询异常：保留上次图标且轮询能继续', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    await device.bind(state, owner: Object(), deviceId: _id);
    await device.refreshLink(state);
    state.link = () async => throw StateError('link failed');
    await device.refreshLink(state, autoConnect: true);
    expect(device.wifiLinked, isTrue);
    state.link = () async => {'ble': true, 'wifi': false};
    await device.refreshLink(state);
    expect(device.wifiLinked, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧请求退出后报错：不通知新页面，不访问已销毁状态', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    final oldSnapshot = Completer<Map<int, Object?>?>();
    final oldLink = Completer<Map<String, Object?>>();
    state.snapshot = () => oldSnapshot.future;
    state.link = () => oldLink.future;
    final owner = Object();
    final binding = device.bind(state, owner: owner, deviceId: _id);
    device.release(owner);
    state.dispose();
    oldSnapshot.completeError(StateError('late snapshot error'));
    oldLink.completeError(StateError('late link error'));
    await binding;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('并发刷新合并查询，蓝牙连接异常后允许下次重试', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    await device.bind(state, owner: Object(), deviceId: _id);
    await device.refreshLink(state);
    final gate = Completer<Map<String, Object?>>();
    var reads = 0;
    state.link = () {
      reads++;
      return gate.future;
    };
    final first = device.refreshLink(state, autoConnect: true);
    final second = device.refreshLink(state, autoConnect: true);
    expect(reads, 1);
    state.connect = () async => throw StateError('connect failed');
    gate.complete({'ble': false, 'wifi': false});
    await Future.wait([first, second]);
    state.link = () async => {'ble': false, 'wifi': false};
    state.connect = () async => {'connected': false};
    await device.refreshLink(state, autoConnect: true, force: true);
    expect(state.connects, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('回显超时后的快照异常不会逃出计时器', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    await device.bind(state, owner: Object(), deviceId: _id);
    device.setSwitch(state, on: true);
    await tester.pump();
    state.snapshot = () async => throw StateError('rollback failed');
    await tester.pump(MowerDevice.echoTimeout);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('上报流异常被处理，后续正常上报仍可更新设备', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    await device.bind(state, owner: Object(), deviceId: _id);
    state.reports.addError(StateError('report failed'));
    await tester.pump();
    state.snapshot = () async => {MowerDp.battery: 66};
    state.reports.add((deviceId: _id, changedDps: {MowerDp.battery}));
    await tester.pump();
    expect(device.battery, 66);
    expect(tester.takeException(), isNull);
  });
}

_ControlledState _state() {
  MowerDevice.instance.resetForTest();
  final state = _ControlledState();
  addTearDown(() {
    MowerDevice.instance.resetForTest();
    if (!state.disposed) state.dispose();
  });
  return state;
}

class _ControlledState extends FlowerpotState {
  _ControlledState()
    : super(repository: MockTuyaRepository(latency: Duration.zero));

  Future<Map<int, Object?>?> Function() snapshot = () async => {};
  Future<Map<String, Object?>> Function() link = () async => {
    'ble': true,
    'wifi': true,
  };
  Future<Map<String, Object?>> Function() connect = () async => {
    'connected': true,
  };
  Future<ActionResult> Function(Map<int, Object>) send = (_) async =>
      const ActionResult(true, 'ok');
  final reports =
      StreamController<({String deviceId, Set<int> changedDps})>.broadcast();
  final sent = <Map<int, Object>>[];
  int connects = 0;
  bool disposed = false;

  @override
  Future<Map<int, Object?>?> mowerDps(String deviceId) => snapshot();
  @override
  Future<Map<String, Object?>> deviceLinkState(String deviceId) => link();
  @override
  Future<Map<String, Object?>> connectDeviceBle(String deviceId) {
    connects++;
    return connect();
  }

  @override
  Future<ActionResult> publishMowerDps(String deviceId, Map<int, Object> dps) {
    sent.add(Map.of(dps));
    return send(dps);
  }

  @override
  Stream<({String deviceId, Set<int> changedDps})> get mowerReports =>
      reports.stream;
  @override
  void dispose() {
    disposed = true;
    unawaited(reports.close());
    super.dispose();
  }
}
