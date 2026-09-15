import 'dart:async';

import 'package:flowerpot/src/app/app_route_tracker.dart';
import 'package:flowerpot/src/app/firmware_reminder.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_other_settings_page.dart';
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
    FirmwareUpgradeType type,
  ) async {
    final state = FlowerpotState(repository: _UpgradeRepository(type));
    addTearDown(state.dispose);
    await tester.runAsync(
      () => state.login(
        account: '13800138000',
        credential: 'demo',
        region: LoginRegion.domestic,
        verificationCode: false,
      ),
    );
    final routes = AppRouteTracker();
    final pushed = <RouteSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        navigatorObservers: <NavigatorObserver>[routes],
        builder: (context, child) =>
            FirmwareReminderHost(state: state, routes: routes, child: child!),
        home: const Scaffold(body: Text('root')),
        onGenerateRoute: (settings) {
          pushed.add(settings);
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

  testWidgets('立刻更新跳到其他设置并直接发起升级', (tester) async {
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
  _UpgradeRepository(this.type) : super(latency: Duration.zero);

  final FirmwareUpgradeType type;

  @override
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async =>
      FirmwareUpdate(
        version: '1.1.0',
        currentVersion: '1.0.8',
        upgradeType: type,
      );
}
