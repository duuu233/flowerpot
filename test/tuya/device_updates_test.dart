import 'dart:async';
import '../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _methodChannel = 'test/tuya';
const _eventChannel = 'test/tuya_events';

/// One planter as the native bridge hands it over.
Map<Object?, Object?> _deviceMap() => <Object?, Object?>{
  'deviceId': 'dev-1',
  'productId': 'orhqsdjyigmh8bwa',
  'name': '客厅的绿意',
  'online': true,
  'activeTime': 1723000000,
  'mac': 'A4:C1:38:7B:2D:10',
  'dps': <Object?, Object?>{
    '103': 64, // battery_level
    '105': 30, // water_level
    '106': 55, // soil_moist
    '112': 246, // air_temperature, tenths
    '122': true, // vibration_switch
  },
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  late MethodChannelTuyaRepository repository;

  /// Pushes one event the way the native device listener would.
  Future<void> emit(Object? event) async {
    ServicesBinding.instance.channelBuffers.push(
      _eventChannel,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(_methodChannel),
      (call) async =>
          call.method == 'getDevices' ? <Object?>[_deviceMap()] : null,
    );
    // The event channel answers its own listen/cancel calls.
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannel),
      (call) async => null,
    );
    repository = MethodChannelTuyaRepository(
      channel: const MethodChannel(_methodChannel),
      events: const EventChannel(_eventChannel),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(_methodChannel),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannel),
      null,
    );
  });

  test('割草DP101给原生桥：单一字符串键、176位hex，无base64二次编码', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(const MethodChannel(_methodChannel), (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    const group = '1C02D00248033804010100';
    final hex = '${List.filled(7, group).join()}0000000000000000000000';
    await repository.publishDpsWithMode('dev-1', {
      101: hex,
    }, mode: 'ThingDevicePublishModeInternet');
    expect(calls, hasLength(1));
    expect(calls.single.method, 'publishDpsWithMode');
    expect(calls.single.arguments, {
      'deviceId': 'dev-1',
      'dps': {'101': hex},
      'mode': 'ThingDevicePublishModeInternet',
    });
    expect(hex.length, 176);
  });
  test('原始DP每次读取SDK当前快照，不用APP旧清单值且允许正常下降', () async {
    await repository.getDevices();
    var level = 99;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(const MethodChannel(_methodChannel), (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'deviceSnapshot') {
        return {
          ..._deviceMap(),
          'dps': {'13': level},
        };
      }
      return null;
    });
    expect((await repository.rawDps('dev-1'))?[13], 99);
    level = 66;
    expect((await repository.rawDps('dev-1'))?[13], 66);
    expect(calls, ['deviceSnapshot', 'deviceSnapshot']);
  });

  test('SDK当前快照缺失不回退APP旧DP', () async {
    await repository.getDevices();
    expect(await repository.rawDps('dev-1'), isNull);
  });

  test('慢SDK快照不能盖过期间到达的实时DP', () async {
    final sub = repository.deviceUpdates.listen((_) {});
    addTearDown(sub.cancel);
    await repository.getDevices();
    final gate = Completer<Map<Object?, Object?>>();
    messenger.setMockMethodCallHandler(const MethodChannel(_methodChannel), (
      call,
    ) async {
      if (call.method == 'deviceSnapshot') return gate.future;
      return null;
    });
    final read = repository.rawDps('dev-1');
    await emit({
      'deviceId': 'dev-1',
      'dps': {'13': 99},
    });
    gate.complete({
      ..._deviceMap(),
      'dps': {'13': 66, '117': 'full'},
    });
    final result = await read;
    expect(result?[13], 99);
    expect(result?[117], 'full', reason: '一条推送不能使其它DP退回APP旧快照');
  });

  group('MethodChannelTuyaRepository.deviceUpdates', () {
    test('merges a reported DP into the last known device', () async {
      final updates = <DeviceUpdate>[];
      final subscription = repository.deviceUpdates.listen(updates.add);
      addTearDown(subscription.cancel);
      await repository.getDevices();

      await emit(<Object?, Object?>{
        'deviceId': 'dev-1',
        'dps': <Object?, Object?>{'105': 88},
      });

      expect(updates, hasLength(1));
      final device = updates.single.device!;
      expect(device.sensors.waterLevel, 88);
      // Everything the report left out survives the merge.
      expect(device.sensors.soilMoisture, 55);
      expect(device.sensors.airTemperature, 24.6);
      expect(device.battery, 64);
      expect(device.name, '客厅的绿意');
    });

    test(
      'reportedDps contains only this packet, including mower OTA errors',
      () async {
        final updates = <DeviceUpdate>[];
        final subscription = repository.deviceUpdates.listen(updates.add);
        addTearDown(subscription.cancel);
        await repository.getDevices();
        await emit(<Object?, Object?>{
          'deviceId': 'dev-1',
          'dps': <Object?, Object?>{'116': '7', '112': '1.1.0'},
        });
        expect(updates.last.reportedDps, <int, Object?>{
          116: '7',
          112: '1.1.0',
        });
        expect(updates.last.changedDps, <int>{116, 112});
        await emit(<Object?, Object?>{
          'deviceId': 'dev-1',
          'dps': <Object?, Object?>{'105': 88},
        });
        expect(updates.last.reportedDps, <int, Object?>{105: 88});
        expect(updates.last.reportedDps, isNot(contains(116)));
      },
    );

    test('device-info snapshot is not a fresh DP116 report', () async {
      final updates = <DeviceUpdate>[];
      final subscription = repository.deviceUpdates.listen(updates.add);
      addTearDown(subscription.cancel);
      await repository.getDevices();
      await emit(<Object?, Object?>{
        'deviceId': 'dev-1',
        'device': <Object?, Object?>{
          ..._deviceMap(),
          'dps': <Object?, Object?>{'116': '20'},
        },
      });
      expect(updates.last.changedDps, isEmpty);
      expect(updates.last.reportedDps, isEmpty);
    });

    test(
      'SDK online query updates DP merge cache without changing readings',
      () async {
        final updates = <DeviceUpdate>[];
        final subscription = repository.deviceUpdates.listen(updates.add);
        addTearDown(subscription.cancel);
        await repository.getDevices();
        messenger.setMockMethodCallHandler(
          const MethodChannel(_methodChannel),
          (call) async =>
              call.method == 'deviceOnlineStates' ? {'dev-1': false} : null,
        );
        expect(await repository.deviceOnlineStates(['dev-1']), {
          'dev-1': false,
        });
        await emit({
          'deviceId': 'dev-1',
          'dps': {'105': 88},
        });
        expect(updates.last.device!.online, isFalse);
        expect(updates.last.device!.sensors.waterLevel, 88);
        await emit({'deviceId': 'dev-1', 'online': true});
        expect(updates.last.device!.online, isTrue);
      },
    );

    test(
      'a newer online event protects the DP snapshot from an older query',
      () async {
        final updates = <DeviceUpdate>[];
        final subscription = repository.deviceUpdates.listen(updates.add);
        addTearDown(subscription.cancel);
        await repository.getDevices();
        final pending = Completer<Object?>();
        messenger.setMockMethodCallHandler(
          const MethodChannel(_methodChannel),
          (call) async =>
              call.method == 'deviceOnlineStates' ? pending.future : null,
        );
        final query = repository.deviceOnlineStates(['dev-1']);
        await Future<void>.delayed(Duration.zero);
        await emit({'deviceId': 'dev-1', 'online': false});
        pending.complete({'dev-1': true});
        await query;
        await emit({
          'deviceId': 'dev-1',
          'dps': {'105': 88},
        });
        expect(updates.last.device!.online, isFalse);
      },
    );

    test(
      'DP-only and network events do not promote an offline device',
      () async {
        final updates = <DeviceUpdate>[];
        final subscription = repository.deviceUpdates.listen(updates.add);
        addTearDown(subscription.cancel);
        await repository.getDevices();
        await emit({'deviceId': 'dev-1', 'online': false});
        await emit({
          'deviceId': 'dev-1',
          'networkAvailable': true,
          'dps': {'105': 88},
        });
        expect(updates.last.device!.online, isFalse);
        expect(updates.last.device!.sensors.waterLevel, 88);
      },
    );

    test('applies an online change without touching the readings', () async {
      final updates = <DeviceUpdate>[];
      final subscription = repository.deviceUpdates.listen(updates.add);
      addTearDown(subscription.cancel);
      await repository.getDevices();

      await emit(<Object?, Object?>{'deviceId': 'dev-1', 'online': false});

      expect(updates.single.device!.online, isFalse);
      expect(updates.single.device!.sensors.waterLevel, 30);
    });

    test('reports a removal and forgets the device', () async {
      final updates = <DeviceUpdate>[];
      final subscription = repository.deviceUpdates.listen(updates.add);
      addTearDown(subscription.cancel);
      await repository.getDevices();

      await emit(<Object?, Object?>{'deviceId': 'dev-1', 'removed': true});
      await emit(<Object?, Object?>{
        'deviceId': 'dev-1',
        'dps': <Object?, Object?>{'105': 10},
      });

      expect(updates, hasLength(1));
      expect(updates.single.removedId, 'dev-1');
    });

    test('ignores a report for a device this session never listed', () async {
      final updates = <DeviceUpdate>[];
      final subscription = repository.deviceUpdates.listen(updates.add);
      addTearDown(subscription.cancel);
      await repository.getDevices();

      await emit(<Object?, Object?>{
        'deviceId': 'unknown',
        'dps': <Object?, Object?>{'105': 10},
      });

      expect(updates, isEmpty);
    });

    test('decoded history follows the reported raw DP', () async {
      final updates = <DeviceUpdate>[];
      final subscription = repository.deviceUpdates.listen(updates.add);
      addTearDown(subscription.cancel);
      await repository.getDevices();
      expect(
        await repository.getHistory(
          'dev-1',
          SensorMetric.waterLevel,
          ReportRange.week,
        ),
        isEmpty,
      );

      // 年偏移 26, 月 8, 起始日 20, 点数 7, then seven daily averages.
      await emit(<Object?, Object?>{
        'deviceId': 'dev-1',
        'dps': <Object?, Object?>{'132': 'GggUBzI0ODw6NzM='},
      });

      final series = await repository.getHistory(
        'dev-1',
        SensorMetric.waterLevel,
        ReportRange.week,
      );
      expect(series, hasLength(7));
      // 水位历史以 mL/2 上报，显示时还原成 mL。
      expect(series.first, 100);
    });
  });

  test(
    'integer DP delta replaces string key and preserves other DPs',
    () async {
      final updates = <DeviceUpdate>[];
      final sub = repository.deviceUpdates.listen(updates.add);
      addTearDown(sub.cancel);
      await repository.getDevices();
      await emit({
        'deviceId': 'dev-1',
        'dps': {105: 88, 168: 0, 117: false},
      });
      expect(updates.last.device!.sensors.waterLevel, 88);
      expect(updates.last.device!.battery, 64);
      expect(updates.last.device!.settings.manualBrightness, 0);
      expect(updates.last.device!.settings.autoBrightness, isFalse);
      expect(updates.last.reportedDps, {105: 88, 168: 0, 117: false});
    },
  );

  test(
    'late list result cannot replace newer DP report in repository cache',
    () async {
      final updates = <DeviceUpdate>[];
      final sub = repository.deviceUpdates.listen(updates.add);
      addTearDown(sub.cancel);
      await repository.getDevices();
      final response = Completer<List<Object?>>();
      messenger.setMockMethodCallHandler(const MethodChannel(_methodChannel), (
        call,
      ) async {
        return call.method == 'getDevices' ? response.future : null;
      });
      final loading = repository.getDevices();
      await Future<void>.delayed(Duration.zero);
      await emit({
        'deviceId': 'dev-1',
        'dps': {'105': 92, '168': 0},
      });
      response.complete([_deviceMap()]);
      final devices = await loading;
      expect(devices.single.sensors.waterLevel, 92);
      expect(devices.single.settings.manualBrightness, 0);
      await emit({
        'deviceId': 'dev-1',
        'dps': {'103': 20},
      });
      expect(updates.last.device!.sensors.waterLevel, 92);
    },
  );

  group('当前固件版本', () {
    Future<String> firmwareOf(Map<Object?, Object?> raw) async {
      messenger.setMockMethodCallHandler(
        const MethodChannel(_methodChannel),
        (call) async => call.method == 'getDevices' ? <Object?>[raw] : null,
      );
      return (await repository.getDevices()).single.firmwareVersion;
    }

    test('花盆读 DP148，不看 112（花盆的 112 是空气温度）', () async {
      final raw = _deviceMap();
      raw['firmwareVersion'] = '9.9.9';
      raw['dps'] = <Object?, Object?>{'112': 246, '148': '1.0.13'};

      expect(await firmwareOf(raw), '1.0.13');
    });

    test('割草机读 DP112 fw_version', () async {
      final raw = _deviceMap();
      raw['productId'] = 'mz7g3yzaufvoh4ls';
      raw['firmwareVersion'] = '9.9.9';
      raw['dps'] = <Object?, Object?>{'112': '1.1.3'};

      expect(await firmwareOf(raw), '1.1.3');
    });

    test('设备没报版本 DP 时退回 SDK 的 verSw', () async {
      final raw = _deviceMap();
      raw['productId'] = 'mz7g3yzaufvoh4ls';
      raw['firmwareVersion'] = '1.1.0';
      raw['dps'] = <Object?, Object?>{'148': '1.0.13'};

      expect(await firmwareOf(raw), '1.1.0');
    });
  });

  group('FlowerpotState', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('a pushed report replaces the device on screen', () async {
      final mock = MockTuyaRepository(latency: Duration.zero);
      final state = FlowerpotState(repository: mock);
      await state.initialize();
      await state.login(
        account: '13800000000',
        credential: '8888',
        region: LoginRegion.domestic,
        verificationCode: true,
      );
      final device = state.devices.single;

      var notified = 0;
      state.addListener(() => notified++);
      mock.pushDeviceUpdate(DeviceUpdate.changed(device.copyWith(battery: 12)));
      await Future<void>.delayed(Duration.zero);

      expect(state.deviceById(device.id)!.battery, 12);
      expect(notified, greaterThan(0));
    });

    test('fresh report wins over a slow setting acknowledgement', () async {
      final mock = _DelayedUpdatesRepository();
      final state = FlowerpotState(repository: mock);
      addTearDown(state.dispose);
      await state.initialize();
      final device = (await mock.getDevices()).single;
      await state.refreshDevices();
      final gate = Completer<void>();
      mock.publishGate = gate.future;
      final write = state.updateSetting(device.id, 'manualBrightness', 70);
      await Future<void>.delayed(Duration.zero);
      mock.pushDeviceUpdate(
        DeviceUpdate.changed(
          device.copyWith(
            settings: device.settings.copyWith(manualBrightness: 25),
          ),
          changedDps: {168},
          reportedDps: {168: 25},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      expect((await write).success, isTrue);
      expect(state.deviceById(device.id)!.settings.manualBrightness, 25);
    });

    test('fresh SDK list replaces old local control override', () async {
      final mock = _DelayedUpdatesRepository();
      final state = FlowerpotState(repository: mock);
      addTearDown(state.dispose);
      await state.initialize();
      await state.refreshDevices();
      final device = state.devices.single;
      await state.updateSetting(device.id, 'manualBrightness', 70);
      expect(state.deviceById(device.id)!.settings.manualBrightness, 70);
      await state.refreshDevices();
      expect(
        state.deviceById(device.id)!.settings.manualBrightness,
        device.settings.manualBrightness,
      );
    });

    test(
      'DP arriving while home lookup waits stays visible after refresh',
      () async {
        final mock = _DelayedUpdatesRepository();
        final state = FlowerpotState(repository: mock);
        addTearDown(state.dispose);
        await state.initialize();
        await state.refreshDevices();
        final device = state.devices.single;
        final gate = Completer<String>();
        mock.homeGate = gate.future;
        final refresh = state.refreshDevices();
        await Future<void>.delayed(Duration.zero);
        mock.pushDeviceUpdate(
          DeviceUpdate.changed(
            device.copyWith(battery: 12),
            changedDps: {103},
            reportedDps: {103: 12},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        gate.complete('mock-home');
        await refresh;
        expect(state.deviceById(device.id)!.battery, 12);
      },
    );

    test('a pushed unbind drops the device', () async {
      final mock = MockTuyaRepository(latency: Duration.zero);
      final state = FlowerpotState(repository: mock);
      await state.initialize();
      await state.login(
        account: '13800000000',
        credential: '8888',
        region: LoginRegion.domestic,
        verificationCode: true,
      );
      final id = state.devices.single.id;

      mock.pushDeviceUpdate(DeviceUpdate.removed(id));
      await Future<void>.delayed(Duration.zero);

      expect(state.devices, isEmpty);
      expect(state.selectedDevice, isNull);
    });
  });
}

class _DelayedUpdatesRepository extends MockTuyaRepository {
  _DelayedUpdatesRepository() : super(latency: Duration.zero);
  Future<void>? publishGate;
  Future<String>? homeGate;

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    await publishGate;
  }

  @override
  Future<String> currentHomeId() async => await homeGate ?? 'mock-home';
}
