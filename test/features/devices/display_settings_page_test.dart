import 'dart:async';

import '../../support/plant_catalog.dart';
import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/display_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/display_settings_card.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('display settings page matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpDisplaySettings(tester, const Size(375, 812));

    expect(find.text('显示'), findsOneWidget);
    expect(find.text('自动屏幕亮度'), findsOneWidget);
    expect(find.text('已开启'), findsOneWidget);
    expect(find.text('自动屏幕亮度开启后，YSplanter会根据检测到的环境'), findsOneWidget);
    expect(find.text('光强度自动调节屏幕亮度；关闭后可手动调节亮度。'), findsOneWidget);
    expect(findAssetImage(AppAssets.brightnessSymbol), findsOneWidget);
    final card = find.byType(DisplaySettingsCard);
    expect(tester.getSize(card), const Size(339, 425));
    expect(tester.getTopLeft(card), const Offset(18, 73));
    expect(tester.takeException(), isNull);
  });

  testWidgets('display settings remain usable at 320x568', (tester) async {
    await _pumpDisplaySettings(tester, const Size(320, 568));

    final description = find.text('光强度自动调节屏幕亮度；关闭后可手动调节亮度。');
    await tester.ensureVisible(description);
    await tester.pump();

    expect(description, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic brightness is synchronized through the device DP', (
    tester,
  ) async {
    final result = await _pumpDisplaySettings(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('auto-brightness-switch')));
    await tester.pumpAndSettle();

    expect(
      result.state.deviceById('device-01')?.settings.autoBrightness,
      isFalse,
    );
    expect(result.repository.lastDps, <int, Object>{117: false});
    expect(find.text('已关闭'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('auto-brightness-switch')))
          .value,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'drag sends intermediate brightness and final zero without flooding',
    (tester) async {
      final result = await _pumpDisplaySettings(tester, const Size(375, 812));
      await tester.tap(find.byKey(const Key('auto-brightness-switch')));
      await tester.pumpAndSettle();
      result.repository.sentDps.clear();
      Slider slider() => tester.widget<Slider>(
        find.byKey(const Key('manual-brightness-slider')),
      );
      slider().onChanged!(80);
      slider().onChanged!(60);
      await tester.pump(const Duration(milliseconds: 119));
      expect(result.repository.sentDps, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(result.repository.sentDps, <Map<int, Object>>[
        {168: 60},
      ]);
      expect(slider().onChanged, isNotNull);
      slider().onChanged!(30);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      slider().onChanged!(0);
      slider().onChangeEnd!(0);
      await tester.pumpAndSettle();
      expect(result.repository.sentDps, <Map<int, Object>>[
        {168: 60},
        {168: 30},
        {168: 0},
      ]);
      expect(
        result.state.deviceById('device-01')?.settings.manualBrightness,
        0,
      );
      expect(find.text('0%'), findsOneWidget);
    },
  );

  testWidgets(
    'slow SDK send retains latest drag value and flushes zero after release',
    (tester) async {
      final result = await _pumpDisplaySettings(tester, const Size(375, 812));
      await tester.tap(find.byKey(const Key('auto-brightness-switch')));
      await tester.pumpAndSettle();
      result.repository.sentDps.clear();
      final gate = Completer<void>();
      result.repository.publishGate = gate.future;
      Slider slider() => tester.widget<Slider>(
        find.byKey(const Key('manual-brightness-slider')),
      );
      slider().onChanged!(70);
      await tester.pump(const Duration(milliseconds: 120));
      slider().onChanged!(40);
      slider().onChanged!(0);
      slider().onChangeEnd!(0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(result.repository.sentDps, <Map<int, Object>>[
        {168: 70},
      ]);
      expect(slider().value, 0);
      result.repository.publishGate = null;
      gate.complete();
      await tester.pumpAndSettle();
      expect(result.repository.sentDps, <Map<int, Object>>[
        {168: 70},
        {168: 0},
      ]);
      expect(
        result.state.deviceById('device-01')?.settings.manualBrightness,
        0,
      );
    },
  );

  testWidgets('leaving display cancels queued brightness writes', (
    tester,
  ) async {
    final result = await _pumpDisplaySettings(tester, const Size(375, 812));
    await tester.tap(find.byKey(const Key('auto-brightness-switch')));
    await tester.pumpAndSettle();
    result.repository.sentDps.clear();
    tester
        .widget<Slider>(find.byKey(const Key('manual-brightness-slider')))
        .onChanged!(0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(result.repository.sentDps, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'device brightness reports refresh slider and cancel draft when auto turns on',
    (tester) async {
      final result = await _pumpDisplaySettings(tester, const Size(375, 812));
      await result.state.initialize();
      result.repository.pushDeviceUpdate(
        DeviceUpdate.changed(
          _device.copyWith(
            settings: const DeviceControlSettings(
              autoBrightness: false,
              manualBrightness: 25,
            ),
          ),
          changedDps: {117, 168},
          reportedDps: {117: false, 168: 25},
        ),
      );
      await tester.pump();
      Slider slider() => tester.widget<Slider>(
        find.byKey(const Key('manual-brightness-slider')),
      );
      expect(slider().value, 25);
      slider().onChanged!(0);
      await tester.pump();
      result.repository.sentDps.clear();
      result.repository.pushDeviceUpdate(
        DeviceUpdate.changed(
          _device.copyWith(
            settings: const DeviceControlSettings(
              autoBrightness: true,
              manualBrightness: 40,
            ),
          ),
          changedDps: {117, 168},
          reportedDps: {117: true, 168: 40},
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(slider().value, 40);
      expect(slider().onChanged, isNull);
      expect(result.repository.sentDps, isEmpty);
      expect(
        tester
            .widget<Switch>(find.byKey(const Key('auto-brightness-switch')))
            .onChanged,
        isNotNull,
      );
    },
  );

  testWidgets('missing display device uses the shared error state', (
    tester,
  ) async {
    final repository = _DisplaySettingsRepository(includeDevice: false);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DisplaySettingsPage(deviceId: 'missing'),
        ),
      ),
    );

    expect(find.text('未找到设备'), findsOneWidget);
    expect(find.text('设备不存在或已经解绑。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device settings display item opens the full display page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _DisplaySettingsRepository();
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
            if (settings.name == AppRoutes.displaySettings) {
              routeArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('display-settings-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('显示'));
    await tester.pumpAndSettle();

    expect(find.text('display-settings-target'), findsOneWidget);
    expect(routeArguments, 'device-01');
    expect(tester.takeException(), isNull);
  });
}

Future<({FlowerpotState state, _DisplaySettingsRepository repository})>
_pumpDisplaySettings(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _DisplaySettingsRepository();
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const DisplaySettingsPage(deviceId: 'device-01'),
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
  settings: const DeviceControlSettings(autoBrightness: true),
  firmwareVersion: '1.0.0',
  macAddress: 'D8:85:AC:A2:B9:B4',
);

class _DisplaySettingsRepository extends MockTuyaRepository {
  _DisplaySettingsRepository({this.includeDevice = true})
    : super(latency: Duration.zero);

  final bool includeDevice;
  Map<int, Object>? lastDps;
  final sentDps = <Map<int, Object>>[];
  Future<void>? publishGate;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async =>
      includeDevice ? <SmartPlanterDevice>[_device] : <SmartPlanterDevice>[];

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    lastDps = dps;
    sentDps.add(Map<int, Object>.of(dps));
    await publishGate;
  }
}
