import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/touch_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/touch_settings_card.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('touch settings page matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpTouchSettings(tester, const Size(375, 812));

    expect(find.text('触觉感知'), findsOneWidget);
    expect(find.text('触摸交互'), findsOneWidget);
    expect(find.text('已禁用'), findsOneWidget);
    expect(find.text('YSplanter可以通过它的植物与身体感知人类触摸。'), findsOneWidget);
    expect(find.text('传感器灵敏度'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(findAssetImage(AppAssets.touchGestureSymbol), findsOneWidget);
    final card = find.byType(TouchSettingsCard);
    expect(tester.getSize(card), const Size(335, 425));
    expect(tester.getTopLeft(card), const Offset(20, 93));
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch settings remain usable at 320x568', (tester) async {
    await _pumpTouchSettings(tester, const Size(320, 568));

    final slider = find.byKey(const Key('touch-sensitivity-slider'));
    await tester.ensureVisible(slider);
    await tester.pump();

    expect(find.text('传感器灵敏度'), findsOneWidget);
    expect(slider, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch interaction is synchronized through the device DP', (
    tester,
  ) async {
    final result = await _pumpTouchSettings(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('touch-interaction-switch')));
    await tester.pumpAndSettle();

    expect(
      result.state.deviceById('device-01')?.settings.touchInteraction,
      isTrue,
    );
    expect(result.repository.lastDps, <int, Object>{112: true});
    expect(find.text('已启用'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('touch-interaction-switch')))
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch sensitivity is synchronized through the device DP', (
    tester,
  ) async {
    final result = await _pumpTouchSettings(tester, const Size(375, 812));
    final slider = tester.widget<Slider>(
      find.byKey(const Key('touch-sensitivity-slider')),
    );

    slider.onChanged!(45);
    await tester.pump();
    expect(find.text('45%'), findsOneWidget);
    slider.onChangeEnd!(45);
    await tester.pumpAndSettle();

    expect(result.state.deviceById('device-01')?.settings.touchSensitivity, 45);
    expect(result.repository.lastDps, <int, Object>{113: 45});
    expect(find.text('45%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing touch device uses the shared error state', (
    tester,
  ) async {
    final repository = _TouchSettingsRepository(includeDevice: false);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const TouchSettingsPage(deviceId: 'missing'),
        ),
      ),
    );

    expect(find.text('未找到设备'), findsOneWidget);
    expect(find.text('设备不存在或已经解绑。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device settings touch item opens the full touch page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _TouchSettingsRepository();
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
            if (settings.name == AppRoutes.touchSettings) {
              routeArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('touch-settings-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    final item = find.text('触觉感知');
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(find.text('touch-settings-target'), findsOneWidget);
    expect(routeArguments, 'device-01');
    expect(tester.takeException(), isNull);
  });
}

Future<({FlowerpotState state, _TouchSettingsRepository repository})>
_pumpTouchSettings(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _TouchSettingsRepository();
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const TouchSettingsPage(deviceId: 'device-01'),
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
    touchInteraction: false,
    touchSensitivity: 80,
  ),
  firmwareVersion: '1.0.0',
  macAddress: 'D8:85:AC:A2:B9:B4',
);

class _TouchSettingsRepository extends MockTuyaRepository {
  _TouchSettingsRepository({this.includeDevice = true})
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
