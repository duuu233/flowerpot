import 'dart:async';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/mock_tuya_repository.dart';
import 'support/plant_catalog.dart';

// The previous local reachability override was removed. SDK values alone
// determine both planter and mower online states.
void main() {
  Future<FlowerpotState> login(_OnlineRepository repo) async {
    final state = FlowerpotState(repository: repo);
    addTearDown(state.dispose);
    await state.initialize();
    final result = await state.login(
      account: '13800000000',
      credential: '8888',
      region: LoginRegion.domestic,
      verificationCode: true,
    );
    expect(result.success, isTrue);
    return state;
  }

  testWidgets('timeouts, BLE and phone network do not override SDK status', (
    tester,
  ) async {
    final repo = _OnlineRepository();
    final state = await login(repo);
    repo.unreachableDevices.addAll(['planter', 'mower']);
    repo.wifiLinked = false;
    repo.bleLinked = true;
    await tester.pump(const Duration(seconds: 80));
    await tester.pump();
    expect(repo.wifiSignalProbes, 0);
    expect(repo.statusReads, greaterThan(0));
    expect(state.devices.map((d) => d.online), [true, true]);
    expect(state.isDeviceOnline('planter'), isTrue);
    expect(state.isDeviceOnline('mower'), isTrue);
    expect(state.interactionLog.any((line) => line.contains('按离线处理')), isFalse);
    state.pauseDeviceWatch();
  });

  testWidgets('SDK cache false/true changes both device types without probes', (
    tester,
  ) async {
    final repo = _OnlineRepository();
    final state = await login(repo);
    repo.states = {'planter': false, 'mower': false};
    await tester.pump(FlowerpotState.onlinePollInterval);
    await tester.pump();
    expect(state.devices.map((d) => d.online), [false, false]);
    repo.states = {'planter': true, 'mower': true};
    await tester.pump(FlowerpotState.onlinePollInterval);
    await tester.pump();
    expect(state.devices.map((d) => d.online), [true, true]);
    expect(repo.wifiSignalProbes, 0);
    state.pauseDeviceWatch();
  });

  testWidgets('SDK read failure/empty result retains the latest SDK snapshot', (
    tester,
  ) async {
    final repo = _OnlineRepository();
    final state = await login(repo);
    repo.states = {};
    await tester.pump(FlowerpotState.onlinePollInterval);
    await tester.pump();
    expect(state.devices.map((d) => d.online), [true, true]);
    repo.failReads = true;
    await tester.pump(FlowerpotState.onlinePollInterval);
    await tester.pump();
    expect(state.devices.map((d) => d.online), [true, true]);
    state.pauseDeviceWatch();
  });

  testWidgets('SDK push updates online immediately for both types', (
    tester,
  ) async {
    final repo = _OnlineRepository();
    final state = await login(repo);
    state.pauseDeviceWatch();
    for (final device in state.devices.toList()) {
      repo.pushDeviceUpdate(
        DeviceUpdate.changed(device.copyWith(online: false)),
      );
    }
    await tester.pump();
    expect(state.devices.map((d) => d.online), [false, false]);
    for (final device in state.devices.toList()) {
      repo.pushDeviceUpdate(
        DeviceUpdate.changed(device.copyWith(online: true)),
      );
    }
    await tester.pump();
    expect(state.devices.map((d) => d.online), [true, true]);
  });

  testWidgets('a newer SDK push wins over an in-flight older query', (
    tester,
  ) async {
    final repo = _OnlineRepository();
    final state = await login(repo);
    final pending = Completer<Map<String, bool>>();
    repo.pending = pending;
    await tester.pump(FlowerpotState.onlinePollInterval);
    await tester.pump();
    for (final device in state.devices.toList()) {
      repo.pushDeviceUpdate(
        DeviceUpdate.changed(device.copyWith(online: false)),
      );
    }
    await tester.pump();
    pending.complete({'planter': true, 'mower': true});
    await tester.pump();
    expect(state.devices.map((d) => d.online), [false, false]);
    state.pauseDeviceWatch();
  });

  testWidgets(
    'late SDK query from an old session does not overwrite a new login',
    (tester) async {
      final repo = _OnlineRepository();
      final state = await login(repo);
      final pending = Completer<Map<String, bool>>();
      repo.pending = pending;
      await tester.pump(FlowerpotState.onlinePollInterval);
      await tester.pump();
      expect(repo.statusReads, greaterThan(0));
      await state.logout();
      repo.pending = null;
      await state.login(
        account: '13900000000',
        credential: '8888',
        region: LoginRegion.domestic,
        verificationCode: true,
      );
      pending.complete({'planter': false, 'mower': false});
      await tester.pump();
      expect(state.devices.map((d) => d.online), [true, true]);
      state.pauseDeviceWatch();
    },
  );
}

class _OnlineRepository extends MockTuyaRepository {
  _OnlineRepository() : super(latency: Duration.zero);
  Map<String, bool> states = {'planter': true, 'mower': true};
  bool failReads = false;
  int statusReads = 0;
  Completer<Map<String, bool>>? pending;

  @override
  Future<Map<String, bool>> deviceOnlineStates(List<String> ids) async {
    statusReads++;
    if (pending case final value?) return value.future;
    if (failReads) {
      throw const TuyaException('sdk_read_failed', 'SDK read failed');
    }
    return Map.of(states);
  }

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => [
    _device('planter', 'plant-product'),
    _device('mower', MowerDp.productId),
  ];

  SmartPlanterDevice _device(String id, String productId) => SmartPlanterDevice(
    id: id,
    productId: productId,
    name: id,
    online: states[id] ?? true,
    signal: 80,
    battery: 80,
    charging: false,
    boundAt: DateTime(2026),
    plant: PlantCatalog.items.first,
    settings: const DeviceControlSettings(),
    sensors: const SensorSnapshot(
      waterLevel: 50,
      soilMoisture: 50,
      illuminance: 300,
      ppfd: 5,
      airTemperature: 25,
      relativeHumidity: 50,
    ),
    firmwareVersion: '1.0.0',
    macAddress: '',
  );
}
