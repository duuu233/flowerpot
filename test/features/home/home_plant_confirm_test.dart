import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/home/presentation/home_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _confirmKey = Key('app-dialog-confirm');
const _cancelKey = Key('app-dialog-cancel');

void main() {
  testWidgets('确认要过两道弹窗，第二道点确认才下发 162=2', (tester) async {
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(plantConfirm: PlantConfirmState.mismatch),
    ]);
    await _pumpDeviceHome(tester, repository);

    expect(find.text('植物确认'), findsOneWidget);
    expect(
      find.text('检测到花盆植物与app添加植物不一致，是否以花盆里的植物为准？'),
      findsOneWidget,
    );
    expect(find.text('忽略'), findsOneWidget);

    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();

    // 二次确认之前一条指令都不能发出去。
    expect(find.text('确认同步花盆植物'), findsOneWidget);
    expect(repository.published, isEmpty);

    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();

    expect(repository.published, <Map<int, Object>>[
      <int, Object>{162: 2},
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('忽略同样要过两道弹窗，第二道点确认才下发 162=3', (tester) async {
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(plantConfirm: PlantConfirmState.mismatch),
    ]);
    await _pumpDeviceHome(tester, repository);

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();

    expect(find.text('确认忽略本次检测'), findsOneWidget);
    expect(
      find.text('确认忽略此次检测，如有需要可以前往设置关闭植物自动检测'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();

    expect(repository.published, <Map<int, Object>>[
      <int, Object>{162: 3},
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('二次确认里取消就什么都不发', (tester) async {
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(plantConfirm: PlantConfirmState.mismatch),
    ]);
    await _pumpDeviceHome(tester, repository);

    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();

    expect(find.text('植物确认'), findsNothing);
    expect(repository.published, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关掉自动检测植物之后不再弹确认', (tester) async {
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(
        plantConfirm: PlantConfirmState.mismatch,
        plantDetection: false,
      ),
    ]);
    await _pumpDeviceHome(tester, repository);

    expect(find.text('植物确认'), findsNothing);
    expect(repository.published, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('162 正常时直接进详情页', (tester) async {
    final repository = _HomeRepository(<SmartPlanterDevice>[_device()]);
    await _pumpDeviceHome(tester, repository);

    expect(find.text('植物确认'), findsNothing);
    expect(repository.published, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DP 116 为空的花盆不会被问植物确认', (tester) async {
    // 这种设备走的是「直接进添加植物」那条路，不该在这里弹确认框。
    final repository = _HomeRepository(<SmartPlanterDevice>[
      _device(plantVariety: '', plantConfirm: PlantConfirmState.mismatch),
    ]);
    await _pumpDeviceHome(tester, repository);

    expect(find.text('植物确认'), findsNothing);
    expect(repository.published, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<FlowerpotState> _pumpDeviceHome(
  WidgetTester tester,
  _HomeRepository repository,
) async {
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
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

SmartPlanterDevice _device({
  String plantVariety = 'pothos',
  PlantConfirmState plantConfirm = PlantConfirmState.normal,
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
