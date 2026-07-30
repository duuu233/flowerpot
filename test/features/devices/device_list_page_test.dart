import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_list_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('device list page exposes the Figma content', (tester) async {
    await _pumpDeviceList(tester, const Size(375, 812));

    expect(find.text('设备列表'), findsOneWidget);
    expect(find.text('YSplanter-01'), findsOneWidget);
    expect(find.text('YSplanter-02'), findsOneWidget);
    expect(find.text('YSplanter-03'), findsOneWidget);
    expect(find.text('在线'), findsNWidgets(2));
    expect(find.text('离线'), findsOneWidget);
    expect(find.byKey(const Key('device-list-add-button')), findsOneWidget);
    expect(findAssetImage(AppAssets.addIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device list remains usable at 320x568', (tester) async {
    await _pumpDeviceList(tester, const Size(320, 568));

    final thirdDevice = find.text('YSplanter-03');
    await tester.ensureVisible(thirdDevice);
    await tester.pump();

    expect(thirdDevice, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add button opens the pairing flow', (tester) async {
    await _pumpDeviceList(tester, const Size(375, 812), withRoutes: true);

    await tester.tap(find.byKey(const Key('device-list-add-button')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-target'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device card selects the device and opens its dashboard', (
    tester,
  ) async {
    Object? dashboardArguments;
    final state = await _pumpDeviceList(
      tester,
      const Size(375, 812),
      withRoutes: true,
      onDashboardArguments: (value) => dashboardArguments = value,
    );

    await tester.tap(find.byKey(const Key('device-list-item-device-02')));
    await tester.pumpAndSettle();

    expect(find.text('device-dashboard-target'), findsOneWidget);
    expect(dashboardArguments, 'device-02');
    expect(state.selectedDevice?.id, 'device-02');
    expect(tester.takeException(), isNull);
  });
}

Future<FlowerpotState> _pumpDeviceList(
  WidgetTester tester,
  Size size, {
  bool withRoutes = false,
  ValueChanged<Object?>? onDashboardArguments,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(repository: _DeviceListRepository(_devices));
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const DeviceListPage(),
        onGenerateRoute: withRoutes
            ? (settings) {
                if (settings.name == AppRoutes.pairing) {
                  return MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('pairing-target')),
                    ),
                  );
                }
                if (settings.name == AppRoutes.device) {
                  onDashboardArguments?.call(settings.arguments);
                  return MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('device-dashboard-target')),
                    ),
                  );
                }
                return null;
              }
            : null,
      ),
    ),
  );
  await tester.pump();
  return state;
}

List<SmartPlanterDevice> get _devices => <SmartPlanterDevice>[
  _device(id: 'device-01', name: 'YSplanter-01', online: true),
  _device(id: 'device-02', name: 'YSplanter-02', online: true),
  _device(id: 'device-03', name: 'YSplanter-03', online: false),
];

SmartPlanterDevice _device({
  required String id,
  required String name,
  required bool online,
}) {
  return SmartPlanterDevice(
    id: id,
    productId: 'pid-smart-planter',
    name: name,
    online: online,
    signal: online ? 86 : 0,
    battery: 94,
    charging: false,
    boundAt: DateTime(2026),
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
    firmwareVersion: '1.0.8',
    macAddress: 'A4:C1:38:7B:2D:10',
  );
}

class _DeviceListRepository extends MockTuyaRepository {
  _DeviceListRepository(this.items) : super(latency: Duration.zero);

  final List<SmartPlanterDevice> items;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => items;
}
