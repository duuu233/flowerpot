import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/plant_detection_settings_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('自动检测植物是一张卡一个开关，版式与 LED 设置一致', (tester) async {
    await _pumpPlantDetection(tester, const Size(375, 812));

    expect(find.text('自动检测植物'), findsOneWidget);
    expect(find.text('启用自动检测'), findsOneWidget);
    expect(find.text('已开启'), findsOneWidget);
    expect(find.byKey(const Key('plant-detection-switch')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开关下发 DP 163', (tester) async {
    final result = await _pumpPlantDetection(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('plant-detection-switch')));
    await tester.pumpAndSettle();

    expect(result.repository.lastDps, <int, Object>{163: false});
    expect(
      result.state.deviceById('device-01')?.settings.plantDetection,
      isFalse,
    );
    expect(find.text('已关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页的这一行改成跳页，不再是行内开关', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _PlantDetectionRepository();
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
            if (settings.name == AppRoutes.plantDetectionSettings) {
              routeArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('plant-detection-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    // 行内开关已经没有了，这一行只显示状态。
    expect(
      find.byKey(const Key('device-settings-toggle-plantDetection')),
      findsNothing,
    );
    final item = find.text('自动检测植物');
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(find.text('plant-detection-target'), findsOneWidget);
    expect(routeArguments, 'device-01');
    expect(tester.takeException(), isNull);
  });
}

Future<({FlowerpotState state, _PlantDetectionRepository repository})>
_pumpPlantDetection(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _PlantDetectionRepository();
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const PlantDetectionSettingsPage(deviceId: 'device-01'),
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

class _PlantDetectionRepository extends MockTuyaRepository {
  _PlantDetectionRepository() : super(latency: Duration.zero);

  Map<int, Object>? lastDps;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    _device,
  ];

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    lastDps = dps;
  }
}
