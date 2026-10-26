import 'dart:async';

import 'package:flowerpot/src/features/mower/mower_current_plan.dart';
import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/mower_ui.dart';
import 'package:flowerpot/src/features/mower/mower_work_countdown.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_status_card.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';
import '../../support/plant_catalog.dart';

/// 工作时间倒计时（2026-10-26 起以设备 DP121 schedule_current 为准）：终点 = 收到新帧的本机时刻 +
/// `et − now`，状态胶囊里「图标 + 剩余时间」按分钟递减，到 0 停在「0分」；新帧重设基准，同一帧不动；
/// 无计划不显示；DP119 下发不再计时。待机、休眠、已关机、离线时首页隐藏（2026-10-24 产品），终点保留。
void main() {
  setUp(MowerDevice.instance.resetForTest);

  test('剩余分钟向上取整，过点停在0；文案为X小时Y分/Y分', () {
    final end = DateTime(2026, 10, 22, 12);
    expect(
      MowerWorkCountdown.remainingMinutes(end, DateTime(2026, 10, 22, 10)),
      120,
    );
    expect(
      MowerWorkCountdown.remainingMinutes(
        end,
        DateTime(2026, 10, 22, 10, 0, 30),
      ),
      120,
    );
    expect(
      MowerWorkCountdown.remainingMinutes(end, DateTime(2026, 10, 22, 10, 1)),
      119,
    );
    expect(
      MowerWorkCountdown.remainingMinutes(end, DateTime(2026, 10, 22, 13)),
      0,
    );
    expect(MowerWorkCountdown.label(120), '2小时0分');
    expect(MowerWorkCountdown.label(119), '1小时59分');
    expect(MowerWorkCountdown.label(45), '45分');
    expect(MowerWorkCountdown.label(0), '0分');
    expect(
      MowerWorkCountdown.untilNextTick(end, DateTime(2026, 10, 22, 10, 0, 20)),
      const Duration(seconds: 20),
    );
    expect(MowerWorkCountdown.untilNextTick(end, end), isNull);
  });

  testWidgets('状态胶囊跟在工作状态后面按分钟递减，到点停在0分不隐藏', (tester) async {
    var now = DateTime(2026, 10, 22, 10);
    final end = now.add(const Duration(hours: 2));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MowerStatusCard(
              tone: MowerPowerState.idle,
              percent: 80,
              statusLabel: '回桩',
              workEndsAt: end,
              now: () => now,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('回桩'), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.text('2小时0分'), findsOneWidget);

    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('1小时59分'), findsOneWidget);

    now = now.add(const Duration(minutes: 75));
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('44分'), findsOneWidget);

    now = end.add(const Duration(hours: 3));
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('0分'), findsOneWidget);
    expect(find.byKey(const Key('mower-work-countdown')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没设置过工作时间：胶囊里不显示倒计时', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MowerStatusCard(
            tone: MowerPowerState.idle,
            percent: 80,
            statusLabel: '待机',
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('mower-work-countdown')), findsNothing);
  });

  test('DP121 解析：u32 三字段齐全才认，剩余 max(0, et−now)，计划身份只看 st/et', () {
    final plan = MowerCurrentPlan.parse(
      '{"st":1761451200,"et":1761465600,"now":1761454500}',
    )!;
    expect(plan.active, isTrue);
    expect(plan.remainingSeconds, 1761465600 - 1761454500);
    expect(
      MowerCurrentPlan.parse(<String, Object?>{'st': 1, 'et': 100, 'now': 50})
          ?.remainingSeconds,
      50,
      reason: '平台也可能直接给 Map',
    );

    final idle = MowerCurrentPlan.parse('{"st":0,"et":0,"now":1761454500}')!;
    expect(idle.active, isFalse);
    expect(idle.remainingSeconds, 0);
    expect(MowerWorkCountdown.endsAt(idle, DateTime(2026, 10, 26)), isNull);

    final over = MowerCurrentPlan.parse('{"st":100,"et":200,"now":500}')!;
    expect(over.remainingSeconds, 0, reason: '过了结束时间停在 0');

    for (final bad in <Object?>[
      null,
      '',
      'not json',
      '[1,2,3]',
      '{"st":1,"et":2}',
      '{"st":-1,"et":2,"now":1}',
      '{"st":1,"et":"2","now":1}',
      '{"st":1,"et":2.5,"now":1}',
      '{"st":1,"et":4294967296,"now":1}',
    ]) {
      expect(MowerCurrentPlan.parse(bad), isNull, reason: '$bad');
    }

    final next = MowerCurrentPlan.parse(
      '{"st":1761451200,"et":1761465600,"now":1761454560}',
    )!;
    expect(next.samePlan(plan), isTrue, reason: 'now 变了不算计划变');
    expect(next.sameFrame(plan), isFalse);
  });

  testWidgets('DP121：按收到时刻+et−now计时，新帧重设基准，同一帧快照不动，无计划收起', (
    tester,
  ) async {
    final repository = _MowerRepository()
      ..rawDpsByDevice[_mowerId] = <int, Object?>{
        MowerDp.scheduleCurrent: '{"st":1000,"et":8200,"now":1000}',
      };
    final state = await _state(repository);
    final device = MowerDevice.instance;
    var now = DateTime(2026, 10, 26, 9);
    device.clock = () => now;
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    await tester.pump();
    expect(device.currentPlan?.endSeconds, 8200);
    expect(device.workEndsAt, DateTime(2026, 10, 26, 11), reason: '剩余 2 小时');

    // 同一帧被整包快照反复刷进来：不能拿旧的 now 把终点往后推。
    now = DateTime(2026, 10, 26, 9, 10);
    repository.pushDeviceUpdate(DeviceUpdate.changed(_mower()));
    await tester.pump();
    await tester.pump();
    expect(device.workEndsAt, DateTime(2026, 10, 26, 11));

    // 兜底新帧：机器时间走了 30 分钟（手机只走了 10 分钟），按机器的剩余 1.5 小时重设。
    _report(repository, '{"st":1000,"et":8200,"now":2800}');
    await tester.pump();
    await tester.pump();
    expect(device.workEndsAt, DateTime(2026, 10, 26, 10, 40));

    // 换了计划（重新启动 1 小时）：按新计划重算。
    now = DateTime(2026, 10, 26, 9, 20);
    _report(repository, '{"st":3400,"et":7000,"now":3400}');
    await tester.pump();
    await tester.pump();
    expect(device.workEndsAt, DateTime(2026, 10, 26, 10, 20));

    // 认不出的帧丢掉，保留上一帧。
    _report(repository, '{"st":3400}');
    await tester.pump();
    await tester.pump();
    expect(device.workEndsAt, DateTime(2026, 10, 26, 10, 20));

    // 任务结束 / 取消：设备报无计划，倒计时收起。
    _report(repository, '{"st":0,"et":0,"now":3500}');
    await tester.pump();
    await tester.pump();
    expect(device.currentPlan?.active, isFalse);
    expect(device.workEndsAt, isNull);
    expect(device.visibleWorkEndsAt, isNull);
    device.resetForTest();
  });

  testWidgets('DP119下发成功不再开始计时；设备没报DP121不显示', (tester) async {
    final repository = _MowerRepository()
      ..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    expect(await _sent(tester, device.setOperatingTime(state, 3)), isTrue);
    expect(device.workEndsAt, isNull);
    expect(device.currentPlan, isNull);
    device.resetForTest();
  });

  testWidgets('待机、休眠、已关机时首页隐藏倒计时，终点保留，回到其它状态接着显示', (tester) async {
    final repository = _MowerRepository()
      ..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    final end = DateTime(2026, 10, 24, 12);
    device.workEndsAt = end;

    for (final shown in <MowerStatus>[
      MowerStatus.mowing,
      MowerStatus.paused,
      MowerStatus.gotoCharge,
      MowerStatus.waitCharge,
      MowerStatus.fault,
      MowerStatus.stop,
    ]) {
      device.status = shown;
      expect(device.visibleWorkEndsAt, end, reason: shown.code);
    }
    for (final hidden in <MowerStatus>[
      MowerStatus.standby,
      MowerStatus.sleep,
    ]) {
      device.status = hidden;
      expect(device.visibleWorkEndsAt, isNull, reason: hidden.code);
      expect(device.workEndsAt, end, reason: '只隐藏，不清终点');
    }

    device.status = MowerStatus.mowing;
    repository.rawDpsByDevice[_mowerId]![MowerDp.shutdownReport] = true;
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(
        _mower(),
        changedDps: <int>{MowerDp.shutdownReport},
      ),
    );
    await tester.pump();
    expect(device.shutdown, isTrue);
    expect(device.visibleWorkEndsAt, isNull, reason: 'DP113 已关机');

    repository.rawDpsByDevice[_mowerId]![MowerDp.shutdownReport] = false;
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(
        _mower(),
        changedDps: <int>{MowerDp.shutdownReport},
      ),
    );
    await tester.pump();
    expect(device.shutdown, isFalse);
    device.status = MowerStatus.mowing;
    expect(device.visibleWorkEndsAt, end);
    device.resetForTest();
  });

  testWidgets('离线时首页隐藏倒计时', (tester) async {
    final repository = _MowerRepository(online: false)
      ..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    device
      ..workEndsAt = DateTime(2026, 10, 24, 12)
      ..status = MowerStatus.mowing;
    expect(device.online, isFalse);
    expect(device.visibleWorkEndsAt, isNull);
    device.resetForTest();
  });
}

