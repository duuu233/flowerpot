import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/temperature_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/temperature_trend_chart_card.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-09-15 产品：「只要涂鸦推送了，报表就是要实时动，往前移动那种效果」「不需要做
/// 特殊的处理，跟以前那些数据一样的渲染」。
///
/// 曲线和顶部读数一样在 build 里现读 `FlowerpotState.chartSeries`：底子是设备的历史包，
/// 日视图后面接上每次推送的实时值，新点从右边进、满了挤掉最左边。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('推一次 105，水位日曲线右边多一个点；周曲线不接实时值', () async {
    final (state, repository) = await _session();
    final id = state.devices.single.id;
    final packet = state.chartSeries(id, SensorMetric.waterLevel, ReportRange.day);
    final week = state.chartSeries(id, SensorMetric.waterLevel, ReportRange.week);
    expect(packet, hasLength(24));

    await _push(repository, state, <int>{105}, waterLevel: 61);

    final day = state.chartSeries(id, SensorMetric.waterLevel, ReportRange.day);
    expect(day, <double>[...packet, 61]);
    expect(
      state.chartSeries(id, SensorMetric.waterLevel, ReportRange.week),
      week,
    );
    // 别的指标的曲线不受影响。
    expect(
      state.chartSeries(id, SensorMetric.soilMoisture, ReportRange.day),
      hasLength(24),
    );
  });

  test('值没变也算一次推送；电量推送不动曲线', () async {
    final (state, repository) = await _session();
    final id = state.devices.single.id;

    await _push(repository, state, <int>{105}, waterLevel: 80);
    await _push(repository, state, <int>{105}, waterLevel: 80);
    final before = state.chartSeries(id, SensorMetric.waterLevel, ReportRange.day);
    expect(before, hasLength(26));

    await _push(repository, state, <int>{103}, battery: 12);
    // 同一个列表：图表不会因为无关的重建丢掉选中的点。
    expect(
      identical(
        state.chartSeries(id, SensorMetric.waterLevel, ReportRange.day),
        before,
      ),
      isTrue,
    );
  });

  test('满 96 个点后每推一次整条往前移一格；推来新日包以包为准', () async {
    final (state, repository) = await _session();
    final id = state.devices.single.id;
    final packet = List<double>.generate(96, (index) => index.toDouble());

    await _push(
      repository,
      state,
      <int>{131},
      history: DeviceHistory(<String, List<double>>{
        DeviceHistory.key(SensorMetric.waterLevel, ReportRange.day): packet,
      }),
    );
    expect(state.chartSeries(id, SensorMetric.waterLevel, ReportRange.day), packet);

    await _push(repository, state, <int>{105}, waterLevel: 150);
    await _push(repository, state, <int>{105}, waterLevel: 160);
    final moved = state.chartSeries(id, SensorMetric.waterLevel, ReportRange.day);
    expect(moved, hasLength(FlowerpotState.liveChartWindow));
    expect(moved.first, 2);
    expect(moved.sublist(94), <double>[150, 160]);

    // 设备推来新的日包：之前接上的实时点已经算进包里了，清掉。
    final next = List<double>.generate(96, (index) => 100 + index.toDouble());
    await _push(
      repository,
      state,
      <int>{131},
      history: DeviceHistory(<String, List<double>>{
        DeviceHistory.key(SensorMetric.waterLevel, ReportRange.day): next,
      }),
    );
    expect(state.chartSeries(id, SensorMetric.waterLevel, ReportRange.day), next);
  });

  testWidgets('设备还没推 164 日包时：推一次 112 曲线就出来，再推往前走', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockTuyaRepository(latency: Duration.zero);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await tester.runAsync(() async {
      await _start(state);
      // 设备还没报 164 的那一段：把演示设备的历史清空，曲线只能靠推送攒。
      await _push(
        repository,
        state,
        const <int>{},
        history: DeviceHistory.empty,
      );
    });
    final id = state.devices.single.id;

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TemperatureStatusPage(deviceId: id),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('暂无温度历史'), findsOneWidget);

    await tester.runAsync(
      () => _push(repository, state, <int>{112}, temperature: 24.6),
    );
    await tester.pump();
    expect(find.text('暂无温度历史'), findsNothing);
    expect(
      tester
          .widget<TemperatureTrendChartCard>(
            find.byType(TemperatureTrendChartCard),
          )
          .values,
      <double>[24.6],
    );

    await tester.runAsync(
      () => _push(repository, state, <int>{112}, temperature: 25.1),
    );
    await tester.pump();
    expect(
      tester
          .widget<TemperatureTrendChartCard>(
            find.byType(TemperatureTrendChartCard),
          )
          .values,
      <double>[24.6, 25.1],
    );
    expect(tester.takeException(), isNull);
  });
}

Future<(FlowerpotState, MockTuyaRepository)> _session() async {
  final repository = MockTuyaRepository(latency: Duration.zero);
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await _start(state);
  return (state, repository);
}

Future<void> _start(FlowerpotState state) async {
  // 设备推送是在 initialize 里订阅的，不走这一步推了也没人收。
  await state.initialize();
  await state.login(
    account: '13800138000',
    credential: 'demo',
    region: LoginRegion.domestic,
    verificationCode: false,
  );
}

/// 像真设备一样推一条上报：只改这次报文带的值，其余沿用当前设备。
Future<void> _push(
  MockTuyaRepository repository,
  FlowerpotState state,
  Set<int> changedDps, {
  int? waterLevel,
  double? temperature,
  int? battery,
  DeviceHistory? history,
}) async {
  final device = state.devices.single;
  final sensors = device.sensors;
  repository.pushDeviceUpdate(
    DeviceUpdate.changed(
      device.copyWith(
        battery: battery,
        history: history,
        sensors: SensorSnapshot(
          waterLevel: waterLevel ?? sensors.waterLevel,
          soilMoisture: sensors.soilMoisture,
          illuminance: sensors.illuminance,
          ppfd: sensors.ppfd,
          par: sensors.par,
          airTemperature: temperature ?? sensors.airTemperature,
          relativeHumidity: sensors.relativeHumidity,
        ),
      ),
      changedDps: changedDps,
    ),
  );
  await Future<void>.delayed(Duration.zero);
}
