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

/// 空气温度日历史（DP 164）：变长日帧，**3 字节头**（年偏移 26、月 9、日 16）
/// 后面直接跟 uint16 BE 的点（十分之一度）。帧长 9，奇数，不可能是「4 字节头 +
/// N×2」，所以按 3 字节头解。
const _tempDailyHex = '1a0910' '00f6' '0102' '00d2';

/// 空气湿度日历史（DP 165）：固件 1.0.12 起**与 164 对称**——3 字节头 + uint16 BE
/// ×10 的点（此前是 1 字节整数 %）。帧长 9、奇数，同样按 3 字节头解。
///
/// 09-16 的导出把这一行写成 4 字节头（年 月 日 点数），那种帧 App 也照样解得出，
/// 见 `tuya_history_codec_test.dart` 里「4 字节头」那条。
const _humidityDailyHex = '1a0910' '0229' '01f4' '0258';

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
    '164': _tempDailyHex, // temp_daily_hist
    '165': _humidityDailyHex, // humi_daily_hist
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

    // 2026-09-16 的功能点表给温度、湿度补了日历史（164 / 165），周 / 月仍然没有。
    expect(TuyaConfig.history.keys, <String>[
      'waterLevel',
      'soilMoisture',
      'illuminance',
      'temperature',
      'humidity',
    ]);
    expect(
      TuyaConfig.history['illuminance']!.values.map(dp),
      <int>[137, 138, 139],
    );
    expect(TuyaConfig.history['temperature'], <String, String>{
      'day': 'temp_daily_hist',
    });
    expect(TuyaConfig.history['humidity'], <String, String>{
      'day': 'humi_daily_hist',
    });
    expect(dp('temp_daily_hist'), 164);
    expect(dp('humi_daily_hist'), 165);
  });

  test('164 / 165 的日历史解出来是还原过倍数的真值', () async {
    await repository.getDevices();

    // 164：3 字节头，uint16 BE，十分之一度。
    expect(
      await repository.getHistory(
        'dev-1',
        SensorMetric.temperature,
        ReportRange.day,
      ),
      <double>[24.6, 25.8, 21],
    );
    // 165：固件 1.0.12 起和 164 对称——3 字节头、uint16 BE、十分之一个百分点。
    expect(
      await repository.getHistory(
        'dev-1',
        SensorMetric.humidity,
        ReportRange.day,
      ),
      <double>[55.3, 50, 60],
    );
    // 只有日包，周 / 月没有。
    expect(
      await repository.getHistory(
        'dev-1',
        SensorMetric.temperature,
        ReportRange.week,
      ),
      isEmpty,
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
    );
    await state.logStatusDps(
      'dev-1',
      '相对湿度',
      HumidityStatusPageModel.reportedDps,
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
    // 2026-09-16 起四个状态页都有历史 DP，谁也不再补那一行。
    expect(
      state.interactionLog.where((line) => line.contains('没有这项的历史 DP')),
      isEmpty,
    );
  });

  test('温度、湿度状态页的历史体检只打自己那一条', () async {
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await repository.getDevices();

    await state.logHistoryDiagnostics(
      'dev-1',
      '空气温度',
      metrics: const <String>{'temperature'},
    );

    expect(state.interactionLog, hasLength(1));
    expect(
      state.interactionLog.single,
      contains('读取 ← [空气温度] 历史 temperature：日 DP164 hex 9字节/3点'),
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
