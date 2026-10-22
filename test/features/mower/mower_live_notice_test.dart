import 'dart:async';

import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/mower_live_notice.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';

const _id = 'mower-live-notice';

String _alarm({int circularize = 0}) =>
    '{"device":0,"error":0,"function":0,"circularize":$circularize}';

/// 首页黄条实时提醒（2026-10-22 检查报告第 5、6 节）：
/// DP111 circularize 实时抬起位 + DP120 事件码 44/144 → 设备已抬起 / 设备已落地；
/// DP120 41/141 → 机器陷入坑洼，正在脱困。
void main() {
  setUp(MowerDevice.instance.resetForTest);

  testWidgets('DP111实时抬起位：由无变有提示已抬起，变回无提示已落地并几秒后收起', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    await device.bind(state, owner: Object(), deviceId: _id);
    expect(device.liveNotice, isNull);

    state.report({MowerDp.faultAlarm: _alarm(circularize: 0x1000)});
    await tester.pump();
    expect(device.liveNotice, '设备已抬起');

    state.report({MowerDp.faultAlarm: _alarm()});
    await tester.pump();
    expect(device.liveNotice, '设备已落地');

    await tester.pump(MowerLiveNotice.landedVisible);
    expect(device.liveNotice, isNull);
  });

  testWidgets('抬起1–3秒就放下：先已抬起再已落地；事件码与DP111谁先到用谁，不重复', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    await device.bind(state, owner: Object(), deviceId: _id);
    var notifications = 0;
    void count() => notifications++;
    device.addListener(count);
    addTearDown(() => device.removeListener(count));

    state.report({MowerDp.alarmEvent: 44});
    await tester.pump();
    expect(device.liveNotice, '设备已抬起');
    state.report({MowerDp.faultAlarm: _alarm(circularize: 0x1000)});
    await tester.pump();
    expect(device.liveNotice, '设备已抬起');

    await tester.pump(const Duration(seconds: 2));
    state.report({MowerDp.alarmEvent: 144});
    await tester.pump();
    expect(device.liveNotice, '设备已落地');
    // DP111 随后到，状态已经是落地，不再重新计时
    state.report({MowerDp.faultAlarm: _alarm()});
    await tester.pump(const Duration(seconds: 2));
    expect(device.liveNotice, '设备已落地');
    await tester.pump(const Duration(seconds: 1));
    expect(device.liveNotice, isNull);
    expect(notifications, greaterThan(0));
  });

  testWidgets('刚进页面快照里抬着就显示已抬起；快照里的旧事件码不触发提示', (tester) async {
    final state = _state()
      ..snapshot = () async => {
        MowerDp.faultAlarm: _alarm(circularize: 0x1000),
        MowerDp.alarmEvent: 41,
      };
    final device = MowerDevice.instance;
    await device.bind(state, owner: Object(), deviceId: _id);
    expect(device.liveNotice, '设备已抬起');

    state.snapshot = () async => {
      MowerDp.faultAlarm: _alarm(),
      MowerDp.alarmEvent: 41,
    };
    // 重新进页面（bind 先解开上一次绑定）
    await device.bind(state, owner: Object(), deviceId: _id);
    expect(device.liveNotice, isNull, reason: '不补「已落地」，旧41不算脱困');
  });

  testWidgets('41提示正在脱困，141收起；收不到141时超时收起', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    await device.bind(state, owner: Object(), deviceId: _id);

    state.report({MowerDp.alarmEvent: 41});
    await tester.pump();
    expect(device.liveNotice, '机器陷入坑洼，正在脱困');
    state.report({MowerDp.alarmEvent: 141});
    await tester.pump();
    expect(device.liveNotice, isNull);

    state.report({MowerDp.alarmEvent: 41});
    await tester.pump();
    expect(device.liveNotice, '机器陷入坑洼，正在脱困');
    await tester.pump(MowerLiveNotice.trapTimeout);
    expect(device.liveNotice, isNull);
  });

  testWidgets('脱困失败报陷坑故障（DP18 bit11 或事件31）：收起脱困提示，交给故障文案', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    await device.bind(state, owner: Object(), deviceId: _id);

    state.report({MowerDp.alarmEvent: 41});
    await tester.pump();
    state.report({MowerDp.fault: 1 << 11});
    await tester.pump();
    expect(device.liveNotice, isNull);
    expect(device.faultMessage, '机器被困，请移至平坦区域。');

    state.report({MowerDp.fault: 0});
    state.report({MowerDp.alarmEvent: 41});
    await tester.pump();
    state.report({MowerDp.alarmEvent: 31});
    await tester.pump();
    expect(device.liveNotice, isNull);
  });

  testWidgets('退出页面清掉提示和计时器', (tester) async {
    final state = _state();
    final device = MowerDevice.instance;
    final owner = Object();
    await device.bind(state, owner: owner, deviceId: _id);
    state.report({MowerDp.alarmEvent: 41});
    await tester.pump();
    expect(device.liveNotice, isNotNull);
    device.release(owner);
    expect(device.liveNotice, isNull);
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
  final reports =
      StreamController<
        ({String deviceId, Set<int> changedDps, Map<int, Object?> reportedDps})
      >.broadcast();
  bool disposed = false;

  void report(Map<int, Object?> dps) => reports.add((
    deviceId: _id,
    changedDps: dps.keys.toSet(),
    reportedDps: dps,
  ));

  @override
  Future<Map<int, Object?>?> mowerDps(String deviceId) => snapshot();
  @override
  Future<Map<String, Object?>> deviceLinkState(String deviceId) async => {
    'ble': true,
    'wifi': true,
  };
  @override
  Future<ActionResult> publishMowerDps(
    String deviceId,
    Map<int, Object> dps,
  ) async => const ActionResult(true, 'ok');

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
