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
  testWidgets('新DP立即显示，不等待旧快照，迟到66不能覆盖99及其它实时字段', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    final old = Completer<Map<int, Object?>?>();
    state.snapshot = () => old.future;
    final binding = device.bind(state, owner: Object(), deviceId: _id);
    expect(device.hasBatteryReport, isFalse);
    state.reports.add((
      deviceId: _id,
      changedDps: {MowerDp.battery, MowerDp.status, MowerDp.chargingStatus},
      reportedDps: {
        MowerDp.battery: 99,
        MowerDp.status: 'mowing',
        MowerDp.chargingStatus: 'full',
      },
    ));
    await tester.pump();
    expect(device.battery, 99);
    expect(device.hasBatteryReport, isTrue);
    expect(device.status, MowerStatus.mowing);
    expect(device.charging, MowerChargingStatus.full);
    old.complete({
      MowerDp.battery: 66,
      MowerDp.status: 'standby',
      MowerDp.rainDelay: 25,
    });
    await binding;
    expect(device.battery, 99);
    expect(device.status, MowerStatus.mowing);
    expect(device.rainDelayMinutes, 25);
  });

  testWidgets('连续实时值按到达顺序显示，电量下降不做单调缓存保护', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    await device.bind(state, owner: Object(), deviceId: _id);
    final blocked = Completer<Map<int, Object?>?>();
    state.snapshot = () => blocked.future;
    for (final level in [99, 66, 0]) {
      state.reports.add((
        deviceId: _id,
        changedDps: {MowerDp.battery},
        reportedDps: {MowerDp.battery: level},
      ));
      await tester.pump();
      expect(device.battery, level);
    }
    blocked.complete({MowerDp.battery: 12});
    expect(device.hasBatteryReport, isTrue);
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
      StreamController<
        ({String deviceId, Set<int> changedDps, Map<int, Object?> reportedDps})
      >.broadcast();
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
  Stream<
    ({String deviceId, Set<int> changedDps, Map<int, Object?> reportedDps})
  >
  get mowerReports => reports.stream;
  @override
  void dispose() {
    disposed = true;
    unawaited(reports.close());
    super.dispose();
  }
}
