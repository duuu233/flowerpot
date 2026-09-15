import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/light_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/water_status_page.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/light_dli_bar_chart.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/water_trend_chart_card.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-09-15 产品：「四个子页面的报表数据会不会跟着涂鸦推送的 DP 变化实时变动」。
///
/// 以前不会——曲线只在进页面、切日 / 周 / 月时取一次。这里模拟停在页面上时设备推来
/// 历史 DP：曲线要跟着刷新；无关的上报（电量、别的指标的历史）不该让曲线重取。
void main() {
  testWidgets('需水状态：停在页面上时推来 DP131，曲线跟着刷新', (tester) async {
    final repository = _LiveHistoryRepository();
    final state = await _login(tester, repository);
    final deviceId = state.devices.single.id;

    await _pumpPage(tester, state, WaterStatusPage(deviceId: deviceId));
    expect(find.text('暂无历史数据'), findsOneWidget);
    expect(repository.historyCalls, 1);

    // 电量上报：这一页的历史没变，不重取。
    await _push(tester, repository, state, changedDps: <int>{103}, battery: 12);
    expect(repository.historyCalls, 1);

    // 设备推来水位日包（96 个点）。
    repository.reported = DeviceHistory(<String, List<double>>{
      DeviceHistory.key(SensorMetric.waterLevel, ReportRange.day):
          List<double>.generate(96, (index) => 80 + index % 30),
    });
    await _push(tester, repository, state, changedDps: <int>{131});

    expect(repository.historyCalls, 2);
    expect(find.text('暂无历史数据'), findsNothing);
    expect(find.byType(WaterTrendChartCard), findsOneWidget);
    expect(
      state.interactionLog.any(
        (line) => line.contains('上报 ← [需水状态] 历史 DP131 有新数据（96点），曲线已刷新'),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('光照状态：推来 DP138 刷新周曲线，土壤湿度历史变了不重取', (tester) async {
    final repository = _LiveHistoryRepository();
    final state = await _login(tester, repository);
    final deviceId = state.devices.single.id;

    await _pumpPage(tester, state, LightStatusPage(deviceId: deviceId));
    expect(find.text('暂无光照历史'), findsOneWidget);
    expect(repository.historyCalls, 1);

    // 别的指标的历史（土壤湿度 · 周）变了：光照这一段没变，不重取。
    repository.reported = DeviceHistory(<String, List<double>>{
      DeviceHistory.key(SensorMetric.soilMoisture, ReportRange.week):
          const <double>[40, 42, 45, 43, 41, 44, 46],
    });
    await _push(tester, repository, state, changedDps: <int>{135});
    expect(repository.historyCalls, 1);

    repository.reported = DeviceHistory(<String, List<double>>{
      DeviceHistory.key(SensorMetric.light, ReportRange.week):
          const <double>[100, 300, 500, 200, 0, 600, 800],
    });
    await _push(tester, repository, state, changedDps: <int>{138});

    expect(repository.historyCalls, 2);
    expect(find.text('暂无光照历史'), findsNothing);
    expect(find.byType(LightDliBarChart), findsOneWidget);
    expect(
      state.interactionLog.any(
        (line) => line.contains('上报 ← [光照状态] 历史 DP138 有新数据（7点），曲线已刷新'),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}

/// 曲线取数直接读「设备最近一次推来的历史」，和真仓库从快照解码是同一个意思。
class _LiveHistoryRepository extends MockTuyaRepository {
  _LiveHistoryRepository() : super(latency: Duration.zero);

  DeviceHistory reported = DeviceHistory.empty;
  int historyCalls = 0;

  @override
  Future<List<double>> getHistory(
    String deviceId,
    SensorMetric metric,
    ReportRange range,
  ) async {
    historyCalls++;
    return reported.series(metric, range);
  }
}

Future<FlowerpotState> _login(
  WidgetTester tester,
  _LiveHistoryRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  // 设备推送是在 initialize 里订阅的，不走这一步推了也没人收。
  await tester.runAsync(() async {
    await state.initialize();
    await state.login(
      account: '13800138000',
      credential: 'demo',
      region: LoginRegion.domestic,
      verificationCode: false,
    );
  });
  return state;
}

Future<void> _pumpPage(
  WidgetTester tester,
  FlowerpotState state,
  Widget page,
) async {
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(theme: buildAppTheme(), home: page),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 像真设备一样推一条上报：设备快照带着 [_LiveHistoryRepository.reported]。
Future<void> _push(
  WidgetTester tester,
  _LiveHistoryRepository repository,
  FlowerpotState state, {
  required Set<int> changedDps,
  int? battery,
}) async {
  final device = state.devices.single;
  repository.pushDeviceUpdate(
    DeviceUpdate.changed(
      device.copyWith(history: repository.reported, battery: battery),
      changedDps: changedDps,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}
