import '../../support/plant_catalog.dart';
import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_info_page.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/device_settings_summary_card.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('device info page exposes the Figma content', (tester) async {
    await _pumpDeviceInfo(tester, const Size(375, 812));

    expect(find.text('更多设备信息'), findsOneWidget);
    expect(find.text('YSplanter-01'), findsOneWidget);
    expect(find.text('已陪伴52天'), findsOneWidget);
    expect(find.text('软件'), findsOneWidget);
    expect(find.text('固件版本'), findsOneWidget);
    expect(find.text('2.1.4'), findsOneWidget);
    expect(find.text('硬件'), findsOneWidget);
    expect(find.text('设备型号'), findsOneWidget);
    expect(find.text('YS 智能花盆'), findsOneWidget);
    expect(find.text('设备devId'), findsOneWidget);
    expect(find.text('6c1f9cacbfbe243ccaa2jy'), findsOneWidget);
    expect(find.text('硬件版本'), findsOneWidget);
    expect(find.text('26'), findsOneWidget);
    expect(findAssetImage(AppAssets.editIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2026-09-23：去掉 APP版本 / MAC / 两个 UUID；花盆没有 mac 地址行', (
    tester,
  ) async {
    await _pumpDeviceInfo(tester, const Size(375, 812));

    for (final gone in <String>[
      'APP版本',
      'MAC',
      'mac地址',
      '设备UUID',
      '花托UUID',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.text('D885ACA2B9B4'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设备型号读涂鸦产品名称（不是昵称）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _DeviceInfoRepository()..productName = '智能花盆 Pro';
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await state.refreshDevices();
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceInfoPage(deviceId: 'device-01'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('智能花盆 Pro'), findsOneWidget);
    expect(find.text('YSplanter-01'), findsOneWidget);
    expect(find.text('device-01'), findsOneWidget);
    expect(find.text('mac地址'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device info remains scrollable at 320x568', (tester) async {
    await _pumpDeviceInfo(tester, const Size(320, 568));

    final hardwareVersion = find.text('26');
    await tester.ensureVisible(hardwareVersion);
    await tester.pump();

    expect(hardwareVersion, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device name can be edited from the information card', (
    tester,
  ) async {
    await _pumpDeviceInfo(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('rename-device-info-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('device-info-name-field')),
      '阳台花盆',
    );
    await tester.tap(find.byKey(const Key('save-device-info-name')));
    await tester.pumpAndSettle();

    expect(find.text('阳台花盆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings summary opens the full device information page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = await _stateWithDevice();
    addTearDown(state.dispose);
    Object? routeArguments;

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceSettingsPage(deviceId: 'device-01'),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.deviceInfo) {
              routeArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('device-info-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(DeviceSettingsSummaryCard));
    await tester.pumpAndSettle();

    expect(find.text('device-info-target'), findsOneWidget);
    expect(routeArguments, 'device-01');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDeviceInfo(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = await _stateWithDevice();
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const DeviceInfoPage(
          deviceId: 'device-01',
          info: DeviceInfoData(
            firmwareVersion: '2.1.4',
            model: 'YS 智能花盆',
            deviceDevId: '6c1f9cacbfbe243ccaa2jy',
            hardwareVersion: '26',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<FlowerpotState> _stateWithDevice() async {
  final state = FlowerpotState(repository: _DeviceInfoRepository());
  await state.refreshDevices();
  return state;
}

SmartPlanterDevice get _device => SmartPlanterDevice(
  id: 'device-01',
  productId: '0C97B533',
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
  firmwareVersion: '2.1.4',
  macAddress: 'D8:85:AC:A2:B9:B4',
);

class _DeviceInfoRepository extends MockTuyaRepository {
  _DeviceInfoRepository() : super(latency: Duration.zero);

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    _device,
  ];
}
