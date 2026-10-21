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
  int checks = 0;
  Future<void> Function()? onStart;

  /// 涂鸦检测升级的结果；设为 null 表示云端已没有待装版本（设备其实已升好）。
  FirmwareUpdate? available = const FirmwareUpdate(
    version: _target,
    currentVersion: '1.0.0',
  );

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
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async {
    checks++;
    return available;
  }

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

  // 2026-10-21 用户：「OTA升级还是会失败，但是其实已经成功了」。下载进度已经走了
  // （96%，没有阶段6，iOS 也只有百分比）之后SDK报失败，同样先核验版本，不直接判失败。
  for (final product in ['planter', MowerDp.productId]) {
    test(
      '$product SDK failure during download progress waits for the actual version',
      () async {
        final repository = _Repository(productId: product);
        final state = await _state(repository);
        addTearDown(state.dispose);
        await _sdk(repository, percent: 96);
        await _sdk(repository, status: OtaStatus.failed);
        final waiting = state.otaProgressFor(_id)!;
        expect(waiting.status, OtaStatus.running);
        expect(waiting.verifyingVersion, isTrue);
        expect(waiting.percent, 96);
        expect(otaRunningLabel(waiting, withPercent: true), '正在确认升级结果');
        _report(repository, state);
        await Future<void>.delayed(Duration.zero);
        expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
        expect(state.deviceById(_id)!.firmwareVersion, _target);
        expect(repository.starts, 1);
      },
    );
  }

  test(
    'version reported during download confirms once the SDK gives up',
    () async {
      final repository = _Repository();
      final state = await _state(repository);
      addTearDown(state.dispose);
      await _sdk(repository, percent: 60);
      _report(repository, state);
      await Future<void>.delayed(Duration.zero);
      // 正常进行中仍只在安装阶段判，60% 时不提前完成。
      expect(state.otaProgressFor(_id)!.status, OtaStatus.running);
      await _sdk(repository, status: OtaStatus.failed);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
    },
  );

  test(
    'failure before any progress is final; target report cannot revive it',
    () async {
      final repository = _Repository();
      final state = await _state(repository);
      addTearDown(state.dispose);
      await _sdk(repository, stage: OtaStage.preparing);
      await _sdk(repository, status: OtaStatus.failed);
      _report(repository, state);
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.failed);
      expect(state.otaProgressFor(_id)!.verifyingVersion, isFalse);
    },
  );

  test(
    'explicit refusal code in a failure event stays final after progress',
    () async {
      final repository = _Repository();
      final state = await _state(repository);
      addTearDown(state.dispose);
      await _sdk(repository, percent: 40);
      repository.pushOtaProgress(
        const OtaProgress(
          deviceId: _id,
          status: OtaStatus.failed,
          message: '设备信号较弱',
          code: '5005',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.failed);
      expect(state.otaProgressFor(_id)!.verifyingVersion, isFalse);
    },
  );

  group('SDK 当前设备模型现读核验', () {
    test(
      'reconnect after the SDK failure reads the new verSw without a version DP push',
      () async {
        final repository = _Repository()
          ..firmwareVersionsByDevice[_id] = ['1.0.0'];
        final state = await _state(repository);
        addTearDown(state.dispose);
        await _sdk(repository, percent: 96, stage: OtaStage.installing);
        await _sdk(repository, status: OtaStatus.failed);
        await Future<void>.delayed(Duration.zero);
        expect(state.otaProgressFor(_id)!.verifyingVersion, isTrue);
        repository.firmwareVersionsByDevice[_id] = ['1.0.0', 'V1.1.0'];
        repository.pushDeviceUpdate(
          DeviceUpdate.changed(state.deviceById(_id)!.copyWith(online: true)),
        );
        await Future<void>.delayed(Duration.zero);
        expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
        expect(state.deviceById(_id)!.firmwareVersion, _target);
        expect(repository.starts, 1);
      },
    );

    test(
      'installation stage reads the SDK model without waiting for an event',
      () async {
        final repository = _Repository()
          ..firmwareVersionsByDevice[_id] = ['1.0.0'];
        final state = await _state(repository);
        addTearDown(state.dispose);
        await _sdk(repository, percent: 50);
        repository.firmwareVersionsByDevice[_id] = [_target];
        await Future<void>.delayed(Duration.zero);
        // 下载中不读、不判。
        expect(state.otaProgressFor(_id)!.status, OtaStatus.running);
        await _sdk(repository, percent: 98);
        await Future<void>.delayed(Duration.zero);
        expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
      },
    );

    test('reopening the progress re-reads the SDK model immediately', () async {
      final repository = _Repository()
        ..firmwareVersionsByDevice[_id] = ['1.0.0'];
      final state = await _state(repository);
      addTearDown(state.dispose);
      await _sdk(repository, percent: 96);
      await _sdk(repository, status: OtaStatus.failed);
      await Future<void>.delayed(Duration.zero);
      repository.firmwareVersionsByDevice[_id] = [_target];
      state.refreshOtaResult(_id);
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
    });

    test(
      'a source that already equalled the target before the upgrade proves nothing',
      () async {
        final repository = _Repository()
          // 例如另一个组件的版本号本来就是 1.1.0。
          ..firmwareVersionsByDevice[_id] = ['1.0.0', _target];
        final state = await _state(repository);
        addTearDown(state.dispose);
        await _sdk(repository, percent: 96);
        await _sdk(repository, status: OtaStatus.failed);
        repository.pushDeviceUpdate(
          DeviceUpdate.changed(state.deviceById(_id)!.copyWith(online: true)),
        );
        await Future<void>.delayed(Duration.zero);
        expect(state.otaProgressFor(_id)!.status, OtaStatus.running);
        expect(state.otaProgressFor(_id)!.verifyingVersion, isTrue);
        await _sdk(repository, status: OtaStatus.success);
        expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
      },
    );

    test(
      'without a baseline read the SDK model is not trusted; the version DP still is',
      () async {
        final repository = _Repository()..failFirmwareVersions = true;
        final state = await _state(repository);
        addTearDown(state.dispose);
        repository
          ..failFirmwareVersions = false
          ..firmwareVersionsByDevice[_id] = [_target];
        await _sdk(repository, percent: 96);
        await _sdk(repository, status: OtaStatus.failed);
        state.refreshOtaResult(_id);
        await Future<void>.delayed(Duration.zero);
        expect(state.otaProgressFor(_id)!.status, OtaStatus.running);
        _report(repository, state);
        await Future<void>.delayed(Duration.zero);
        expect(state.otaProgressFor(_id)!.status, OtaStatus.success);
      },
    );
  });

  testWidgets(
    'upgrade entry asks Tuya again instead of reusing the red-dot result',
    (tester) async {
      final repository = _Repository();
      late FlowerpotState state;
      await tester.runAsync(() async {
        state = await _state(repository, start: false);
      });
      addTearDown(state.dispose);
      expect(state.hasFirmwareUpdate(_id), isTrue);
      final before = repository.checks;
      // 设备其实已经升好：云端不再给待装版本。
      repository.available = null;
      await tester.pumpWidget(
        FlowerpotScope(
          state: state,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => runFirmwareUpgrade(context, _id),
                  child: const Text('检查升级'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('检查升级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.checks, before + 1);
      expect(find.text('当前已是最新固件版本'), findsOneWidget);
      expect(find.text('检查更新'), findsNothing);
      expect(state.hasFirmwareUpdate(_id), isFalse);
      expect(repository.starts, 0);
      // 等提示自己消失，再拆掉页面。
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
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
