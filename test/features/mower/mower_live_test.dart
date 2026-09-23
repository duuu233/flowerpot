import 'dart:async';

import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_raw.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';
import '../../support/plant_catalog.dart';

/// 割草机接真机（2026-09-21）：下发走涂鸦 SDK、上报按原始 DP 值解、没回显就回弹。
///
/// 用 testWidgets：回弹是 5 秒计时，假时钟下 `tester.pump(duration)` 一步跳过去。
/// ⚠️ 单例：每条用例开头、结尾都 `resetForTest`，结尾那次顺带取消还没到点的回弹计时器
/// （测试框架在用例体结束时就检查有没有挂着的 Timer，比 tearDown 早）。
void main() {
  setUp(MowerDevice.instance.resetForTest);

  testWidgets('绑真机：设备快照里已上报的 DP 全部按原始值解出来', (tester) async {
    final repository = _MowerRepository();
    final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
    week[1] = const MowerScheduleDay(
      slotOne: MowerScheduleSlot(startMinutes: 540, endMinutes: 600),
      edge: true,
    );
    repository.rawDpsByDevice[_mowerId] = <int, Object?>{
      MowerDp.switchGo: true,
      MowerDp.mode: 'spot',
      MowerDp.status: 'spot_mowing',
      MowerDp.battery: 55,
      MowerDp.fault: 1 << 3,
      MowerDp.chargingStatus: 'charging',
      MowerDp.coverStatus: false,
      // raw 型：SDK 交给 App 的是十六进制串
      MowerDp.mowSchedule: TuyaRaw.hex(MowerScheduleCodec.encodeByDay(week)),
      MowerDp.zoneConfig: TuyaRaw.hex(
        MowerZoneCodec.encode(const <MowerZoneConfig>[
          MowerZoneConfig(index: 2, percent: 40, meters: 150),
        ]),
      ),
      MowerDp.rainDelaySwitch: true,
      MowerDp.rainDetectEnable: false,
      MowerDp.rainDelay: 30,
      MowerDp.timeSyncEnable: true,
      MowerDp.timezone: 'UTCB9',
      MowerDp.dstEnable: true,
      MowerDp.deviceTime: '1790000000',
      MowerDp.language: 'german',
    };
    final state = await _state(repository);
    final device = MowerDevice.instance;

    await device.bind(state, owner: _owner, deviceId: _mowerId);

    expect(device.isLive, isTrue);
    expect(device.switchGo, isTrue);
    expect(device.mode, MowerMode.spot);
    expect(device.status, MowerStatus.spotMowing);
    expect(device.battery, 55);
    // 2026-09-23 口径：上报值就是文案编号（快照里给的是 1<<3 = 8 → 编号 8）
    expect(device.faultMessage, MowerFault.messages[8]);
    expect(device.charging, MowerChargingStatus.charging);
    expect(device.coverClosed, isFalse);
    expect(device.schedule[1].slotOne?.startMinutes, 540);
    expect(device.schedule[1].edge, isTrue);
    expect(device.schedule[0].isEmpty, isTrue);
    expect(device.zones[1].percent, 40);
    expect(device.zones[1].meters, 150);
    expect(device.zones[0].percent, 0);
    expect(device.rainDelaySwitch, isTrue);
    expect(device.rainDetectEnable, isFalse);
    expect(device.rainDelayMinutes, 30);
    expect(device.timeSyncEnable, isTrue);
    expect(device.timezoneIndex, MowerTimezone.zeroIndex + 9);
    expect(device.dstEnable, isTrue);
    expect(device.deviceTimeUtcSeconds, '1790000000');
    expect(device.language, MowerLanguage.german);
    device.resetForTest();
  });

  testWidgets('真机没报过计划时是空周，不再画稿子上的演示色块', (tester) async {
    final repository = _MowerRepository()..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);

    await MowerDevice.instance.bind(state, owner: _owner, deviceId: _mowerId);

    expect(
      MowerDevice.instance.schedule.every((day) => day.isEmpty),
      isTrue,
    );
    expect(MowerDevice.instance.zones.map((zone) => zone.percent), <int>[0, 0, 0, 0, 0]);
    MowerDevice.instance.resetForTest();
  });

  testWidgets('真机下发：经 SDK 发给这台设备；raw 型发十六进制串；多条按调用顺序发', (tester) async {
    final repository = _MowerRepository()..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await device.bind(state, owner: _owner, deviceId: _mowerId);

    device.setMode(state, MowerMode.smart);
    device.setTimeSync(state, enable: true, timezoneIndex: 20, dst: false);
    const zones = <MowerZoneConfig>[
      MowerZoneConfig(index: 1, percent: 50, meters: 20),
    ];
    device.setZones(state, zones);
    await tester.pump();

    final sent = repository.publishedDps;
    expect(sent.every((entry) => entry.$1 == _mowerId), isTrue);
    expect(sent.map((entry) => entry.$2.keys.single).toList(), <int>[
      MowerDp.mode,
      // 时间同步 V2.2 §9.6 的顺序：106 → 107 → 108 → 114
      MowerDp.timeSyncEnable,
      MowerDp.timezone,
      MowerDp.dstEnable,
      MowerDp.deviceTime,
      MowerDp.zoneConfig,
    ]);
    expect(sent[0].$2[MowerDp.mode], 'smart');
    expect(sent[2].$2[MowerDp.timezone], 'UTCB8');
    expect(
      sent.last.$2[MowerDp.zoneConfig],
      TuyaRaw.hex(MowerZoneCodec.encode(zones)),
    );
    device.resetForTest();
  });

  testWidgets('下发后 5 秒没有回显：按设备当前值画回去（V2.2 §1 超时回弹）', (tester) async {
    final repository = _MowerRepository()
      ..rawDpsByDevice[_mowerId] = <int, Object?>{MowerDp.rainDetectEnable: false};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await device.bind(state, owner: _owner, deviceId: _mowerId);

    device.setRain(state, detectEnable: true, delaySwitch: false, delayMinutes: 0);
    await tester.pump();
    expect(device.rainDetectEnable, isTrue, reason: '先本地回显');

    await tester.pump(MowerDevice.echoTimeout);
    await tester.pump();
    expect(device.rainDetectEnable, isFalse, reason: '设备没回显 = 拒了，画回设备的值');
    device.resetForTest();
  });

  testWidgets('回显到了就以回显为准，到点也不回弹', (tester) async {
    final repository = _MowerRepository()
      ..rawDpsByDevice[_mowerId] = <int, Object?>{MowerDp.rainDetectEnable: false};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    await device.bind(state, owner: _owner, deviceId: _mowerId);

    device.setRain(state, detectEnable: true, delaySwitch: false, delayMinutes: 0);
    await tester.pump();
    // 设备收下了，报上来 104=true。
    repository.rawDpsByDevice[_mowerId]![MowerDp.rainDetectEnable] = true;
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(_mower(), changedDps: <int>{MowerDp.rainDetectEnable}),
    );
    await tester.pump();
    await tester.pump(MowerDevice.echoTimeout);
    await tester.pump();

    expect(device.rainDetectEnable, isTrue);
    device.resetForTest();
  });

  testWidgets('设备离线：指令不发，页面收到一句提示，界面画回设备的值', (tester) async {
    final repository = _MowerRepository(online: false)
      ..rawDpsByDevice[_mowerId] = <int, Object?>{MowerDp.switchGo: false};
    final state = await _state(repository);
    final device = MowerDevice.instance;
    final failures = <String>[];
    final sub = device.failures.listen(failures.add);
    await device.bind(state, owner: _owner, deviceId: _mowerId);

    device.setSwitch(state, on: true);
    await tester.pump();
    await tester.pump();

    expect(repository.publishedDps, isEmpty, reason: '离线门禁在发之前就拦下了');
    expect(failures, <String>['割草机已离线，指令没有发出去']);
    expect(device.switchGo, isFalse);
    await sub.cancel();
    device.resetForTest();
  });

  testWidgets('割草机的上报不走花盆那套：列表那一行照样更新', (tester) async {
    final repository = _MowerRepository()..rawDpsByDevice[_mowerId] = <int, Object?>{};
    final state = await _state(repository);
    expect(state.isMowerDevice(state.deviceById(_mowerId)!), isTrue);

    repository.pushDeviceUpdate(DeviceUpdate.changed(_mower(online: false)));
    await tester.pump();

    expect(state.deviceById(_mowerId)!.online, isFalse);
  });

  testWidgets('搜索页：割草机的产品 ID 也算本 App 的产品，扫到就列出来', (tester) async {
    final repository = _MowerRepository();
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    expect(await state.startBleDiscovery(), isTrue);

    repository
      ..pushBleDevice(
        const BleDevice(
          uuid: 'uuid-mower',
          name: '',
          mac: 'AA:BB:CC:00:00:31',
          productId: MowerDp.productId,
          rssi: -45,
          bound: false,
          supportWifiList: true,
        ),
      )
      ..pushBleDevice(
        const BleDevice(
          uuid: 'uuid-other',
          name: '别人的',
          mac: 'AA:BB:CC:00:00:32',
          productId: 'pid-other',
          rssi: -30,
          bound: false,
          supportWifiList: false,
        ),
      );
    await tester.pump();

    expect(state.bleDevices.map((item) => item.uuid), <String>['uuid-mower']);
    await state.stopBleDiscovery();
  });
}

const String _mowerId = 'mower-1';
final Object _owner = Object();

SmartPlanterDevice _mower({bool online = true}) => SmartPlanterDevice(
  id: _mowerId,
  productId: MowerDp.productId,
  name: '割草机',
  online: online,
  signal: 80,
  battery: 0,
  charging: false,
  boundAt: DateTime(2026, 9, 21),
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
  macAddress: 'AA:BB:CC:00:00:31',
);

/// 设备列表里只有一台割草机；其余照 Mock。
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
  return state;
}
