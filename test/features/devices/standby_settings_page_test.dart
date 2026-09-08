import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/behavior_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/standby_settings_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('休眠模式页照雨淋设置的版式：开关 + 延迟时间滚轮 + 保存', (tester) async {
    await _pumpStandby(tester, const Size(375, 812));

    expect(find.text('休眠模式'), findsOneWidget);
    expect(find.text('开启'), findsOneWidget);
    expect(find.text('无操作达到延迟时间后进入休眠'), findsOneWidget);
    expect(find.text('延迟时间'), findsOneWidget);
    expect(find.byKey(const Key('standby-hour-wheel')), findsOneWidget);
    expect(find.byKey(const Key('standby-minute-wheel')), findsOneWidget);
    expect(find.byKey(const Key('standby-save-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开关即时下发 DP 151', (tester) async {
    final result = await _pumpStandby(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('standby-switch')));
    await tester.pumpAndSettle();

    expect(result.repository.lastDps, <int, Object>{151: true});
    expect(
      result.state.deviceById('device-01')?.settings.standbyEnabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存把滚轮上的延迟时间写进 DP 152', (tester) async {
    // 设备当前是 30 分钟（DeviceControlSettings 的默认值），页面打开即照它摆好
    // 滚轮，直接保存应当原样写回，而不是写成 0 或者越界值。
    final result = await _pumpStandby(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('standby-save-button')));
    await tester.pumpAndSettle();

    expect(result.repository.lastDps, <int, Object>{152: 30});
    expect(
      result.state.deviceById('device-01')?.settings.standbyDelayMinutes,
      30,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('设备不存在时用统一的错误态', (tester) async {
    final repository = _StandbyRepository(includeDevice: false);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const StandbySettingsPage(deviceId: 'missing'),
        ),
      ),
    );

    expect(find.text('未找到设备'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('入口在「行为」页，点进去带上 deviceId', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _StandbyRepository();
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await state.refreshDevices();
    Object? routeArguments;

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const BehaviorSettingsPage(deviceId: 'device-01'),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.standbySettings) {
              routeArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Center(child: Text('standby-target'))),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    final entry = find.byKey(const Key('standby-settings-entry'));
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('standby-target'), findsOneWidget);
    expect(routeArguments, 'device-01');
    expect(tester.takeException(), isNull);
  });
}

Future<({FlowerpotState state, _StandbyRepository repository})> _pumpStandby(
  WidgetTester tester,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _StandbyRepository();
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const StandbySettingsPage(deviceId: 'device-01'),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

class _StandbyRepository extends MockTuyaRepository {
  _StandbyRepository({this.includeDevice = true})
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
