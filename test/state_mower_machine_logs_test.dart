import 'package:flowerpot/src/features/mower/mower_machine_log.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mock_tuya_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FlowerpotState> stateFor(
    String? account, {
    bool failSnapshot = false,
  }) async {
    final state = FlowerpotState(
      repository: _LogRepository(account, failSnapshot),
    );
    await state.initialize();
    state.pauseDeviceWatch();
    addTearDown(state.dispose);
    return state;
  }

  test('机器日志按账号、设备落盘，重进恢复文案和已读，其他账号不串记录', () async {
    final state = await stateFor('owner-a');
    final log = await state.mowerMachineLog('mower-a');
    log.apply({5: 1});
    log.markRead();
    await state.saveMowerMachineLog('mower-a');
    final sameAccount = await stateFor('owner-a');
    final restored = await sameAccount.mowerMachineLog('mower-a');
    expect(restored.entries.single.message(false), '开始割草');
    expect(restored.entries.single.message(true), 'Mowing started');
    expect(restored.entries.single.read, isTrue);
    expect((await sameAccount.mowerMachineLog('mower-b')).entries, isEmpty);
    final other = await stateFor('owner-b');
    expect((await other.mowerMachineLog('mower-a')).entries, isEmpty);
  });

  test('未登录只保留内存，不写账号为空的本机记录', () async {
    final state = await stateFor(null);
    final log = await state.mowerMachineLog('mower-a');
    log.apply({5: 1});
    await state.saveMowerMachineLog('mower-a');
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().where((key) => key.startsWith('mowerMachineLog:')),
      isEmpty,
    );
    final another = await stateFor(null);
    expect((await another.mowerMachineLog('mower-a')).entries, isEmpty);
  });

  test('设备快照读取失败不阻断本机日志，后续实时记录仍可持久化', () async {
    final state = await stateFor('owner-a', failSnapshot: true);
    final log = await state.mowerMachineLog('mower-a');
    expect(log, isA<MowerMachineLog>());
    log.apply({5: 1});
    await state.saveMowerMachineLog('mower-a');
    expect(identical(await state.mowerMachineLog('mower-a'), log), isTrue);
    final recovered = await stateFor('owner-a');
    expect(
      (await recovered.mowerMachineLog(
        'mower-a',
      )).entries.single.message(false),
      '开始割草',
    );
  });
}

class _LogRepository extends MockTuyaRepository {
  _LogRepository(this.account, this.failSnapshot)
    : super(latency: Duration.zero, seedDevice: false);
  final String? account;
  final bool failSnapshot;
  @override
  Future<AppUser?> restoreSession() async => account == null
      ? null
      : AppUser(id: account!, nickname: '测试账号', account: account!);
  @override
  Future<Map<int, Object?>?> rawDps(String deviceId) async {
    if (failSnapshot) throw StateError('snapshot unavailable');
    return {};
  }
}
