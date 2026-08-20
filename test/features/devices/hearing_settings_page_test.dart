import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/hearing_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/hearing_settings_card.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('hearing settings page matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpHearingSettings(tester, const Size(375, 812));

    expect(find.text('听觉感知'), findsOneWidget);
    expect(find.text('声音互动'), findsOneWidget);
    expect(find.text('已开启'), findsOneWidget);
    expect(find.text('YSplanter可以听到声音与振动，并产生多种多样的独'), findsOneWidget);
    expect(find.text('特反馈。'), findsOneWidget);
    expect(find.text('传感器灵敏度'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(findAssetImage(AppAssets.hearingWaveformSymbol), findsOneWidget);
    final card = find.byType(HearingSettingsCard);
    expect(tester.getSize(card), const Size(339, 425));
    expect(tester.getTopLeft(card), const Offset(18, 93));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hearing settings remain usable at 320x568', (tester) async {
    await _pumpHearingSettings(tester, const Size(320, 568));

    final slider = find.byKey(const Key('sound-sensitivity-slider'));
    await tester.ensureVisible(slider);
    await tester.pump();

    expect(find.text('传感器灵敏度'), findsOneWidget);
    expect(slider, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sound interaction is synchronized through the device DP', (
    tester,
  ) async {
    final result = await _pumpHearingSettings(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('sound-interaction-switch')));
    await tester.pumpAndSettle();

    expect(
      result.state.deviceById('device-01')?.settings.soundInteraction,
      isFalse,
    );
    expect(result.repository.lastDps, <int, Object>{118: false});
    expect(find.text('已关闭'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('sound-interaction-switch')))
          .value,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sound sensitivity is synchronized through the device DP', (
    tester,
  ) async {
    final result = await _pumpHearingSettings(tester, const Size(375, 812));
    final slider = tester.widget<Slider>(
      find.byKey(const Key('sound-sensitivity-slider')),
    );

    slider.onChanged!(35);
    await tester.pump();
    expect(find.text('35%'), findsOneWidget);
    slider.onChangeEnd!(35);
    await tester.pumpAndSettle();

    expect(result.state.deviceById('device-01')?.settings.soundSensitivity, 35);
    expect(result.repository.lastDps, <int, Object>{119: 35});
    expect(find.text('35%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing hearing device uses the shared error state', (
    tester,
  ) async {
    final repository = _HearingSettingsRepository(includeDevice: false);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const HearingSettingsPage(deviceId: 'missing'),
        ),
      ),
    );

    expect(find.text('未找到设备'), findsOneWidget);
    expect(find.text('设备不存在或已经解绑。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device settings hearing item opens the full hearing page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _HearingSettingsRepository();
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
            if (settings.name == AppRoutes.hearingSettings) {
              routeArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('hearing-settings-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    final item = find.text('听觉感知');
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(find.text('hearing-settings-target'), findsOneWidget);
    expect(routeArguments, 'device-01');
    expect(tester.takeException(), isNull);
  });
}

Future<({FlowerpotState state, _HearingSettingsRepository repository})>
_pumpHearingSettings(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _HearingSettingsRepository();
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const HearingSettingsPage(deviceId: 'device-01'),
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
    soundInteraction: true,
    soundSensitivity: 80,
  ),
  firmwareVersion: '1.0.0',
  macAddress: 'D8:85:AC:A2:B9:B4',
);

class _HearingSettingsRepository extends MockTuyaRepository {
  _HearingSettingsRepository({this.includeDevice = true})
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
