import '../../support/plant_catalog.dart';
import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/home/presentation/home_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _confirmKey = Key('app-dialog-confirm');
const _cancelKey = Key('app-dialog-cancel');

void main() {
  testWidgets('162 报 1 就弹「发现新植物」引导窗', (tester) async {
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(plantConfirm: PlantConfirmState.prompt),
    ]);
    await _pumpDeviceHome(tester, repository);

    expect(find.text('发现新植物'), findsOneWidget);
    // 植物名按 DP 116 的 id 从目录里读，读不到才写「新植物」。
    expect(find.text('已检测到绿萝植物，请确认植物。'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
    expect(find.text('选择植物'), findsOneWidget);
    expect(find.text('1、选择植物请确保与花盆植物一致'), findsOneWidget);
    expect(find.text('2、忽略检测结果，可前往设置关闭植物自动检测'), findsOneWidget);
    // 弹窗只是提示，还没有下发任何指令。
    expect(repository.published, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点「确认」把设备当前上报的植物 id 原样回写', (tester) async {
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(plantConfirm: PlantConfirmState.prompt),
    ]);
    await _pumpDeviceHome(tester, repository);

    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();

    // 116 写回设备刚报上来的那一株；不再写 162——固件收到 116 自己改回 0。
    expect(repository.published.single[116], 'pothos');
    expect(repository.published.single.containsKey(162), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点「选择植物」跳到植物选择流程，不直接下发', (tester) async {
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(plantConfirm: PlantConfirmState.prompt),
    ]);
    await _pumpDeviceHome(tester, repository, withRoutes: true);

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();

    expect(find.text('plant-picker-target'), findsOneWidget);
    expect(repository.published, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('植物 id 报 0（通用植物）时只给「选择植物」一个按钮', (tester) async {
    // 固件只认出「有植物」但认不出品种，后台也不再为 0 建植物数据，所以没有可
    // 确认的对象：文案换成「请选择并确认植物」，确认按钮不出现。
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(plantVariety: '0', plantConfirm: PlantConfirmState.prompt),
    ]);
    await _pumpDeviceHome(tester, repository, withRoutes: true);

    expect(find.text('发现新植物'), findsOneWidget);
    expect(find.text('已检测到通用植物，请选择并确认植物。'), findsOneWidget);
    expect(find.text('选择植物'), findsOneWidget);
    expect(find.text('确认'), findsNothing);
    // 两条提示文案照旧。
    expect(find.text('1、选择植物请确保与花盆植物一致'), findsOneWidget);

    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();

    // 唯一那个按钮走的是「去选植物」，不能把 0 当成确认下发。
    expect(find.text('plant-picker-target'), findsOneWidget);
    expect(repository.published, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('162 报 0 不弹窗', (tester) async {
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(plantConfirm: PlantConfirmState.hidden),
    ]);
    await _pumpDeviceHome(tester, repository);

    expect(find.text('发现新植物'), findsNothing);
    expect(repository.published, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('116 报 -1：画未种植物的花盆，今日养护换成提示，也不弹窗', (tester) async {
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(plantVariety: '-1'),
    ]);
    await _pumpDeviceHome(tester, repository);

    expect(find.text('发现新植物'), findsNothing);
    expect(find.byKey(const Key('home-care-notice')), findsOneWidget);
    expect(find.text('未检测到植物，请将植物种入花盆。'), findsOneWidget);
    // 养护建议整行被替换掉，标题也不再显示。
    expect(find.text('今日养护'), findsNothing);
    expect(tester.takeException(), isNull);
  });

}

Future<FlowerpotState> _pumpDeviceHome(
  WidgetTester tester,
  _HomeRepository repository, {
  bool withRoutes = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const HomePage(deviceId: 'device-01', showBackButton: true),
        onGenerateRoute: withRoutes
            ? (settings) {
                if (settings.name == AppRoutes.plantPicker) {
                  return MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('plant-picker-target')),
                    ),
                  );
                }
                return null;
              }
            : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

SmartPlanterDevice _device({
  String plantVariety = 'pothos',
  PlantConfirmState plantConfirm = PlantConfirmState.hidden,
  bool plantDetection = true,
}) {
  return SmartPlanterDevice(
    id: 'device-01',
    productId: 'pid-smart-planter',
    name: 'YSplanter-01',
    online: true,
    signal: 86,
    battery: 94,
    charging: false,
    boundAt: DateTime(2026),
    plant: PlantCatalog.items.first,
    sensors: const SensorSnapshot(
      waterLevel: 80,
      soilMoisture: 60,
      illuminance: 800,
      ppfd: 5.6,
      airTemperature: 24.5,
      relativeHumidity: 52,
    ),
    settings: DeviceControlSettings(plantDetection: plantDetection),
    firmwareVersion: '1.0.8',
    macAddress: 'A4:C1:38:7B:2D:10',
    plantVariety: plantVariety,
    plantConfirm: plantConfirm,
  );
}

class _HomeRepository extends MockTuyaRepository {
  _HomeRepository(this.items) : super(latency: Duration.zero);

  final List<SmartPlanterDevice> items;
  final List<Map<int, Object>> published = <Map<int, Object>>[];

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => items;

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    published.add(dps);
    await super.publishDps(deviceId, dps);
  }
}
