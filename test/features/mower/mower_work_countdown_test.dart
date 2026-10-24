import 'dart:async';

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

/// 工作时间倒计时（2026-10-22 产品定稿）：APP 本机按「DP119 下发成功时刻 + 小时数」计算，
/// 状态胶囊里「图标 + 剩余时间」按分钟递减；不暂停，到 0 停在「0分」；重设即重跑。
/// 待机、休眠、已关机、离线时首页隐藏（2026-10-24 产品），终点保留。
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
              statusLabel: '回桩中',
              workEndsAt: end,
              now: () => now,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('回桩中'), findsOneWidget);
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

  testWidgets('DP119下发成功即开始计时，重设按新时长重跑，重进页面从本机读回', (tester) async {
    final repository = _MowerRepository()
      ..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    expect(device.workEndsAt, isNull);

    var now = DateTime(2026, 10, 22, 9);
    device.clock = () => now;
    expect(await _sent(tester, device.setOperatingTime(state, 3)), isTrue);
    expect(device.workEndsAt, DateTime(2026, 10, 22, 12));

    now = DateTime(2026, 10, 22, 10, 30);
    expect(await _sent(tester, device.setOperatingTime(state, 2)), isTrue);
    expect(device.workEndsAt, DateTime(2026, 10, 22, 12, 30), reason: '重设即重跑');

    // 「继续」只发 DP2，不重写 DP119，倒计时不变。
    device.release(_owner);
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    await tester.pump();
    expect(device.workEndsAt, DateTime(2026, 10, 22, 12, 30));
    device.resetForTest();
  });

  testWidgets('DP119没发出去（离线）不开始计时', (tester) async {
    final repository = _MowerRepository(online: false)
      ..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    expect(await _sent(tester, device.setOperatingTime(state, 3)), isFalse);
    expect(device.workEndsAt, isNull);
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

  testWidgets('另一台设备没在本机设置过：不显示，不借用别的设备的终点', (tester) async {
    final repository = _MowerRepository()
      ..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await MowerWorkCountdown.save('other-mower', DateTime(2026, 10, 22, 12));
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    await tester.pump();
    expect(device.workEndsAt, isNull);
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
