import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/device_settings_page_model.dart';
import 'package:flowerpot/src/features/devices/presentation/device_messages_page.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';

/// 花盆消息通知（2026-09-28 产品：照割草机做）。列表和割草机共用 `DeviceMessagesView`，
/// 这里看花盆这边的入口和分栏：日志 = 通知、提醒 = 轻微、告警 = 严重（认不出等级的也归告警）。
void main() {
  test('设置页功能列表有「消息通知」，排在「其他设置」前面', () async {
    final repository = MockTuyaRepository(latency: Duration.zero);
    final device = (await repository.getDevices()).first;
    final kinds = DeviceSettingsPageModel.fromDevice(
      device,
    ).menuItems.map((item) => item.kind).toList();

    expect(
      kinds.where((kind) => kind == DeviceSettingsMenuKind.messages),
      hasLength(1),
    );
    expect(
      kinds.indexOf(DeviceSettingsMenuKind.messages),
      kinds.indexOf(DeviceSettingsMenuKind.other) - 1,
    );
  });

  testWidgets('设备离线也能点进消息通知（看的是云端历史推送，其它项的在线门禁不变）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MessagesRepository(offline: true);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await state.refreshDevices();
    final deviceId = state.devices.first.id;
    Object? arguments;

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: DeviceSettingsPage(deviceId: deviceId),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.deviceMessages) {
              arguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('device-messages-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    final entry = find.text('消息通知');
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('device-messages-target'), findsOneWidget);
    expect(arguments, deviceId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('三栏按推送等级分：通知进日志、轻微进提醒、严重和认不出的进告警', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final repository = _MessagesRepository(
      items: <Map<String, Object?>>[
        <String, Object?>{
          'msgTitle': '水位偏低',
          'msgContent': '请及时加水',
          'time': now - 60,
          'extendParams': '{"level":"通知"}',
        },
        <String, Object?>{
          'msgTitle': '土壤偏干',
          'time': now - 120,
          'alarmType': 2,
        },
        <String, Object?>{
          'msgTitle': '传感器异常',
          'time': now - 180,
          'alarmType': 3,
        },
        <String, Object?>{'msgTitle': '未知消息', 'time': now - 240},
      ],
    );
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await state.refreshDevices();

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: DeviceMessagesPage(deviceId: state.devices.first.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('消息通知'), findsOneWidget);
    expect(find.text('全部日期'), findsOneWidget);
    // 日志栏（默认）
    expect(find.text('水位偏低'), findsOneWidget);
    expect(find.text('请及时加水'), findsOneWidget);
    expect(find.text('土壤偏干'), findsNothing);

    await tester.tap(find.byKey(const Key('device-messages-tab-1')));
    await tester.pump();
    expect(find.text('土壤偏干'), findsOneWidget);
    expect(find.text('水位偏低'), findsNothing);

    await tester.tap(find.byKey(const Key('device-messages-tab-2')));
    await tester.pump();
    expect(find.text('传感器异常'), findsOneWidget);
    expect(find.text('未知消息'), findsOneWidget);
    expect(find.text('土壤偏干'), findsNothing);
    expect(
      state.interactionLog.any((line) => line.contains('花盆-消息通知 分档：共 4 条')),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('消息中心取不到：如实写原因，不编数据', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    await state.refreshDevices();

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: DeviceMessagesPage(deviceId: state.devices.first.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('没有取到：Mock 仓库没有涂鸦消息中心'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('device-messages-empty')), findsOneWidget);
  });
}

/// 消息中心按设备取时回 [items]；[offline] 时清单里的花盆都是离线的。
class _MessagesRepository extends MockTuyaRepository {
  _MessagesRepository({
    this.items = const <Map<String, Object?>>[],
    this.offline = false,
  }) : super(latency: Duration.zero);

  final List<Map<String, Object?>> items;
  final bool offline;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async {
    final devices = await super.getDevices();
    return offline
        ? <SmartPlanterDevice>[
            for (final device in devices) device.copyWith(online: false),
          ]
        : devices;
  }

  @override
  Future<Map<String, Object?>> deviceMessages({
    required String deviceId,
    String msgType = 'MSG_REPORT',
    int offset = 0,
    int limit = 50,
  }) async => <String, Object?>{
    'ok': true,
    'msgSrcId': deviceId,
    'msgType': msgType,
    'method': 'mock',
    'instance': 'mock',
    'items': offset == 0 ? items : const <Map<String, Object?>>[],
    'count': offset == 0 ? items.length : 0,
    'totalCount': items.length,
  };
}
