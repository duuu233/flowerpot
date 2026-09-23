import '../../support/plant_catalog.dart';
import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/behavior_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/behavior_schedule_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/schedule_slot_dialog.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('behavior settings page matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpBehaviorSettings(tester, const Size(375, 812));

    expect(find.text('行为'), findsOneWidget);
    expect(find.text('中午小憩'), findsOneWidget);
    expect(find.text('夜间睡眠'), findsOneWidget);
    expect(find.text('已开启'), findsNWidgets(2));
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('13:30'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('次日07:30'), findsOneWidget);
    expect(find.text('让 YSplanter 在正午稍作休息，可自定义她的小憩时'), findsOneWidget);
    expect(find.text('间。'), findsOneWidget);
    expect(find.text('设定 YSplanter 的夜间作息选择她的入睡与醒来时间。'), findsOneWidget);

    final cards = find.byType(BehaviorScheduleCard);
    expect(cards, findsNWidgets(2));
    expect(tester.getSize(cards.first), const Size(339, 268));
    expect(tester.getTopLeft(cards.first), const Offset(18, 73));
    expect(tester.getTopLeft(cards.last), const Offset(18, 353));
    expect(tester.takeException(), isNull);
  });

  testWidgets('behavior settings remain usable at 320x568', (tester) async {
    await _pumpBehaviorSettings(tester, const Size(320, 568));

    final target = find.byKey(const Key('night-end-time'));
    await tester.ensureVisible(target);
    await tester.pump();

    expect(target, findsOneWidget);
    expect(find.text('次日07:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nap switch is synchronized through the device DP', (
    tester,
  ) async {
    final result = await _pumpBehaviorSettings(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('nap-switch')));
    await tester.pumpAndSettle();

    expect(result.state.deviceById('device-01')?.settings.napEnabled, isFalse);
    expect(result.repository.lastDps, <int, Object>{125: false});
    expect(
      tester.widget<Switch>(find.byKey(const Key('nap-switch'))).value,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('night switch is synchronized through the device DP', (
    tester,
  ) async {
    final result = await _pumpBehaviorSettings(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('night-switch')));
    await tester.pumpAndSettle();

    expect(
      result.state.deviceById('device-01')?.settings.nightEnabled,
      isFalse,
    );
    expect(result.repository.lastDps, <int, Object>{128: false});
    expect(tester.takeException(), isNull);
  });

  testWidgets('nap start time is synchronized through the device DP', (
    tester,
  ) async {
    ScheduleSlot? initialSlot;
    String? dialogTitle;
    final result = await _pumpBehaviorSettings(
      tester,
      const Size(375, 812),
      slotEditor: (context, title, initial) async {
        dialogTitle = title;
        initialSlot = initial;
        // 一次弹窗同时带回开始和结束，所以结束时间原样送回。
        return ScheduleSlot(
          startMinutes: 11 * 60 + 45,
          endMinutes: initial.endMinutes,
        );
      },
    );

    await tester.tap(find.byKey(const Key('nap-start-time')));
    await tester.pumpAndSettle();

    expect(dialogTitle, '编辑中午小憩');
    expect(initialSlot?.startMinutes, 12 * 60);
    expect(initialSlot?.endMinutes, 13 * 60 + 30);
    expect(
      result.state.deviceById('device-01')?.settings.napPeriod,
      '11:45-13:30',
    );
    expect(result.repository.lastDps, <int, Object>{126: 705, 127: 810});
    expect(find.text('11:45'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('night end time keeps the next-day label and device DP', (
    tester,
  ) async {
    ScheduleSlot? initialSlot;
    final result = await _pumpBehaviorSettings(
      tester,
      const Size(375, 812),
      slotEditor: (context, title, initial) async {
        initialSlot = initial;
        return ScheduleSlot(
          startMinutes: initial.startMinutes,
          endMinutes: 6 * 60 + 45,
        );
      },
    );

    await tester.tap(find.byKey(const Key('night-end-time')));
    await tester.pumpAndSettle();

    expect(initialSlot?.startMinutes, 22 * 60);
    expect(initialSlot?.endMinutes, 7 * 60 + 30);
    expect(
      result.state.deviceById('device-01')?.settings.nightPeriod,
      '22:00-06:45',
    );
    expect(result.repository.lastDps, <int, Object>{129: 1320, 130: 405});
    expect(find.text('次日06:45'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing behavior device uses the shared error state', (
    tester,
  ) async {
    final repository = _BehaviorSettingsRepository(includeDevice: false);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const BehaviorSettingsPage(deviceId: 'missing'),
        ),
      ),
    );

    expect(find.text('未找到设备'), findsOneWidget);
    expect(find.text('设备不存在或已经解绑。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device settings behavior item opens the full behavior page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _BehaviorSettingsRepository();
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await state.refreshDevices();
    Object? routeArguments;

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceSettingsPage(deviceId: 'device-01'),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.behaviorSettings) {
              routeArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('behavior-settings-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    final item = find.text('行为');
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(find.text('behavior-settings-target'), findsOneWidget);
    expect(routeArguments, 'device-01');
    expect(tester.takeException(), isNull);
  });
}

Future<({FlowerpotState state, _BehaviorSettingsRepository repository})>
_pumpBehaviorSettings(
  WidgetTester tester,
  Size size, {
  BehaviorSlotEditor? slotEditor,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _BehaviorSettingsRepository();
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: BehaviorSettingsPage(
          deviceId: 'device-01',
          slotEditor: slotEditor,
        ),
      ),
    ),
  );
  await tester.pump();
  return (state: state, repository: repository);
}

SmartPlanterDevice get _device => SmartPlanterDevice(
  id: 'device-01',
  productId: 'product-01',
  name: 'YSplanter-01',
  online: true,
  signal: 86,
  battery: 94,
  charging: false,
  boundAt: DateTime.now().subtract(const Duration(days: 51)),
  plant: PlantCatalog.items.first,
  sensors: const SensorSnapshot(
    waterLevel: 80,
    soilMoisture: 97,
    illuminance: 305,
    ppfd: 5.642,
    airTemperature: 26.9,
    relativeHumidity: 52,
  ),
  settings: const DeviceControlSettings(
    napEnabled: true,
    napPeriod: '12:00-13:30',
    nightEnabled: true,
    nightPeriod: '22:00-07:30',
  ),
  firmwareVersion: '1.0.0',
  macAddress: 'D8:85:AC:A2:B9:B4',
);

class _BehaviorSettingsRepository extends MockTuyaRepository {
  _BehaviorSettingsRepository({this.includeDevice = true})
    : super(latency: Duration.zero);

  final bool includeDevice;
  Map<int, Object>? lastDps;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async =>
      includeDevice ? <SmartPlanterDevice>[_device] : <SmartPlanterDevice>[];

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    lastDps = dps;
  }
}
