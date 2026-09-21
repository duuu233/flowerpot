import 'support/mock_tuya_repository.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_config.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 恢复出厂设置：**先下发恢复出厂 DP 141，下发成功才解绑**，解绑用 SDK 的
/// `resetFactory`（2026-09-21 产品口径）。141 发不出去就停下、设备保持绑定；
/// 「重新配网」不受这条约束（设备离线正是它的常见场景）。
void main() {
  final id = MockTuyaRepository.fixtureDevice.id;
  final resetDp = TuyaConfig.dp['factory_reset'];

  test('恢复出厂：先下发 141，下发成功后再用 resetFactory 解绑', () async {
    final repository = _ResetRepository();
    final state = await _state(repository);
    addTearDown(state.dispose);

    final result = await state.factoryResetDevice(id);

    expect(result.success, isTrue);
    expect(result.message, '设备已解绑并清除数据');
    // 顺序就是这条需求本身：141 在前，解绑在后；解绑走的是「解绑并清除数据」。
    expect(repository.calls, <String>[
      'publishDps {$resetDp: true}',
      'resetFactory',
    ]);
    expect(state.deviceById(id), isNull);
  });

  test('恢复出厂：141 下发失败就停下，设备不解绑', () async {
    final repository = _ResetRepository()
      ..publishError = const TuyaException('11001', '指令下发超时');
    final state = await _state(repository);
    addTearDown(state.dispose);

    final result = await state.factoryResetDevice(id);

    expect(result.success, isFalse);
    // 原始码照带，文案说清设备没被解绑。
    expect(result.code, '11001');
    expect(result.message, contains('设备未解绑'));
    expect(result.message, contains('指令下发超时'));
    expect(repository.calls, <String>['publishDps {$resetDp: true}']);
    expect(state.deviceById(id), isNotNull);
  });

  test('恢复出厂：设备离线时 141 不发、也不解绑', () async {
    final repository = _ResetRepository()..online = false;
    final state = await _state(repository);
    addTearDown(state.dispose);

    final result = await state.factoryResetDevice(id);

    expect(result.success, isFalse);
    // 沿用统一的离线口径：页面据这个码提示「设备已离线」并回设备列表。
    expect(result.code, 'device_offline');
    expect(repository.calls, isEmpty);
    expect(state.deviceById(id), isNotNull);
  });

  test('重新配网不受影响：设备离线发不出 141，照样解绑', () async {
    // 换了路由器、设备离线，正是要重新配网的时候——这条路拦住就配不回来了。
    final repository = _ResetRepository()..online = false;
    final state = await _state(repository);
    addTearDown(state.dispose);

    final result = await state.removeDevice(id, resetFactory: true);

    expect(result.success, isTrue);
    expect(repository.calls, <String>['resetFactory']);
    expect(state.deviceById(id), isNull);
  });

  test('移除设备：不发 141，直接解绑（removeDevice）', () async {
    final repository = _ResetRepository();
    final state = await _state(repository);
    addTearDown(state.dispose);

    final result = await state.removeDevice(id, resetFactory: false);

    expect(result.success, isTrue);
    expect(result.message, '设备已解绑');
    expect(repository.calls, <String>['removeDevice']);
  });
}

Future<FlowerpotState> _state(_ResetRepository repository) async {
  final state = FlowerpotState(repository: repository);
  await state.initialize();
  await state.refreshDevices();
  return state;
}

/// 记下下发与解绑的先后；下发可以按用例报错，设备可以设成离线。
class _ResetRepository extends MockTuyaRepository {
  _ResetRepository() : super(latency: Duration.zero);

  final List<String> calls = <String>[];
  TuyaException? publishError;
  bool online = true;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async {
    final devices = await super.getDevices();
    return devices.map((device) => device.copyWith(online: online)).toList();
  }

  // 在线轮询也按 [online] 回答，免得它把设备改回在线。
  @override
  Future<Map<String, bool>> deviceOnlineStates(List<String> deviceIds) async =>
      <String, bool>{for (final deviceId in deviceIds) deviceId: online};

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    calls.add('publishDps $dps');
    final error = publishError;
    if (error != null) throw error;
  }

  @override
  Future<void> removeDevice(
    String deviceId, {
    required bool resetFactory,
  }) {
    calls.add(resetFactory ? 'resetFactory' : 'removeDevice');
    return super.removeDevice(deviceId, resetFactory: resetFactory);
  }
}
