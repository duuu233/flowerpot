import '../../support/plant_catalog.dart';
import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_list_page.dart';
import 'package:flowerpot/src/features/home/models/home_dashboard_model.dart';
import 'package:flowerpot/src/features/home/presentation/home_page.dart';
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

  testWidgets('the header leads to the profile centre instead of going back', (
    tester,
  ) async {
    await _pumpDeviceList(tester, const Size(375, 812), withRoutes: true);

    expect(find.byKey(const Key('device-list-profile-button')), findsOneWidget);
    expect(find.byType(AppBackButton), findsNothing);

    await tester.tap(find.byKey(const Key('device-list-profile-button')));
    await tester.pumpAndSettle();

    expect(find.text('mine-target'), findsOneWidget);
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

  testWidgets('add button starts the pairing flow with the device search', (
    tester,
  ) async {
    await _pumpDeviceList(tester, const Size(375, 812), withRoutes: true);

    await tester.tap(find.byKey(const Key('device-list-add-button')));
    await tester.pumpAndSettle();

    expect(find.text('device-search-target'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有植物的花盆也直接进详情页，不再先拦去选植物', (tester) async {
    // 植物的有无由设备上报的 116（-1 / 0..N）决定，详情页自己会画「未检测到
    // 植物」，也会在设备要求时弹引导窗；列表页不再替设备做这个判断。
    Object? deviceArguments;
    final state = await _pumpDeviceList(
      tester,
      const Size(375, 812),
      withRoutes: true,
      onDeviceArguments: (value) => deviceArguments = value,
    );

    await tester.tap(find.byKey(const Key('device-list-item-device-02')));
    await tester.pumpAndSettle();

    expect(find.text('device-home-target'), findsOneWidget);
    expect(find.text('plant-picker-target'), findsNothing);
    expect(state.selectedDevice?.id, 'device-02');
    expect((deviceArguments! as HomeDeviceArguments).deviceId, 'device-02');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an offline device is not allowed into the device page', (
    tester,
  ) async {
    Object? deviceArguments;
    Object? pickerArguments;
    await _pumpDeviceList(
      tester,
      const Size(375, 812),
      withRoutes: true,
      onDeviceArguments: (value) => deviceArguments = value,
      onPlantPickerArguments: (value) => pickerArguments = value,
    );

    await tester.tap(find.byKey(const Key('device-list-item-device-03')));
    await tester.pumpAndSettle();

    expect(find.text('设备已离线'), findsOneWidget);
    expect(deviceArguments, isNull);
    expect(pickerArguments, isNull);
    // 还留在列表页。
    expect(find.text('设备列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a device with a chosen plant opens the detail page', (
    tester,
  ) async {
    Object? deviceArguments;
    final state = await _pumpDeviceList(
      tester,
      const Size(375, 812),
      withRoutes: true,
      onDeviceArguments: (value) => deviceArguments = value,
    );
    await state.selectPlant('device-02', PlantCatalog.items.first);
    await tester.pump();

    await tester.tap(find.byKey(const Key('device-list-item-device-02')));
    await tester.pumpAndSettle();

    final arguments = deviceArguments! as HomeDeviceArguments;
    expect(arguments.scene, HomeDashboardScene.withCompanionSummary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设备列表读不出来时给错误和重试，而不是「暂无设备」', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FlakyDeviceListRepository(_devices);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);

    // 第一次读取失败：登录路径吞掉异常，列表就是空的——「重新登录后设备全没了」
    // 的现场就是这样。
    await expectLater(state.refreshDevices(), throwsA(isA<TuyaException>()));
    expect(state.deviceLoadError, contains('home_query_failed'));

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(theme: buildAppTheme(), home: const DeviceListPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('device-list-error')), findsOneWidget);
    expect(find.text('设备列表没读出来'), findsOneWidget);
    // 不能再画成「暂无设备」。
    expect(find.text('暂无设备'), findsNothing);
    expect(
      find.byKey(const Key('empty-device-list-illustration')),
      findsNothing,
    );
    // 现场信息直接画在页面上：查的是哪个家庭、读到几台，不用再进联调页。
    final diagnostics = tester.widget<SelectableText>(
      find.byKey(const Key('device-list-diagnostics')),
    );
    expect(diagnostics.data, contains('设备 0 台'));
    expect(diagnostics.data, contains('家庭'));

    // 重试成功后恢复成正常列表。
    repository.failing = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('device-list-error')), findsNothing);
    expect(find.text('YSplanter-01'), findsOneWidget);
    expect(state.deviceLoadError, isNull);
    expect(tester.takeException(), isNull);
  });

}

Future<FlowerpotState> _pumpDeviceList(
  WidgetTester tester,
  Size size, {
  bool withRoutes = false,
  ValueChanged<Object?>? onDeviceArguments,
  ValueChanged<Object?>? onPlantPickerArguments,
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
                if (settings.name == AppRoutes.deviceSearch) {
                  return MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('device-search-target')),
                    ),
                  );
                }
                if (settings.name == AppRoutes.deviceHome) {
                  onDeviceArguments?.call(settings.arguments);
                  return MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('device-home-target')),
                    ),
                  );
                }
                if (settings.name == AppRoutes.plantPicker) {
                  onPlantPickerArguments?.call(settings.arguments);
                  return MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('plant-picker-target')),
                    ),
                  );
                }
                if (settings.name == AppRoutes.mine) {
                  return MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('mine-target')),
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

/// 先失败后成功：第一次 `getDevices` 抛错，`failing` 置回 false 后恢复正常。
class _FlakyDeviceListRepository extends MockTuyaRepository {
  _FlakyDeviceListRepository(this.items) : super(latency: Duration.zero);

  final List<SmartPlanterDevice> items;
  bool failing = true;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async {
    if (failing) {
      throw const TuyaException('home_query_failed', '家庭列表查询失败');
    }
    return items;
  }
}

class _DeviceListRepository extends MockTuyaRepository {
  _DeviceListRepository(this.items) : super(latency: Duration.zero);

  final List<SmartPlanterDevice> items;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => items;
}
