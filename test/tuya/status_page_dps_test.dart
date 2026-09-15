import 'package:flowerpot/src/features/devices/models/humidity_status_page_model.dart';
import 'package:flowerpot/src/features/devices/models/light_status_page_model.dart';
import 'package:flowerpot/src/features/devices/models/temperature_status_page_model.dart';
import 'package:flowerpot/src/features/devices/models/water_status_page_model.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_config.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _methodChannel = 'test/tuya_status_dps';
const _eventChannel = 'test/tuya_status_dps_events';

/// 光照周包（DP 138）：年偏移 26、月 9、起始日 8、点数 7，后面 7 个 uint16 BE。
/// SDK 交上来的 raw 是十六进制串。
const _lightWeeklyHex =
    '1a090807' '0064' '012c' '01f4' '00c8' '0000' '0258' '0320';

Map<Object?, Object?> _deviceMap() => <Object?, Object?>{
  'deviceId': 'dev-1',
  'name': '客厅的绿意',
  'online': true,
  'dps': <Object?, Object?>{
    '105': 30, // water_level
    '106': 55, // soil_moist
    '107': 'drinking', // water_needs_status
    '108': 'good', // lighting_condition
    '109': 305, // light_intensity
    '110': 5, // light_ppfd_value
    '112': 246, // air_temperature，十分之一度
    // 113 air_temperature_status 故意不报。
    '114': 553, // air_humidity，十分之一个百分点
    '115': 'damp', // air_humidity_status
    '138': _lightWeeklyHex, // light_weekly_hist
  },
};

/// 2026-09-15 产品：首页已绑定设备下面四个子页面（需水 / 光照 / 空气温度 / 相对湿度）
/// 是一套逻辑，只是 DP 不同。这里按功能点表核每一页读的 DP。
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  late MethodChannelTuyaRepository repository;

  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(_methodChannel),
      (call) async =>
          call.method == 'getDevices' ? <Object?>[_deviceMap()] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannel),
      (call) async => null,
    );
    repository = MethodChannelTuyaRepository(
      channel: const MethodChannel(_methodChannel),
      events: const EventChannel(_eventChannel),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(_methodChannel),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannel),
      null,
    );
  });

  test('四个状态页读的 DP 号和功能点表一致', () {
    int dp(String identifier) => TuyaConfig.dp[identifier]!;

    expect(WaterStatusPageModel.reportedDps.map(dp), <int>[105, 106, 107]);
    expect(LightStatusPageModel.reportedDps.map(dp), <int>[109, 110, 108]);
    expect(TemperatureStatusPageModel.reportedDps.map(dp), <int>[112, 113, 146]);
    expect(HumidityStatusPageModel.reportedDps.map(dp), <int>[114, 115]);

    // 历史 DP 只有水位、土壤湿度、光照三组；温度、湿度没有。
    expect(TuyaConfig.history.keys, <String>[
      'waterLevel',
      'soilMoisture',
      'illuminance',
    ]);
    expect(
      TuyaConfig.history['illuminance']!.values.map(dp),
      <int>[137, 138, 139],
    );
  });

  test('光照历史 137–139 解出来挂在 SensorMetric.light 下，不在 dli 下', () async {
    await repository.getDevices();

    final light = await repository.getHistory(
      'dev-1',
      SensorMetric.light,
      ReportRange.week,
    );
    expect(light, <double>[100, 300, 500, 200, 0, 600, 800]);

    // 光照状态页以前读的是 dli：功能点表里没有 DLI 历史，永远是空的。
    expect(
      await repository.getHistory('dev-1', SensorMetric.dli, ReportRange.week),
      isEmpty,
    );
  });

  test('reportedDps 原样返回快照里的值，没报的是 null', () async {
    expect(await repository.reportedDps('dev-1', <String>['water_level']), isNull);

    await repository.getDevices();

    final values = await repository.reportedDps(
      'dev-1',
      TemperatureStatusPageModel.reportedDps,
    );
    expect(values, <String, Object?>{
      'air_temperature': 246,
      'air_temperature_status': null,
      'temp_unit_convert': null,
    });
  });

  test('状态页进页面把 DP 号、标识符和原始值记进联调日志', () async {
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await repository.getDevices();

    await state.logStatusDps(
      'dev-1',
      '空气温度',
      TemperatureStatusPageModel.reportedDps,
      hasHistoryDp: false,
    );
    await state.logStatusDps(
      'dev-1',
      '相对湿度',
      HumidityStatusPageModel.reportedDps,
      hasHistoryDp: false,
    );
    await state.logStatusDps(
      'dev-1',
      '光照状态',
      LightStatusPageModel.reportedDps,
    );

    final log = state.interactionLog.join('\n');
    expect(
      log,
      contains(
        '读取 ← [空气温度] DP112 air_temperature=246（÷10=24.6），'
        'DP113 air_temperature_status=未上报，DP146 temp_unit_convert=未上报',
      ),
    );
    expect(
      log,
      contains(
        '读取 ← [相对湿度] DP114 air_humidity=553（÷10=55.3），'
        'DP115 air_humidity_status=damp',
      ),
    );
    expect(
      log,
      contains(
        '读取 ← [光照状态] DP109 light_intensity=305，'
        'DP110 light_ppfd_value=5，DP108 lighting_condition=good',
      ),
    );
    // 温度、湿度补一行「没有历史 DP」；光照有历史 DP，不补。
    expect(
      state.interactionLog.where((line) => line.contains('没有这项的历史 DP')),
      hasLength(2),
    );
  });

  test('光照状态页的历史体检只打 137–139 那一组', () async {
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await repository.getDevices();

    await state.logHistoryDiagnostics(
      'dev-1',
      '光照状态',
      metrics: const <String>{'illuminance'},
    );

    expect(state.interactionLog, hasLength(1));
    expect(
      state.interactionLog.single,
      contains('读取 ← [光照状态] 历史 illuminance：日 DP137 无 · 周 DP138 hex 18字节/7点 · 月 DP139 无'),
    );
  });
}
