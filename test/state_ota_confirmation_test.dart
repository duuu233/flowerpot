import 'package:flowerpot/src/core/config/debug_log_gate.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/firmware_upgrade_flow.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/ota_progress_dialog.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_tuya_repository.dart';
import 'support/plant_catalog.dart';

const _id = 'ota-device';
const _target = '1.1.0';

class _Repository extends MockTuyaRepository {
  _Repository({this.productId = 'planter'}) : super(latency: Duration.zero);
  final String productId;
  int starts = 0;
  Future<void> Function()? onStart;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => [
    SmartPlanterDevice(
      id: _id,
      productId: productId,
      name: '测试设备',
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
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async =>
      const FirmwareUpdate(version: _target, currentVersion: '1.0.0');

  @override
  Future<void> startFirmwareUpgrade(
    String deviceId, {
    String? targetVersion,
    int? componentType,
  }) async {
    starts++;
    await onStart?.call();
  }
}

Future<FlowerpotState> _state(
  _Repository repository, {
  DateTime Function()? clock,
  bool start = true,
}) async {
  final state = FlowerpotState(repository: repository, otaClock: clock);
  await state.initialize();
  await state.refreshDevices();
  await state.checkFirmware(_id);
  if (start) await state.upgradeFirmware(_id, _target);
  return state;
}

Future<void> _sdk(
  _Repository repository, {
  OtaStatus status = OtaStatus.running,
  int? percent,
  OtaStage? stage,
}) async {
  repository.pushOtaProgress(
    OtaProgress(
      deviceId: _id,
      status: status,
      percent: percent,
      stage: stage,
      message: status == OtaStatus.failed ? 'SDK报告升级失败或超时' : null,
    ),
  );
  await Future<void>.delayed(Duration.zero);
}

void _report(
  _Repository repository,
  FlowerpotState state, {
  Object? version = _target,
  int? dp,
  bool fresh = true,
  Map<int, Object?> additional = const {},
}) {
  final versionDp =
      dp ?? (repository.productId == MowerDp.productId ? 112 : 148);
  repository.pushDeviceUpdate(
    DeviceUpdate.changed(
      state
          .deviceById(_id)!
          .copyWith(firmwareVersion: version is String ? version : _target),
      changedDps: fresh ? {versionDp, ...additional.keys} : {},
      reportedDps: {versionDp: version, ...additional},
    ),
  );
}

void main() {
  test(
    'timing separates progress installation and fresh target confirmation',
    () async {
      var now = DateTime(2026, 10, 20, 10);
      final lines = <String>[];
      final previousPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message?.startsWith('[ota-timing]') == true) lines.add(message!);
      };
      addTearDown(() => debugPrint = previousPrint);
      final repository = _Repository();
      final state = await _state(repository, clock: () => now);
      addTearDown(state.dispose);
      now = now.add(const Duration(seconds: 4));
      await _sdk(repository, percent: 1);
      await _sdk(repository, percent: 1);
      now = now.add(const Duration(seconds: 90));
      await _sdk(repository, percent: 96, stage: OtaStage.installing);
      now = now.add(const Duration(seconds: 1));
      await _sdk(repository, status: OtaStatus.failed);
      now = now.add(const Duration(seconds: 25));
      _report(repository, state);
      await Future<void>.delayed(Duration.zero);
      expect(
        lines.where((line) => line.contains('event=first_progress ')),
        hasLength(1),
      );
      expect(lines, contains(contains('event=installing elapsedMs=94000')));
      expect(
        lines,
        contains(contains('event=version_verification elapsedMs=95000')),
      );
      expect(
        lines,
        contains(contains('event=target_version_match elapsedMs=120000')),
      );
      expect(lines.last, contains('event=result_success elapsedMs=120000'));
      expect(lines.any((line) => line.contains(_id)), isFalse);
      final completedCount = lines.length;
      await _sdk(repository, status: OtaStatus.failed);
      expect(lines.length, completedCount);
      state.clearOtaProgress(_id);
      await state.upgradeFirmware(_id, _target);
      expect(lines.last, contains('attempt=2 event=start elapsedMs=0'));
    },
  );

