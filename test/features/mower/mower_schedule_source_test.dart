import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_plan_edit_sheet.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_raw.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/mock_tuya_repository.dart';
import '../../support/plant_catalog.dart';

const id = 'mower-dp-source';
SmartPlanterDevice device() => SmartPlanterDevice(
  id: id,
  productId: MowerDp.productId,
  name: 'test mower',
  online: true,
  signal: 80,
  battery: 50,
  charging: false,
  boundAt: DateTime(2026),
  plant: PlantCatalog.items.first,
  sensors: const SensorSnapshot(
    waterLevel: 0,
    soilMoisture: 0,
    illuminance: 0,
    ppfd: 0,
    airTemperature: 0,
    relativeHumidity: 0,
  ),
  settings: const DeviceControlSettings(),
  firmwareVersion: '1.0',
  macAddress: '',
);

// 合成协议帧，绝不是用户真机默认包。true=七天启用且修边，false=模拟用户所述现象。
Uint8List frame(bool allEnabled) {
  final data = Uint8List(88);
  for (var group = 1; group <= 7; group++) {
    final enabled = allEnabled || group != 1;
    final edge = allEnabled || group == 3 || group == 5 || group == 7;
    data.setRange(group * 11, group * 11 + 11, [
      0x1c,
      0x02,
      0xd0,
      0x02,
      0x48,
      0x03,
      0x38,
      0x04,
      edge ? 1 : 0,
      enabled ? 1 : 0,
      0,
    ]);
  }
  return data;
}

class Repo extends MockTuyaRepository {
  Repo() : super(latency: Duration.zero, seedDevice: false);
  Completer<Map<int, Object?>?>? hold;
  @override
  Future<List<SmartPlanterDevice>> getDevices() async => [device()];
  @override
  Future<Map<int, Object?>?> rawDps(String deviceId) {
    final delayed = hold;
    hold = null;
    return delayed?.future ?? super.rawDps(deviceId);
  }

  void report(Object raw, {bool changeCache = true}) {
    if (changeCache) rawDpsByDevice[id] = {MowerDp.mowSchedule: raw};
    pushDeviceUpdate(
      DeviceUpdate.changed(
        device(),
        changedDps: {MowerDp.mowSchedule},
        reportedDps: {MowerDp.mowSchedule: raw},
      ),
    );
  }

  void receipt(int code, int seq) => pushDeviceUpdate(
    DeviceUpdate.changed(
      device(),
      changedDps: {MowerDp.commandResults},
      reportedDps: {
        MowerDp.commandResults: jsonEncode({
          'dp': 101,
          'code': code,
          'seq': seq,
          'val': 1,
        }),
      },
    ),
  );
}

Future<FlowerpotState> setup(Repo repo, {bool bind = true}) async {
  final state = FlowerpotState(repository: repo);
  addTearDown(state.dispose);
  await state.initialize();
  await state.refreshDevices();
  state.pauseDeviceWatch();
  if (bind) {
    await MowerDevice.instance.bind(state, owner: Object(), deviceId: id);
  }
  return state;
}

