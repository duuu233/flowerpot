import 'dart:async';

import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/mower_ui.dart';
import 'package:flowerpot/src/features/mower/mower_work_countdown.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_status_card.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';
import '../../support/plant_catalog.dart';

/// 工作时间倒计时（2026-10-22 产品定稿，2026-10-24 起点改为时间设置弹窗确认）：APP 本机按「确认时刻 + 小时数」计算，
/// 状态胶囊里「图标 + 剩余时间」按分钟递减；不暂停、不隐藏，到 0 停在「0分」；重设即重跑。
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

  testWidgets('确认时间设置即开始计时，重设按新时长重跑，重进页面从本机读回', (tester) async {
    final repository = _MowerRepository()
      ..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    expect(device.workEndsAt, isNull);

    var now = DateTime(2026, 10, 22, 9);
    device.clock = () => now;
    device.restartWorkCountdown(state, 3);
    expect(device.workEndsAt, DateTime(2026, 10, 22, 12));

    now = DateTime(2026, 10, 22, 10, 30);
    device.restartWorkCountdown(state, 2);
    expect(device.workEndsAt, DateTime(2026, 10, 22, 12, 30), reason: '重设即重跑');

    // 「继续」不弹时间设置，倒计时不变。
    device.release(_owner);
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    await tester.pump();
    expect(device.workEndsAt, DateTime(2026, 10, 22, 12, 30));
    device.resetForTest();
  });

  testWidgets('DP119下发本身不动倒计时：发出去不重计，没发出去也不撤销', (tester) async {
    final repository = _MowerRepository()
      ..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await device.bind(state, owner: _owner, deviceId: _mowerId);
    device.clock = () => DateTime(2026, 10, 22, 9);
    expect(await _sent(tester, device.setOperatingTime(state, 3)), isTrue);
    expect(device.workEndsAt, isNull);
    device.restartWorkCountdown(state, 2);
    repository.publishError = const TuyaException('sdk_fail', '指令没有发出去');
    expect(await _sent(tester, device.setOperatingTime(state, 3)), isFalse);
    expect(device.workEndsAt, DateTime(2026, 10, 22, 11));
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

SmartPlanterDevice _mower() => SmartPlanterDevice(
  id: _mowerId,
  productId: MowerDp.productId,
  name: '割草机',
  online: true,
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
  _MowerRepository() : super(latency: Duration.zero, seedDevice: false);

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    _mower(),
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
