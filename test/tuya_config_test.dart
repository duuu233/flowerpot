import 'package:flowerpot/src/tuya/tuya_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the product DP table matches the platform export', () {
    // 101–150 inclusive, one row per function point in
    // assets/智能花盆test(orhqsdjyigmh8bwa)_08_20.xlsx.
    expect(TuyaConfig.dp.length, 50);
    expect(TuyaConfig.dp.values.toSet().length, TuyaConfig.dp.length);
    expect(TuyaConfig.dp.values.reduce((a, b) => a < b ? a : b), 101);
    expect(TuyaConfig.dp.values.reduce((a, b) => a > b ? a : b), 150);
    expect(TuyaConfig.dp['soil_moist'], 106);
    expect(TuyaConfig.dp['vibration_switch'], 122);
    expect(TuyaConfig.dp['water_level_calib'], 140);
  });

  test('every app-facing name resolves to a real DP', () {
    for (final identifier in TuyaConfig.setting.values) {
      expect(TuyaConfig.dp, contains(identifier));
    }
    for (final ranges in TuyaConfig.history.values) {
      for (final identifier in ranges.values) {
        expect(TuyaConfig.dp, contains(identifier));
      }
    }
    for (final identifier in TuyaConfig.dpScale.keys) {
      expect(TuyaConfig.dp, contains(identifier));
    }
  });

  test('switch settings encode to a single DP', () {
    expect(TuyaConfig.settingDps('vibration', true), <int, Object>{122: true});
    expect(TuyaConfig.settingDps('soundSensitivity', 35), <int, Object>{
      119: 35,
    });
  });

  test('schedules encode to the start and end minute DPs', () {
    expect(TuyaConfig.settingDps('napPeriod', '11:45-13:30'), <int, Object>{
      126: 705,
      127: 810,
    });
    expect(TuyaConfig.settingDps('nightPeriod', '22:00-06:45'), <int, Object>{
      129: 1320,
      130: 405,
    });
    expect(TuyaConfig.settingDps('napPeriod', '11:45'), isNull);
    expect(TuyaConfig.settingDps('napPeriod', '25:00-13:30'), isNull);
  });

  test('the temperature unit maps onto the device enum', () {
    expect(TuyaConfig.settingDps('temperatureUnit', 'celsius'), <int, Object>{
      146: 'C',
    });
    expect(
      TuyaConfig.settingDps('temperatureUnit', 'fahrenheit'),
      <int, Object>{146: 'F'},
    );
    expect(TuyaConfig.settingDps('temperatureUnit', 'kelvin'), isNull);
  });

  test('a setting the product has no DP for reports as unsupported', () {
    expect(TuyaConfig.settingDps('weatherService', true), isNull);
    expect(TuyaConfig.settingDps('repairSystem', true), isNull);
  });

  test('clock labels round-trip through minutes past midnight', () {
    expect(TuyaConfig.minutesOfDay('00:00'), 0);
    expect(TuyaConfig.minutesOfDay('23:59'), 1439);
    expect(TuyaConfig.minutesOfDay('24:00'), isNull);
    expect(TuyaConfig.minutesOfDay('12-30'), isNull);
    expect(TuyaConfig.clockLabel(705), '11:45');
    // The DP range ends at 1440, which is midnight at the far end of the day.
    expect(TuyaConfig.clockLabel(1440), '00:00');
    expect(TuyaConfig.clockLabel(1441), isNull);
    expect(TuyaConfig.clockLabel(-1), isNull);
  });
}
