import 'dart:async';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/ota_progress_dialog.dart';
import 'package:flowerpot/src/features/devices/presentation/firmware_upgrade_flow.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/mock_tuya_repository.dart';
import 'support/plant_catalog.dart';

class _Repository extends MockTuyaRepository {
  _Repository() : super(latency: Duration.zero);
  int starts = 0;
  bool inProgress = false;
  int? requestedComponent;
  @override
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async =>
      FirmwareUpdate(
        version: '1.1.0',
        currentVersion: '1.0.0',
        componentType: 9,
        inProgress: inProgress,
      );
  String? requestedVersion;
  Completer<void>? startReply;
  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    SmartPlanterDevice(
      id: 'mower-test',
      productId: MowerDp.productId,
      name: '测试割草机',
      online: true,
      signal: 90,
      battery: 90,
      charging: true,
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
      firmwareVersion: '1.0.0',
      macAddress: '',
    ),
  ];
  @override
  Future<void> startFirmwareUpgrade(
    String deviceId, {
    String? targetVersion,
    int? componentType,
  }) async {
    starts++;
    requestedVersion = targetVersion;
    requestedComponent = componentType;
    if (startReply != null) await startReply!.future;
  }
}

Future<FlowerpotState> _state(
  _Repository repository,
  DateTime Function() now,
) async {
  final state = FlowerpotState(repository: repository, otaClock: now);
  await state.initialize();
  await state.refreshDevices();
  state.pauseDeviceWatch();
  return state;
}

Future<void> _progress(
  _Repository repository, {
  int? percent,
  OtaStage? stage,
  OtaStatus status = OtaStatus.running,
}) async {
  repository.pushOtaProgress(
    OtaProgress(
      deviceId: 'mower-test',
      status: status,
      percent: percent,
      stage: stage,
    ),
  );
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('SDK stage 2 without a percentage is upgrading, not preparing', () {
    const progress = OtaProgress(
      deviceId: 'mower-test',
      status: OtaStatus.running,
      stage: OtaStage.upgrading,
    );
    expect(progress.displayStage, OtaStage.upgrading);
  });
  test(
    'negative and late progress do not reset the progress or install stage',
    () async {
      final repository = _Repository();
      var now = DateTime(2026);
      final state = await _state(repository, () => now);
      addTearDown(state.dispose);
      await state.upgradeFirmware('mower-test', '1.1.0');
      await _progress(repository, percent: 48, stage: OtaStage.upgrading);
      await _progress(repository, percent: -1, stage: OtaStage.preparing);
      expect(state.otaProgressFor('mower-test')?.percent, 48);
      expect(
        state.otaProgressFor('mower-test')?.displayStage,
        OtaStage.upgrading,
      );
      await _progress(repository, percent: 20);
      expect(state.otaProgressFor('mower-test')?.percent, 48);
      await _progress(repository, stage: OtaStage.installing);
      await _progress(repository, stage: OtaStage.upgrading);
      expect(
        state.otaProgressFor('mower-test')?.displayStage,
        OtaStage.installing,
      );
    },
  );
  test(
    'duplicate preparing snapshots cannot keep a stuck task alive',
    () async {
      final repository = _Repository();
      var now = DateTime(2026);
      final state = await _state(repository, () => now);
      addTearDown(state.dispose);
      await state.upgradeFirmware('mower-test', '1.1.0');
      await _progress(repository, stage: OtaStage.preparing);
      now = now.add(const Duration(minutes: 1));
      await _progress(repository, percent: 0, stage: OtaStage.preparing);
      now = now.add(const Duration(minutes: 1));
      expect(state.otaStalled('mower-test'), isTrue);
      expect(state.otaProgressFor('mower-test')?.status, OtaStatus.running);
    },
  );
  test(
    'real progress resets the stall timer but installation keeps its full grace',
    () async {
      final repository = _Repository();
      var now = DateTime(2026);
      final state = await _state(repository, () => now);
      addTearDown(state.dispose);
      await state.upgradeFirmware('mower-test', '1.1.0');
      now = now.add(const Duration(minutes: 1));
      await _progress(repository, percent: 25);
      now = now.add(const Duration(minutes: 2));
      expect(state.otaStalled('mower-test'), isFalse);
      await _progress(repository, stage: OtaStage.installing);
      now = now.add(const Duration(minutes: 9));
      expect(state.otaStalled('mower-test'), isFalse);
      now = now.add(const Duration(minutes: 1));
      expect(state.otaStalled('mower-test'), isTrue);
    },
  );
  test('reopening a running task does not dispatch another upgrade', () async {
    final repository = _Repository();
    final now = DateTime(2026);
    final state = await _state(repository, () => now);
    addTearDown(state.dispose);
    await state.upgradeFirmware('mower-test', '1.1.0');
    await state.upgradeFirmware('mower-test', '1.1.0');
    expect(repository.starts, 1);
    expect(repository.requestedVersion, '1.1.0');
  });
  testWidgets(
    'an existing SDK task restores its component and progress without a new confirmation',
    (tester) async {
      final repository = _Repository()..inProgress = true;
      final now = DateTime(2026);
      late FlowerpotState state;
      await tester.runAsync(() async {
        state = await _state(repository, () => now);
        await state.refreshFirmwareUpdate('mower-test');
      });
      addTearDown(state.dispose);
      expect(state.hasFirmwareUpdate('mower-test'), isFalse);
      await tester.pumpWidget(
        FlowerpotScope(
          state: state,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => runFirmwareUpgrade(context, 'mower-test'),
                  child: const Text('恢复升级'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('恢复升级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('ota-progress-dialog')), findsOneWidget);
      expect(find.text('检查更新'), findsNothing);
      expect(repository.requestedComponent, 9);
      repository.pushOtaProgress(
        const OtaProgress(deviceId: 'mower-test', status: OtaStatus.success),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('ota-progress-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'stuck preparation can be closed without failing or restarting the device',
    (tester) async {
      var now = DateTime(2026);
      final repository = _Repository();
      late FlowerpotState state;
      await tester.runAsync(() async {
        state = await _state(repository, () => now);
        await state.upgradeFirmware('mower-test', '1.1.0');
      });
      addTearDown(state.dispose);
      await tester.pumpWidget(
        FlowerpotScope(
          state: state,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showOtaProgressDialog(context, deviceId: 'mower-test'),
                  child: const Text('查看升级'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('查看升级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('ota-progress-close')), findsNothing);
      now = now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('暂未收到升级进度'), findsOneWidget);
      expect(state.otaProgressFor('mower-test')?.status, OtaStatus.running);
      await tester.tap(find.text('关闭窗口'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('ota-progress-dialog')), findsNothing);
      expect(repository.starts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'missing native start reply does not hold the entry forever or invent a failure',
    (tester) async {
      final repository = _Repository()..startReply = Completer<void>();
      final now = DateTime(2026);
      late FlowerpotState state;
      await tester.runAsync(() async {
        state = await _state(repository, () => now);
      });
      addTearDown(state.dispose);
      final result = state.upgradeFirmware('mower-test', '1.1.0');
      await tester.pump(const Duration(seconds: 31));
      expect((await result).success, isTrue);
      expect(state.otaProgressFor('mower-test')?.status, OtaStatus.running);
      repository.startReply!.complete();
      await tester.pump();
    },
  );
}
