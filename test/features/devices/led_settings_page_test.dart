import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/led_settings_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LED page is one switch, laid out like 震动设置', (tester) async {
    await _pumpLedSettings(tester, const Size(375, 812));

    expect(find.text('LED设置'), findsOneWidget);
    expect(find.text('启用LED'), findsOneWidget);
    expect(find.text('已开启'), findsOneWidget);
    expect(find.text('关闭后，YSplanter的屏幕指示灯将不再亮起，'), findsOneWidget);
    expect(find.byKey(const Key('led-switch')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the LED switch writes the display brightness DP', (
    tester,
  ) async {
    // 09-03 的功能点表里没有单独的 LED 开关，这一页和「显示」共用 117。
    final result = await _pumpLedSettings(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('led-switch')));
    await tester.pumpAndSettle();

    expect(result.repository.lastDps, <int, Object>{117: false});
    expect(
      result.state.deviceById('device-01')?.settings.autoBrightness,
      isFalse,
    );
    expect(find.text('已关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing LED device uses the shared error state', (tester) async {
    final repository = _LedSettingsRepository(includeDevice: false);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const LedSettingsPage(deviceId: 'missing'),
        ),
      ),
    );

    expect(find.text('未找到设备'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the settings list has an LED row that opens the page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _LedSettingsRepository();
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
            if (settings.name == AppRoutes.ledSettings) {
              routeArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Center(child: Text('led-target'))),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    final item = find.text('LED设置');
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(find.text('led-target'), findsOneWidget);
    expect(routeArguments, 'device-01');
    expect(tester.takeException(), isNull);
  });
}

Future<({FlowerpotState state, _LedSettingsRepository repository})>
_pumpLedSettings(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _LedSettingsRepository();
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const LedSettingsPage(deviceId: 'device-01'),
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
  settings: const DeviceControlSettings(),
  firmwareVersion: '1.0.0',
  macAddress: 'D8:85:AC:A2:B9:B4',
);

class _LedSettingsRepository extends MockTuyaRepository {
  _LedSettingsRepository({this.includeDevice = true})
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