  test('user builds do not collect OTA timing diagnostics', () async {
    // Run this assertion in the APP_DEBUG_TOOLS=false variant as well.
    if (DebugLogGate.enabled) return;
    final lines = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message?.startsWith('[ota-timing]') == true) lines.add(message!);
    };
    addTearDown(() => debugPrint = previousPrint);
    final repository = _Repository();
    final state = await _state(repository);
    addTearDown(state.dispose);
    await _sdk(repository, percent: 2);
    await _sdk(repository, status: OtaStatus.success);
    expect(lines, isEmpty);
  });

  test(
    'explicit SDK precheck refusal is not softened by installation progress',
    () async {
      final repository = _Repository();
      repository.onStart = () async {
        await _sdk(repository, stage: OtaStage.installing);
        throw const TuyaException('ota_precheck_failed', '设备不允许升级');
      };
      final state = await _state(repository, start: false);
      addTearDown(state.dispose);
      expect((await state.upgradeFirmware(_id, _target)).success, isFalse);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.failed);
      expect(state.otaProgressFor(_id)!.verifyingVersion, isFalse);
      _report(repository, state);
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.failed);
    },
  );

  for (final product in ['planter', MowerDp.productId]) {
    for (final stageOnly in [false, true]) {
      test(
        '$product SDK failure after ${stageOnly ? '96%+stage6' : '98%'} waits for actual target version',
        () async {
          final repository = _Repository(productId: product);
          final state = await _state(repository);
          addTearDown(state.dispose);
          await _sdk(
            repository,
            percent: stageOnly ? 96 : 98,
            stage: stageOnly ? OtaStage.installing : null,
          );
          await _sdk(repository, status: OtaStatus.failed);
          final waiting = state.otaProgressFor(_id)!;
          expect(waiting.status, OtaStatus.running);
          expect(waiting.verifyingVersion, isTrue);
          expect(waiting.percent, stageOnly ? 96 : 98);
          expect(otaRunningLabel(waiting, withPercent: true), '正在确认升级结果');
          expect(state.hasFirmwareUpdate(_id), isTrue);
          _report(repository, state, version: '1.0.0');
          await Future<void>.delayed(Duration.zero);
          expect(state.otaProgressFor(_id)!.verifyingVersion, isTrue);
          _report(repository, state, version: ' V1.1.0 ');
          await Future<void>.delayed(Duration.zero);
          expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
          expect(state.deviceById(_id)!.firmwareVersion, _target);
          expect(state.hasFirmwareUpdate(_id), isFalse);
          await _sdk(repository, status: OtaStatus.failed);
          expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
          expect(repository.starts, 1);
        },
      );
    }
  }

  test(
    'failure before installation is final; target report cannot hide a genuine failure',
    () async {
      final repository = _Repository();
      final state = await _state(repository);
      addTearDown(state.dispose);
      await _sdk(repository, percent: 96);
      await _sdk(repository, status: OtaStatus.failed);
      _report(repository, state);
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.failed);
      expect(state.otaProgressFor(_id)!.verifyingVersion, isFalse);
    },
  );

  test(
    'repeat failures and progress do not extend confirmation deadline; late actual version still resolves',
    () async {
      var now = DateTime(2026);
      final repository = _Repository();
      final state = await _state(repository, clock: () => now);
      addTearDown(state.dispose);
      await _sdk(repository, percent: 96, stage: OtaStage.installing);
      await _sdk(repository, status: OtaStatus.failed);
      now = now.add(const Duration(seconds: 119));
      await _sdk(repository, status: OtaStatus.failed);
      await _sdk(repository, percent: 100);
      expect(state.otaStalled(_id), isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(state.otaStalled(_id), isTrue);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.running);
      expect(state.otaProgressFor(_id)!.verifyingVersion, isTrue);
      now = now.add(const Duration(minutes: 5));
      _report(repository, state);
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
      expect(state.otaStalled(_id), isFalse);
      expect(repository.starts, 1);
    },
  );

  test(
    'snapshot, wrong product DP and invalid raw version cannot confirm an upgrade',
    () async {
      final repository = _Repository(productId: MowerDp.productId);
      final state = await _state(repository);
      addTearDown(state.dispose);
      await _sdk(repository, stage: OtaStage.installing);
      await _sdk(repository, status: OtaStatus.failed);
      _report(repository, state, fresh: false);
      _report(repository, state, dp: 148);
      _report(repository, state, version: null);
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.running);
      expect(state.otaProgressFor(_id)!.verifyingVersion, isTrue);
      _report(repository, state);
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
    },
  );

  for (final code in ['7', '20']) {
    test(
      'explicit mower DP116=$code overrides pending verification even alongside target version',
      () async {
        final repository = _Repository(productId: MowerDp.productId);
        final state = await _state(repository);
        addTearDown(state.dispose);
        await _sdk(repository, stage: OtaStage.installing);
        await _sdk(repository, status: OtaStatus.failed);
        _report(repository, state, additional: {116: code});
        await Future<void>.delayed(Duration.zero);
        expect(state.otaProgressFor(_id)!.status, OtaStatus.failed);
        expect(state.otaProgressFor(_id)!.verifyingVersion, isFalse);
        _report(repository, state);
        await _sdk(repository, status: OtaStatus.success);
        expect(state.otaProgressFor(_id)!.status, OtaStatus.failed);
      },
    );
  }

  test('a valid SDK success still resolves pending confirmation', () async {
    final repository = _Repository();
    final state = await _state(repository);
    addTearDown(state.dispose);
    await _sdk(repository, percent: 98);
    await _sdk(repository, status: OtaStatus.failed);
    await _sdk(repository, status: OtaStatus.success);
    expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
    expect(state.deviceById(_id)!.firmwareVersion, _target);
  });

  test(
    'SDK method error after installation progress opens confirmation instead of failing entry',
    () async {
      final repository = _Repository();
      repository.onStart = () async {
        await _sdk(repository, percent: 96, stage: OtaStage.installing);
        throw const TuyaException('ota_timeout', '等待结果超时');
      };
      final state = await _state(repository, start: false);
      addTearDown(state.dispose);
      expect((await state.upgradeFirmware(_id, _target)).success, isTrue);
      expect(state.otaProgressFor(_id)!.verifyingVersion, isTrue);
      expect((await state.upgradeFirmware(_id, _target)).success, isTrue);
      expect(repository.starts, 1);
      _report(repository, state);
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
    },
  );

  test(
    'retrying a different target clears prior verification evidence',
    () async {
      var now = DateTime(2026);
      final repository = _Repository();
      final state = await _state(repository, clock: () => now);
      addTearDown(state.dispose);
      await _sdk(repository, stage: OtaStage.installing);
      await _sdk(repository, status: OtaStatus.failed);
      now = now.add(const Duration(minutes: 3));
      state.clearOtaProgress(_id);
      expect(state.otaStalled(_id), isFalse);
      _report(repository, state);
      await Future<void>.delayed(Duration.zero);
      await state.upgradeFirmware(_id, '1.2.0');
      await _sdk(repository, stage: OtaStage.installing);
      _report(repository, state);
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.running);
      expect(state.otaProgressFor(_id)!.verifyingVersion, isFalse);
      _report(repository, state, version: '1.2.0');
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
    },
  );

  test('logout clears pending verification and its deadline', () async {
    final repository = _Repository();
    final state = await _state(repository);
    addTearDown(state.dispose);
    await _sdk(repository, percent: 98);
    await _sdk(repository, status: OtaStatus.failed);
    await state.logout();
    expect(state.otaProgressFor(_id), isNull);
    expect(state.otaStalled(_id), isFalse);
  });

  for (final product in ['planter', MowerDp.productId]) {
    testWidgets(
      '$product dialog stays pending after failure and becomes successful on actual version report',
      (tester) async {
        final repository = _Repository(productId: product);
        late FlowerpotState state;
        await tester.runAsync(() async {
          state = await _state(repository);
          await _sdk(repository, percent: 96, stage: OtaStage.installing);
        });
        addTearDown(state.dispose);
        await _pumpDialog(tester, state);
        repository.pushOtaProgress(
          const OtaProgress(deviceId: _id, status: OtaStatus.failed),
        );
        await tester.pump();
        expect(find.text('正在确认升级结果'), findsOneWidget);
        expect(find.text('升级失败'), findsNothing);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byKey(const Key('ota-progress-bar')),
              )
              .value,
          isNull,
        );
        expect(find.byKey(const Key('ota-progress-close')), findsOneWidget);
        _report(repository, state);
        await tester.pump();
        expect(find.text('升级完成'), findsOneWidget);
        expect(find.text('100%'), findsOneWidget);
        await tester.tap(find.text('知道了'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(repository.starts, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'online manual recheck is neutral and cancelling preserves the target',
    (tester) async {
      var now = DateTime(2026);
      final repository = _Repository();
      late FlowerpotState state;
      await tester.runAsync(() async {
        state = await _state(repository, clock: () => now);
        await _sdk(repository, percent: 98);
        await _sdk(repository, status: OtaStatus.failed);
      });
      addTearDown(state.dispose);
      await _pumpDialog(tester, state);
      await tester.tap(find.text('关闭窗口'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      now = now.add(const Duration(minutes: 2));
      await tester.tap(find.text('查看升级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('暂未确认升级结果'), findsOneWidget);
      expect(find.text('升级似乎已中断'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.otaProgressFor(_id)!.verifyingVersion, isTrue);
      _report(repository, state);
      await tester.pump();
      expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
      expect(repository.starts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'verification expiry is unconfirmed, closable and viewable offline without another start',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var now = DateTime(2026);
      final repository = _Repository();
      late FlowerpotState state;
      await tester.runAsync(() async {
        state = await _state(repository, clock: () => now);
        await _sdk(repository, percent: 98);
        await _sdk(repository, status: OtaStatus.failed);
      });
      addTearDown(state.dispose);
      await _pumpDialog(tester, state);
      now = now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('暂未确认升级结果'), findsOneWidget);
      expect(find.text('升级失败'), findsNothing);
      await tester.tap(find.text('关闭窗口'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.otaProgressFor(_id)!.verifyingVersion, isTrue);
      repository.pushDeviceUpdate(
        DeviceUpdate.changed(state.deviceById(_id)!.copyWith(online: false)),
      );
      await tester.pump();
      await tester.tap(find.text('查看升级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('暂未确认升级结果'), findsOneWidget);
      expect(find.text('升级似乎已中断'), findsNothing);
      _report(repository, state);
      await tester.pump();
      expect(find.text('升级完成'), findsOneWidget);
      expect(repository.starts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Future<void> _pumpDialog(WidgetTester tester, FlowerpotState state) async {
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => runFirmwareUpgrade(context, _id),
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
}
