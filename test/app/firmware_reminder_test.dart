import 'dart:async';

import 'package:flowerpot/src/app/app_route_tracker.dart';
import 'package:flowerpot/src/app/firmware_reminder.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_other_settings_page.dart';
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
            builder: (_) => Scaffold(body: Text('${settings.name}')),
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
  _UpgradeRepository(this.type, {this.mower = false})
    : super(latency: Duration.zero);

  final FirmwareUpgradeType type;
  final bool mower;
  int startCalls = 0;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async {
    final devices = await super.getDevices();
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
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async =>
      FirmwareUpdate(
        version: '1.1.0',
        currentVersion: '1.0.8',
        upgradeType: type,
      );
}