Future<void> drain(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(MowerDevice.instance.resetForTest);
  tearDown(MowerDevice.instance.resetForTest);
  for (final allEnabled in [true, false]) {
    for (final base64 in [false, true]) {
      testWidgets('合成初始DP：全启用=$allEnabled，base64=$base64，七天不被APP默认改写', (
        tester,
      ) async {
        final repo = Repo()
          ..rawDpsByDevice[id] = {
            101: base64
                ? base64Encode(frame(allEnabled))
                : TuyaRaw.hex(frame(allEnabled)),
          };
        await setup(repo);
        final days = MowerDevice.instance.schedule;
        for (var uiDay = 0; uiDay < 7; uiDay++) {
          expect(days[uiDay].slotOne?.enabled, allEnabled || uiDay != 1);
          expect(days[uiDay].edge, allEnabled || [0, 3, 5].contains(uiDay));
        }
        expect(repo.publishedDps, isEmpty, reason: '加载不自动写计划');
      });
    }
  }
  testWidgets('保存后SDK成功仍显示原DP，真实不同回显优先于下发草稿', (tester) async {
    final repo = Repo()..rawDpsByDevice[id] = {101: TuyaRaw.hex(frame(false))};
    final state = await setup(repo);
    final d = MowerDevice.instance;
    final original = d.schedule;
    final received = d.scheduleRaw;
    d.setSchedule(state, MowerScheduleCodec.decode(frame(true)));
    expect(identical(d.schedule, original), isTrue);
    expect(d.scheduleRaw, received);
    await drain(tester);
    expect(d.schedulePending, isTrue);
    final sent = repo.publishedDps.single.$2;
    expect(sent.keys, [101]);
    expect(sent[101], TuyaRaw.hex(frame(true)));
    expect((sent[101] as String).length, 176);
    expect(d.scheduleSentRaw, frame(true));
    expect(identical(d.schedule, original), isTrue);
    // Firmware's actual reply disagrees with intent; app must show the reply.
    repo.report(TuyaRaw.hex(frame(false)), changeCache: false);
    await drain(tester);
    expect(d.schedule[1].slotOne?.enabled, isFalse);
    expect(d.schedule[2].edge, isFalse);
    expect(d.schedulePending, isFalse);
    expect(d.scheduleRawSource, '设备上报');
    expect(d.scheduleSentRaw, frame(true));
    d.resetForTest();
  });
  testWidgets('等待DP回读时拦重复草稿，避免旧周计划覆盖另一日', (tester) async {
    final repo = Repo()..rawDpsByDevice[id] = {101: TuyaRaw.hex(frame(false))};
    final state = await setup(repo);
    final d = MowerDevice.instance;
    d.setSchedule(state, MowerScheduleCodec.decode(frame(true)));
    d.setSchedule(state, MowerScheduleCodec.decode(frame(false)));
    await drain(tester);
    expect(repo.publishedDps, hasLength(1));
    d.resetForTest();
  });
  for (final fails in [false, true]) {
    testWidgets('SDK失败=$fails/回显超时，不伪造新修边或清旧计划', (tester) async {
      final repo = Repo()
        ..rawDpsByDevice[id] = {101: TuyaRaw.hex(frame(false))};
      if (fails) {
        repo.publishError = const TuyaException('sdk_fail', 'test error');
      }
      final state = await setup(repo);
      final d = MowerDevice.instance;
      d.setSchedule(state, MowerScheduleCodec.decode(frame(true)));
      await drain(tester);
      if (!fails) {
        await tester.pump(const Duration(seconds: 6));
        await drain(tester);
      }
      expect(d.schedule[1].slotOne?.enabled, isFalse);
      expect(d.schedule[2].edge, isFalse);
      expect(d.schedulePending, isFalse);
      d.resetForTest();
    });
  }
  for (final code in [0, 65, 66]) {
    testWidgets('DP115计划回执$code：成功等待DP101，拒绝有提示且不改变计划', (tester) async {
      final repo = Repo()
        ..rawDpsByDevice[id] = {101: TuyaRaw.hex(frame(false))};
      final state = await setup(repo);
      final d = MowerDevice.instance;
      final failures = <String>[];
      final sub = d.failures.listen(failures.add);
      d.setSchedule(state, MowerScheduleCodec.decode(frame(true)));
      await drain(tester);
      repo.receipt(code, 1);
      await drain(tester);
      expect(d.scheduleCommandResult?.code, code);
      expect(d.schedule[2].edge, isFalse);
      expect(d.schedulePending, code == 0);
      expect(failures, code == 0 ? isEmpty : hasLength(1));
      expect(repo.publishedDps, hasLength(1));
      unawaited(sub.cancel());
      d.resetForTest();
    });
  }
  testWidgets('旧DP115不误认本次，实际拒绝才结束等待', (tester) async {
    final repo = Repo()
      ..rawDpsByDevice[id] = {
        101: TuyaRaw.hex(frame(false)),
        115: '{"code":65,"seq":9,"dp":101}',
      };
    final state = await setup(repo);
    final d = MowerDevice.instance;
    d.setSchedule(state, MowerScheduleCodec.decode(frame(true)));
    await drain(tester);
    repo.receipt(65, 9);
    await drain(tester);
    expect(d.schedulePending, isTrue);
    expect(d.scheduleCommandResult, isNull);
    repo.receipt(65, 10);
    await drain(tester);
    expect(d.schedulePending, isFalse);
    d.resetForTest();
  });
  testWidgets('89字节错误包不更新计划，后续合法88字节恢复解析', (tester) async {
    final repo = Repo()..rawDpsByDevice[id] = {101: TuyaRaw.hex(frame(false))};
    await setup(repo);
    final d = MowerDevice.instance;
    final original = d.schedule;
    repo.report(TuyaRaw.hex([...frame(true), 0]));
    await drain(tester);
    expect(identical(d.schedule, original), isTrue);
    expect(d.scheduleRaw, hasLength(89));
    repo.report(base64Encode(frame(true)));
    await drain(tester);
    expect(d.schedule.every((day) => day.edge), isTrue);
  });
  testWidgets('初始快照迟到不能覆盖新的DP101上报', (tester) async {
    final repo = Repo()..rawDpsByDevice[id] = {101: TuyaRaw.hex(frame(false))};
    final state = await setup(repo, bind: false);
    final hold = Completer<Map<int, Object?>?>();
    repo.hold = hold;
    final binding = MowerDevice.instance.bind(
      state,
      owner: Object(),
      deviceId: id,
    );
    await drain(tester);
    repo.report(TuyaRaw.hex(frame(true)));
    await drain(tester);
    expect(MowerDevice.instance.schedule.every((day) => day.edge), isTrue);
    hold.complete({101: TuyaRaw.hex(frame(false))});
    await drain(tester);
    await binding;
    expect(MowerDevice.instance.schedule.every((day) => day.edge), isTrue);
    expect(MowerDevice.instance.scheduleRaw, frame(true));
  });
  for (final slot in [
    const MowerScheduleSlot(startMinutes: -10, endMinutes: 60),
    const MowerScheduleSlot(startMinutes: 1400, endMinutes: 1500),
    const MowerScheduleSlot(startMinutes: 600, endMinutes: 609),
    const MowerScheduleSlot(startMinutes: 720, endMinutes: 540),
  ]) {
    testWidgets('非法启用时段${slot.startMinutes}-${slot.endMinutes}不发清空指令', (
      tester,
    ) async {
      final repo = Repo()
        ..rawDpsByDevice[id] = {101: TuyaRaw.hex(frame(false))};
      final state = await setup(repo);
      final next = List<MowerScheduleDay>.of(MowerDevice.instance.schedule);
      next[4] = MowerScheduleDay(slotOne: slot);
      MowerDevice.instance.setSchedule(state, next);
      await drain(tester);
      expect(repo.publishedDps, isEmpty);
    });
  }
  testWidgets('少于七天不发送，避免全量写入清掉其它日期', (tester) async {
    final repo = Repo()..rawDpsByDevice[id] = {101: TuyaRaw.hex(frame(false))};
    final state = await setup(repo);
    MowerDevice.instance.setSchedule(state, [
      const MowerScheduleDay(edge: true),
    ]);
    await drain(tester);
    expect(repo.publishedDps, isEmpty);
  });
  test('设备已报默认时间的停用时段，改修边/复制不能清空起止', () {
    final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
    week[4] = const MowerScheduleDay(
      slotOne: MowerPlanDraft.defaultOne,
      slotTwo: MowerPlanDraft.defaultTwo,
    );
    final draft = MowerPlanDraft.forDay(
      4,
      week,
    ).copyWith(edge: true, copyWeek: true);
    final raw = MowerScheduleCodec.encodeAll(draft.day0);
    for (var group = 1; group <= 7; group++) {
      expect(raw.sublist(group * 11, group * 11 + 11), [
        0xfe,
        1,
        0xd0,
        2,
        0x48,
        3,
        0x38,
        4,
        1,
        0,
        0,
      ]);
    }
    final empty = MowerPlanDraft.forDay(
      1,
      List.filled(7, const MowerScheduleDay()),
    );
    expect(empty.day0.slotOne, isNull);
    expect(empty.day0.slotTwo, isNull);
  });
}
