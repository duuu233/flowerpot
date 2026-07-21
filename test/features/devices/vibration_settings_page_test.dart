import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/vibration_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/vibration_settings_card.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('vibration settings page matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpVibrationSettings(tester, const Size(375, 812));

    expect(find.text('震动设置'), findsOneWidget);
    expect(find.text('启动震动'), findsOneWidget);
    expect(find.text('已禁用'), findsOneWidget);
    expect(find.text('开启后，YSplanter将在触摸操作、缺水警报及番茄钟'), findsOneWidget);
    expect(find.text('提醒等情况自动触发振动。'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    final card = find.byType(VibrationSettingsCard);
    expect(tester.getSize(card), const Size(335, 339));
    expect(tester.getTopLeft(card), const Offset(20, 93));
    expect(tester.takeException(), isNull);
  });

  testWidgets('vibration settings remain usable at 320x568', (tester) async {
    await _pumpVibrationSettings(tester, const Size(320, 568));

    final description = find.text('提醒等情况自动触发振动。');
    await tester.ensureVisible(description);
    await tester.pump();

    expect(description, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vibration is synchronized through the device DP', (
    tester,
  ) async {
    final result = await _pumpVibrationSettings(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('vibration-switch')));
    await tester.pumpAndSettle();

    expect(result.state.deviceById('device-01')?.settings.vibration, isTrue);
    expect(result.repository.lastDps, <int, Object>{114: true});
    expect(find.text('已启用'), findsOneWidget);
    expect(
      tester.widget<Switch>(find.byKey(const Key('vibration-switch'))).value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing vibration device uses the shared error state', (
    tester,
  ) async {
    final repository = _VibrationSettingsRepository(includeDevice: false);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const VibrationSettingsPage(deviceId: 'missing'),
        ),
      ),
    );

    expect(find.text('未找到设备'), findsOneWidget);
    expect(find.text('设备不存在或已经解绑。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device settings vibration item opens the full vibration page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _VibrationSettingsRepository();
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
            if (settings.name == AppRoutes.vibrationSettings) {
              routeArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('vibration-settings-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    final item = find.text('震动设置');
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(find.text('vibration-settings-target'), findsOneWidget);
    expect(routeArguments, 'device-01');
    expect(tester.takeException(), isNull);
  });
}

Future<({FlowerpotState state, _VibrationSettingsRepository repository})>
_pumpVibrationSettings(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _VibrationSettingsRepository();
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const VibrationSettingsPage(deviceId: 'device-01'),
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
  settings: const DeviceControlSettings(vibration: false),
  firmwareVersion: '1.0.0',
  macAddress: 'D8:85:AC:A2:B9:B4',
);

class _VibrationSettingsRepository extends MockTuyaRepository {
  _VibrationSettingsRepository({this.includeDevice = true})
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
