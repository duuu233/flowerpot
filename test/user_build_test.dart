import 'package:flowerpot/src/tuya/tuya_raw.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/app/interaction_log_overlay.dart';
import 'package:flowerpot/src/core/config/debug_log_gate.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_info_page.dart';
import 'package:flowerpot/src/features/devices/presentation/device_list_page.dart';
import 'package:flowerpot/src/features/devices/presentation/device_messages_page.dart';
import 'package:flowerpot/src/features/messages/message_monitor_console.dart';
import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/presentation/mower_home_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_tuya_repository.dart';
import 'support/plant_catalog.dart';

void main() {
  const enabled = DebugLogGate.enabled;

  test('应用调试输出遵循构建总闸', () {
    final lines = <String?>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message);
    addTearDown(() => debugPrint = original);
    DebugLogGate.log('private diagnostic');
    expect(lines, enabled ? ['private diagnostic'] : isEmpty);
  });

  testWidgets('全局日志浮层遵循构建总闸，运行时开关不能重新开启用户包', (tester) async {
    final repository = MockTuyaRepository(latency: Duration.zero);
    await repository.login(
      account: 'test@example.com',
      credential: '12345678',
      region: LoginRegion.overseas,
      verificationCode: false,
    );
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await state.initialize();
    state.pauseDeviceWatch();
    DebugLogGate.interactionLog = true;
    state.logNote('DP101 test');
    await _pump(
      tester,
      state,
      const InteractionLogOverlay(child: Scaffold(body: Text('业务页面'))),
    );
    expect(find.text('业务页面'), findsOneWidget);
    expect(state.interactionLog.isNotEmpty, enabled);
    expect(
      find.byKey(const Key('interaction-log-pill')),
      enabled ? findsOneWidget : findsNothing,
    );
  });

  testWidgets('消息保留真实列表，用户包不挂写死的监控数据或额外查询', (tester) async {
    final repo = _MessageRepository();
    final state = FlowerpotState(repository: repo);
    addTearDown(state.dispose);
    await state.refreshDevices();
    final id = state.devices.first.id;
    await _pump(tester, state, DeviceMessagesPage(deviceId: id));
    await tester.pumpAndSettle();
    expect(find.text('真实设备消息'), findsOneWidget);
    expect(
      find.byType(MessageMonitorConsole),
      enabled ? findsOneWidget : findsNothing,
    );
    expect(repo.queriedIds.contains(id), isTrue);
    expect(repo.queriedIds.any((item) => item != id), enabled);
    expect(find.text('日志'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('告警'), findsOneWidget);
  });

  testWidgets('单独挂监控组件时，用户包也不展示或发起诊断查询', (tester) async {
    final repo = _MessageRepository();
    final state = FlowerpotState(repository: repo);
    addTearDown(state.dispose);
    await _pump(
      tester,
      state,
      const Scaffold(
        body: MessageMonitorConsole(
          title: 'diagnostic',
          deviceIds: ['debug-only'],
          windows: [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('message-monitor-console')),
      enabled ? findsOneWidget : findsNothing,
    );
    expect(repo.queriedIds, enabled ? ['debug-only'] : isEmpty);
  });

  testWidgets('花盆设备信息保留业务字段，DP诊断入口遵循构建总闸', (tester) async {
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    await state.refreshDevices();
    await _pump(
      tester,
      state,
      DeviceInfoPage(deviceId: state.devices.first.id),
    );
    await tester.pumpAndSettle();
    expect(find.text('固件版本'), findsOneWidget);
    expect(
      find.byKey(const Key('device-info-dp162-probe')),
      enabled ? findsOneWidget : findsNothing,
    );
  });

  testWidgets('空设备列表不向用户展示账号家庭诊断', (tester) async {
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero, seedDevice: false),
    );
    addTearDown(state.dispose);
    await state.refreshDevices();
    await _pump(tester, state, const DeviceListPage());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('device-list-diagnostics')),
      enabled ? findsOneWidget : findsNothing,
    );
  });

  testWidgets('割草计划调试台遵循构建总闸，时段仍可编辑并下发', (tester) async {
    MowerDevice.instance.resetForTest();
    final repo = _MowerRepository();
    final schedule = Uint8List(88);
    schedule.setRange(0, 11, [0x1c, 2, 0xd0, 2, 0x48, 3, 0x38, 4, 1, 1, 1]);
    repo.rawDpsByDevice['user-mower'] = {101: TuyaRaw.hex(schedule)};
    final state = FlowerpotState(repository: repo);
    addTearDown(state.dispose);
    await state.initialize();
    state.pauseDeviceWatch();
    await state.refreshDevices();
    state.pauseDeviceWatch();
    await _pump(tester, state, MowerHomePage(deviceId: 'user-mower'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('mower-plan-debug-window')),
      enabled ? findsOneWidget : findsNothing,
    );
    await tester.tap(find.byKey(const Key('mower-plan-slot-1-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('DP101 有效位'), findsNothing);
    await tester.tap(find.byKey(const Key('mower-plan-edit-slot-enabled')));
    await tester.tap(find.byKey(const Key('mower-plan-edit-save')));
    await tester.pumpAndSettle();
    expect(repo.publishedDps.single.$1, 'user-mower');
    expect(repo.publishedDps.single.$2, contains(MowerDp.mowSchedule));
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  FlowerpotState state,
  Widget page,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: page,
        onGenerateRoute: (settings) =>
            AppRoutes.onGenerateRoute(settings, authenticated: true),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _MessageRepository extends MockTuyaRepository {
  _MessageRepository() : super(latency: Duration.zero);
  final queriedIds = <String>[];
  @override
  Future<Map<String, Object?>> deviceMessages({
    required String deviceId,
    String msgType = 'MSG_REPORT',
    int offset = 0,
    int limit = 50,
  }) async {
    queriedIds.add(deviceId);
    return {
      'ok': true,
      'items': [
        {
          'id': 'real-message',
          'msgTitle': '真实设备消息',
          'msgContent': '设备返回的内容',
          'extendParams': '{"level":"通知"}',
          'time': 1792022400,
        },
      ],
      'totalCount': 1,
    };
  }
}

class _MowerRepository extends MockTuyaRepository {
  _MowerRepository() : super(latency: Duration.zero, seedDevice: false);
  @override
  Future<List<SmartPlanterDevice>> getDevices() async => [
    SmartPlanterDevice(
      id: 'user-mower',
      productId: MowerDp.productId,
      name: '用户割草机',
      macAddress: '00:00:00:00:00:01',
      online: true,
      signal: 80,
      battery: 80,
      charging: false,
      boundAt: DateTime(2026, 10, 15),
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
    ),
  ];
}