/// 下发要经过 Mock 的零延时计时器，假时钟下得 pump 才会走完。
Future<bool?> _sent(WidgetTester tester, Future<bool> pending) async {
  bool? value;
  unawaited(pending.then((sent) => value = sent));
  await tester.pump();
  await tester.pump();
  return value;
}

/// 模拟一条只带 DP121 的实时上报。
void _report(_MowerRepository repository, String raw) {
  repository.rawDpsByDevice[_mowerId]![MowerDp.scheduleCurrent] = raw;
  repository.pushDeviceUpdate(
    DeviceUpdate.changed(
      _mower(),
      changedDps: <int>{MowerDp.scheduleCurrent},
      reportedDps: <int, Object?>{MowerDp.scheduleCurrent: raw},
    ),
  );
}

const String _mowerId = 'mower-countdown';
final Object _owner = Object();

SmartPlanterDevice _mower({bool online = true}) => SmartPlanterDevice(
  id: _mowerId,
  productId: MowerDp.productId,
  name: '割草机',
  online: online,
  signal: 80,
  battery: 0,
  charging: false,
  boundAt: DateTime(2026, 10, 22),
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
  firmwareVersion: '1.0.0',
  macAddress: 'AA:BB:CC:00:00:41',
);

class _MowerRepository extends MockTuyaRepository {
  _MowerRepository({this.online = true})
    : super(latency: Duration.zero, seedDevice: false);

  final bool online;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    _mower(online: online),
  ];
}

Future<FlowerpotState> _state(MockTuyaRepository repository) async {
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.initialize();
  await state.refreshDevices();
  state.pauseDeviceWatch();
  return state;
}
