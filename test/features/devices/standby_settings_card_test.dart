import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/behavior_settings_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('休眠模式直接展开在「行为」页上，不再是一个入口', (tester) async {
    await _pumpBehavior(tester, const Size(375, 812));

    expect(find.text('休眠模式'), findsOneWidget);
    expect(find.text('无操作达到延迟时间后进入休眠'), findsOneWidget);
    expect(find.text('延迟时间'), findsOneWidget);
    // DeviceControlSettings 的默认延迟是 30 分钟。
    expect(find.text('30分'), findsOneWidget);
    expect(find.byKey(const Key('standby-switch')), findsOneWidget);
    expect(find.byKey(const Key('standby-delay-row')), findsOneWidget);
    // 二级页面和它的入口都没有了。
    expect(find.byKey(const Key('standby-settings-entry')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开关即时下发 DP 151', (tester) async {
    final result = await _pumpBehavior(tester, const Size(375, 812));

    final switchFinder = find.byKey(const Key('standby-switch'));
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(result.repository.lastDps, <int, Object>{151: true});
    expect(
      result.state.deviceById('device-01')?.settings.standbyEnabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('延迟时间点开弹窗改，保存写 DP 152', (tester) async {
    final result = await _pumpBehavior(tester, const Size(375, 812));

    await _openDelayDialog(tester);
    expect(find.byKey(const Key('standby-hour-wheel')), findsOneWidget);
    expect(find.byKey(const Key('standby-minute-wheel')), findsOneWidget);

    // 拨动分钟滚轮再保存：具体停在哪一格由滚轮自己收敛，这里只要求它确实变过、
    // 并且按保存后写的是 DP 152。
    await tester.drag(
      find.byKey(const Key('standby-minute-wheel')),
      const Offset(0, -132),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('standby-delay-save')));
    await tester.pumpAndSettle();

    final written = result.repository.lastDps;
    expect(written?.keys, <int>[152]);
    expect(written?[152], isNot(30));
    expect(
      result.state.deviceById('device-01')?.settings.standbyDelayMinutes,
      written?[152],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('弹窗取消不写 DP，原值不动', (tester) async {
    final result = await _pumpBehavior(tester, const Size(375, 812));

    await _openDelayDialog(tester);
    await tester.tap(find.byKey(const Key('standby-delay-cancel')));
    await tester.pumpAndSettle();

    expect(result.repository.lastDps, isNull);
    expect(find.text('30分'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存原样的延迟时间不发多余的 DP', (tester) async {
    final result = await _pumpBehavior(tester, const Size(375, 812));

    await _openDelayDialog(tester);
    await tester.tap(find.byKey(const Key('standby-delay-save')));
    await tester.pumpAndSettle();

    expect(result.repository.lastDps, isNull);
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
          home: const BehaviorSettingsPage(deviceId: 'missing'),
        ),
      ),
    );

    expect(find.text('未找到设备'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openDelayDialog(WidgetTester tester) async {
  final row = find.byKey(const Key('standby-delay-row'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('standby-delay-dialog')), findsOneWidget);
}

Future<({FlowerpotState state, _StandbyRepository repository})> _pumpBehavior(
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
        home: const BehaviorSettingsPage(deviceId: 'device-01'),
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
