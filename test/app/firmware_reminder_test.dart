import 'dart:async';

import 'package:flowerpot/src/app/app_route_tracker.dart';
import 'package:flowerpot/src/app/firmware_reminder.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_other_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/firmware_upgrade_flow.dart';
import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mock_tuya_repository.dart';

/// 2026-09-15 产品：固件升级按涂鸦返回的升级方式走不同交互——提醒升级弹框可取消、
/// 强制升级弹框不能取消、检测升级只留红点；只在设备页监控，「我的」和设备列表不监控。
void main() {
  Future<(FlowerpotState, List<RouteSettings>)> pumpHost(
    WidgetTester tester,
    FirmwareUpgradeType type, {
    bool confirmed = false,
    bool realSettings = false,
    bool mower = false,
    _UpgradeRepository? repository,
  }) async {
    final state = FlowerpotState(
      repository: repository ?? _UpgradeRepository(type),
    );
    addTearDown(state.dispose);
    await tester.runAsync(() async {
      if (realSettings) await state.initialize();
      await state.login(
        account: '13800138000',
        credential: 'demo',
        region: LoginRegion.domestic,
        verificationCode: false,
      );
    });
    if (mower) {
      MowerDevice.instance.resetForTest();
      addTearDown(MowerDevice.instance.resetForTest);
      await MowerDevice.instance.bind(
        state,
        owner: Object(),
        deviceId: state.devices.single.id,
      );
    }
    final routes = AppRouteTracker();
    final pushed = <RouteSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        navigatorObservers: <NavigatorObserver>[routes],
        builder: (context, child) => FlowerpotScope(
          state: state,
          child: FirmwareReminderHost(
            state: state,
            routes: routes,
            child: child!,
          ),
        ),
        home: const Scaffold(body: Text('root')),
        onGenerateRoute: (settings) {
          pushed.add(settings);
          if (realSettings && settings.name == AppRoutes.deviceOtherSettings) {
            final arguments =
                settings.arguments! as DeviceOtherSettingsArguments;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => DeviceOtherSettingsPage(
                deviceId: arguments.deviceId,
                startFirmwareUpgrade: arguments.startFirmwareUpgrade,
              ),
            );
          }
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => Scaffold(
              body: mower && realSettings
                  ? TextButton(
                      key: const Key('manual-firmware-check'),
                      onPressed: () => runFirmwareUpgrade(
                        context,
                        state.devices.single.id,
                        confirmed: confirmed,
                      ),
                      child: const Text('固件检测升级'),
                    )
                  : Text('${settings.name}'),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    return (state, pushed);
  }

  Future<void> open(
    WidgetTester tester,
    String route,
    Object? arguments,
  ) async {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.pushNamed(route, arguments: arguments));
    await tester.pumpAndSettle();
  }

  const remind = '检测到V1.1.0新版本，确认是否升级';
  const force = '检测到V1.1.0新版本，请升级后使用';

  for (final mower in [false, true]) {
    for (final type in [
      FirmwareUpgradeType.remind,
      FirmwareUpgradeType.force,
    ]) {
      testWidgets('$mower $type 离线不查询/不提醒，已有弹窗离线自动关闭', (tester) async {
        final repo = _UpgradeRepository(type, mower: mower);
        final (state, _) = await pumpHost(
          tester,
          type,
          mower: mower,
          realSettings: true,
          repository: repo,
        );
        final id = state.devices.single.id;
        final snapshot = state.deviceById(id)!;
        repo.pushDeviceUpdate(
          DeviceUpdate.changed(snapshot.copyWith(online: false)),
        );
        await tester.pumpAndSettle();
        await open(
          tester,
          mower ? AppRoutes.mowerHome : AppRoutes.deviceSettings,
          id,
        );
        expect(repo.checkCalls, 0);
        expect(find.text(remind), findsNothing);
        expect(find.text(force), findsNothing);
        final result = await state.upgradeFirmware(id, '1.1.0');
        expect(result.code, 'device_offline');
        expect(repo.startCalls, 0);
        expect(state.otaProgressFor(id), isNull);
        repo.pushDeviceUpdate(DeviceUpdate.changed(snapshot));
        await tester.pumpAndSettle();
        expect(
          find.text(type == FirmwareUpgradeType.force ? force : remind),
          findsOneWidget,
        );
        repo.pushDeviceUpdate(
          DeviceUpdate.changed(snapshot.copyWith(online: false)),
        );
        await tester.pumpAndSettle();
        expect(find.text(remind), findsNothing);
        expect(find.text(force), findsNothing);
        expect(repo.startCalls, 0);
      });
    }
  }
  testWidgets('手动确认期间离线，确认后不启动OTA', (tester) async {
    final repo = _UpgradeRepository(FirmwareUpgradeType.check, mower: true);
    final (state, _) = await pumpHost(
      tester,
      FirmwareUpgradeType.check,
      mower: true,
      realSettings: true,
      repository: repo,
    );
    final id = state.devices.single.id;
    await open(tester, AppRoutes.mowerHome, id);
    await tester.tap(find.byKey(const Key('manual-firmware-check')));
    await tester.pumpAndSettle();
    repo.pushDeviceUpdate(
      DeviceUpdate.changed(state.deviceById(id)!.copyWith(online: false)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('install-firmware-update')));
    await tester.pumpAndSettle();
    expect(repo.startCalls, 0);
    expect(state.otaProgressFor(id), isNull);
    expect(find.byKey(const Key('ota-progress-close')), findsNothing);
  });
  testWidgets('提醒升级：设备页弹框，取消后这次进设备面板不再弹', (tester) async {
    final (state, _) = await pumpHost(tester, FirmwareUpgradeType.remind);
    final id = state.devices.single.id;

    await open(tester, AppRoutes.deviceSettings, id);
    expect(find.text(remind), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('立刻更新'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text(remind), findsNothing);

    await open(tester, AppRoutes.displaySettings, id);
    expect(find.text(remind), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('立刻更新跳到其他设置（进页面再弹固件升级框）', (tester) async {
    final (state, pushed) = await pumpHost(tester, FirmwareUpgradeType.remind);
    final id = state.devices.single.id;

    await open(tester, AppRoutes.deviceSettings, id);
    await tester.tap(find.text('立刻更新'));
    await tester.pumpAndSettle();

    final target = pushed.last;
    expect(target.name, AppRoutes.deviceOtherSettings);
    final arguments = target.arguments! as DeviceOtherSettingsArguments;
    expect(arguments.deviceId, id);
    expect(arguments.startFirmwareUpgrade, isTrue);
    expect(find.text(remind), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('强制升级：没有取消，返回键关不掉', (tester) async {
    final (state, pushed) = await pumpHost(tester, FirmwareUpgradeType.force);
    final id = state.devices.single.id;

    await open(tester, AppRoutes.deviceSettings, id);
    expect(find.text(force), findsOneWidget);
    expect(find.text('取消'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(force), findsOneWidget);

    await tester.tap(find.text('立刻更新'));
    await tester.pumpAndSettle();
    expect(pushed.last.name, AppRoutes.deviceOtherSettings);
    // 「其他设置」本身不弹：升级入口就在这一页。
    expect(find.text(force), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final type in <FirmwareUpgradeType>[
    FirmwareUpgradeType.remind,
    FirmwareUpgradeType.force,
  ]) {
    testWidgets('$type：提醒完全退场后才开升级确认，进度出现后不再重弹', (tester) async {
      final repository = _UpgradeRepository(type);
      final (state, pushed) = await pumpHost(
        tester,
        type,
        realSettings: true,
        repository: repository,
      );
      final id = state.devices.single.id;
      final reminder = type == FirmwareUpgradeType.force ? force : remind;
      await open(tester, AppRoutes.deviceSettings, id);
      expect(find.text(reminder), findsOneWidget);
      await tester.tap(find.text('立刻更新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(reminder, skipOffstage: false), findsOneWidget);
      expect(
        pushed.where((route) => route.name == AppRoutes.deviceOtherSettings),
        isEmpty,
        reason: '提醒框退场完成前不跳页',
      );
      expect(find.byKey(const Key('firmware-update-dialog')), findsNothing);
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find
            .byKey(const Key('firmware-update-dialog'))
            .evaluate()
            .isNotEmpty) {
          expect(find.text(reminder, skipOffstage: false), findsNothing);
        }
      }
      expect(find.byKey(const Key('firmware-update-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('install-firmware-update')));
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find
            .byKey(const Key('ota-progress-dialog'))
            .evaluate()
            .isNotEmpty) {
          expect(find.text(reminder, skipOffstage: false), findsNothing);
          expect(
            find.byKey(
              const Key('firmware-update-dialog'),
              skipOffstage: false,
            ),
            findsNothing,
          );
        }
      }
      expect(find.byKey(const Key('ota-progress-dialog')), findsOneWidget);
      expect(repository.startCalls, 1);
      repository.pushOtaProgress(
        OtaProgress(deviceId: id, status: OtaStatus.running, percent: 42),
      );
      await tester.pump();
      await tester.pump();
      expect(state.otaProgressFor(id)?.percent, 42);
      expect(find.text('固件升级中'), findsOneWidget);
      expect(find.text(reminder, skipOffstage: false), findsNothing);
      repository.pushOtaProgress(
        OtaProgress(deviceId: id, status: OtaStatus.success),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.otaProgressFor(id)?.status, OtaStatus.success);
      await tester.tap(find.byKey(const Key('ota-progress-close')));
      await tester.pumpAndSettle();
      expect(find.text(reminder), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final type in <FirmwareUpgradeType>[
    FirmwareUpgradeType.remind,
    FirmwareUpgradeType.force,
  ]) {
    testWidgets('割草机 $type：切设置和确认期间不重弹提醒', (tester) async {
      final repository = _UpgradeRepository(type, mower: true);
      final (state, _) = await pumpHost(
        tester,
        type,
        realSettings: true,
        mower: true,
        repository: repository,
      );
      final id = state.devices.single.id;
      final reminder = type == FirmwareUpgradeType.force ? force : remind;
      await open(tester, AppRoutes.mowerHome, id);
      await tester.tap(find.text('立刻更新'));
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find
            .byKey(const Key('firmware-update-dialog'))
            .evaluate()
            .isNotEmpty) {
          expect(find.text(reminder, skipOffstage: false), findsNothing);
        }
      }
      expect(find.byKey(const Key('firmware-update-dialog')), findsOneWidget);
      expect(find.text(reminder, skipOffstage: false), findsNothing);
      await tester.tap(find.byKey(const Key('install-firmware-update')));
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find
            .byKey(const Key('ota-progress-dialog'))
            .evaluate()
            .isNotEmpty) {
          expect(find.text(reminder, skipOffstage: false), findsNothing);
          expect(
            find.byKey(
              const Key('firmware-update-dialog'),
              skipOffstage: false,
            ),
            findsNothing,
          );
        }
      }
      expect(find.byKey(const Key('ota-progress-dialog')), findsOneWidget);
      expect(repository.startCalls, 1);
      repository.pushOtaProgress(
        OtaProgress(deviceId: id, status: OtaStatus.success),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('ota-progress-close')));
      await tester.pumpAndSettle();
      expect(find.text(reminder, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('检测升级不弹框', (tester) async {
    final (state, _) = await pumpHost(tester, FirmwareUpgradeType.check);
    final id = state.devices.single.id;

    await open(tester, AppRoutes.deviceSettings, id);

    expect(state.hasFirmwareUpdate(id), isTrue);
    expect(find.text(remind), findsNothing);
    expect(find.text(force), findsNothing);
  });

  for (final type in [FirmwareUpgradeType.remind, FirmwareUpgradeType.force]) {
    for (final charging in <Object?>[0, 2, null, 'unknown']) {
      testWidgets('割草机 $type：DP117=$charging 不弹，充电上报后才弹', (tester) async {
        final repository = _UpgradeRepository(
          type,
          mower: true,
          chargingStatus: charging,
        );
        final (state, _) = await pumpHost(
          tester,
          type,
          mower: true,
          realSettings: true,
          repository: repository,
        );
        final id = state.devices.single.id;
        await open(tester, AppRoutes.mowerHome, id);
        expect(state.hasFirmwareUpdate(id), isTrue);
        expect(find.text(remind), findsNothing);
        expect(find.text(force), findsNothing);
        repository.rawDpsByDevice[id] = {MowerDp.chargingStatus: 'charging'};
        repository.pushDeviceUpdate(
          DeviceUpdate.changed(
            state.deviceById(id)!,
            changedDps: {MowerDp.chargingStatus},
            reportedDps: {MowerDp.chargingStatus: 'charging'},
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(type == FirmwareUpgradeType.force ? force : remind),
          findsOneWidget,
        );
        expect(repository.startCalls, 0);
      });
    }
  }

  for (final charging in <Object?>[0, 2, null, 'unknown', 1, 'charging']) {
    testWidgets('割草机手动检测 DP117=$charging：确认后判断充电再升级', (tester) async {
      final repository = _UpgradeRepository(
        FirmwareUpgradeType.check,
        mower: true,
        chargingStatus: charging,
      );
      final (state, _) = await pumpHost(
        tester,
        FirmwareUpgradeType.check,
        mower: true,
        realSettings: true,
        repository: repository,
      );
      final id = state.devices.single.id;
      await open(tester, AppRoutes.mowerHome, id);
      await tester.tap(find.byKey(const Key('manual-firmware-check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('firmware-update-dialog')), findsOneWidget);
      expect(find.text('请回桩进行ota升级'), findsNothing);
      expect(repository.startCalls, 0);
      await tester.tap(find.byKey(const Key('install-firmware-update')));
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        find.byKey(const Key('firmware-update-dialog'), skipOffstage: false),
        findsNothing,
      );
      if (charging == 1 || charging == 'charging') {
        expect(repository.startCalls, 1);
        expect(find.byKey(const Key('ota-progress-dialog')), findsOneWidget);
        repository.pushOtaProgress(
          OtaProgress(deviceId: id, status: OtaStatus.success),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(const Key('ota-progress-close')));
        await tester.pumpAndSettle();
      } else {
        expect(find.text('请回桩进行ota升级'), findsOneWidget);
        expect(repository.startCalls, 0);
        expect(state.otaProgressFor(id), isNull);
        expect(find.byKey(const Key('ota-progress-dialog')), findsNothing);
      }
      expect(state.isCheckingFirmware(id), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('已确认入口不能绕过充电门禁', (tester) async {
    final repository = _UpgradeRepository(
      FirmwareUpgradeType.check,
      mower: true,
      chargingStatus: 0,
    );
    final (state, _) = await pumpHost(
      tester,
      FirmwareUpgradeType.check,
      mower: true,
      realSettings: true,
      confirmed: true,
      repository: repository,
    );
    await open(tester, AppRoutes.mowerHome, state.devices.single.id);
    await tester.tap(find.byKey(const Key('manual-firmware-check')));
    await tester.pumpAndSettle();
    expect(find.text('请回桩进行ota升级'), findsOneWidget);
    expect(find.byKey(const Key('firmware-update-dialog')), findsNothing);
    expect(repository.startCalls, 0);
  });

  testWidgets('确认框停留期间离桩：点立即更新按最新DP117拦截', (tester) async {
    final repository = _UpgradeRepository(
      FirmwareUpgradeType.check,
      mower: true,
    );
    final (state, _) = await pumpHost(
      tester,
      FirmwareUpgradeType.check,
      mower: true,
      realSettings: true,
      repository: repository,
    );
    final id = state.devices.single.id;
    await open(tester, AppRoutes.mowerHome, id);
    await tester.tap(find.byKey(const Key('manual-firmware-check')));
    await tester.pumpAndSettle();
    repository.rawDpsByDevice[id] = {MowerDp.chargingStatus: 0};
    await tester.tap(find.byKey(const Key('install-firmware-update')));
    await tester.pumpAndSettle();
    expect(find.text('请回桩进行ota升级'), findsOneWidget);
    expect(repository.startCalls, 0);
    expect(state.otaProgressFor(id), isNull);
  });

  testWidgets('设备列表、「我的」不监控', (tester) async {
    final (state, _) = await pumpHost(tester, FirmwareUpgradeType.force);

    await open(tester, AppRoutes.deviceList, null);
    expect(find.text(force), findsNothing);
    await open(tester, AppRoutes.mine, null);
    expect(find.text(force), findsNothing);
    expect(state.hasFirmwareUpdate(state.devices.single.id), isFalse);
  });

  test('upgradeType 0 / 2 / 3 map to remind / force / check', () {
    expect(FirmwareUpgradeType.fromTuya(0), FirmwareUpgradeType.remind);
    expect(FirmwareUpgradeType.fromTuya(2), FirmwareUpgradeType.force);
    expect(FirmwareUpgradeType.fromTuya(3), FirmwareUpgradeType.check);
    // 老原生包不回这个字段：按检测升级处理，只亮红点。
    expect(FirmwareUpgradeType.fromTuya(null), FirmwareUpgradeType.check);
  });
}

class _UpgradeRepository extends MockTuyaRepository {
  _UpgradeRepository(this.type, {this.mower = false, this.chargingStatus = 1})
    : super(latency: Duration.zero);

  final FirmwareUpgradeType type;
  final bool mower;
  final Object? chargingStatus;
  int startCalls = 0;
  int checkCalls = 0;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async {
    final devices = await super.getDevices();
    if (mower) {
      for (final device in devices) {
        rawDpsByDevice.putIfAbsent(
          device.id,
          () => {MowerDp.chargingStatus: chargingStatus},
        );
      }
    }
    return mower
        ? devices
              .map(
                (device) => SmartPlanterDevice(
                  id: device.id,
                  productId: MowerDp.productId,
                  name: device.name,
                  online: device.online,
                  signal: device.signal,
                  battery: device.battery,
                  charging: device.charging,
                  boundAt: device.boundAt,
                  plant: device.plant,
                  sensors: device.sensors,
                  settings: device.settings,
                  firmwareVersion: device.firmwareVersion,
                  macAddress: device.macAddress,
                ),
              )
              .toList()
        : devices;
  }

  @override
  Future<void> startFirmwareUpgrade(String deviceId) async {
    startCalls++;
  }

  @override
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async {
    checkCalls++;
    return FirmwareUpdate(
      version: '1.1.0',
      currentVersion: '1.0.8',
      upgradeType: type,
    );
  }
}
