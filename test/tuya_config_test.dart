import 'package:flowerpot/src/tuya/tuya_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the product DP table matches the platform export', () {
    // 101–162 来自 docs/智能花盆test(yciq4kssu1fv8umn)_09_07.xlsx，163 是自动
    // 检测植物开关的本地占位，平台补完导出后要回来核对这一行。
    expect(TuyaConfig.productId, 'yciq4kssu1fv8umn');
    expect(TuyaConfig.dp.length, 63);
    expect(TuyaConfig.dp.values.toSet().length, TuyaConfig.dp.length);
    expect(TuyaConfig.dp.values.reduce((a, b) => a < b ? a : b), 101);
    expect(TuyaConfig.dp.values.reduce((a, b) => a > b ? a : b), 163);
    expect(TuyaConfig.dp['soil_moist'], 106);
    expect(TuyaConfig.dp['vibration_switch'], 122);
    expect(TuyaConfig.dp['water_level_calib'], 140);
    // 09-03 新增的十条。
    expect(TuyaConfig.dp['standby_switch'], 151);
    expect(TuyaConfig.dp['standby_delay'], 152);
    expect(TuyaConfig.dp['language'], 153);
    expect(TuyaConfig.dp['memorial_set'], 154);
    expect(TuyaConfig.dp['del_photo'], 155);
    expect(TuyaConfig.dp['del_all_photos'], 156);
    expect(TuyaConfig.dp['pin_photo'], 157);
    expect(TuyaConfig.dp['memorial_birthday'], 158);
    expect(TuyaConfig.dp['memorial_wedding'], 159);
    expect(TuyaConfig.dp['op_result'], 160);
    // 09-07 新增的两条植物功能点，加上还没进导出的检测开关。
    expect(TuyaConfig.dp['plant_type'], 161);
    expect(TuyaConfig.dp['plant_confirm'], 162);
    expect(TuyaConfig.dp['plant_detect_switch'], 163);
  });

  test('植物分类只接受 161 的枚举值 1/2/3', () {
    expect(TuyaConfig.plantTypeValue(1), '1');
    expect(TuyaConfig.plantTypeValue(3), '3');
    expect(TuyaConfig.plantTypeValue(0), isNull);
    expect(TuyaConfig.plantTypeValue(4), isNull);
    expect(TuyaConfig.plantTypeValue(null), isNull);
  });

  test('自动检测植物是一条普通的开关设置', () {
    expect(TuyaConfig.settingDps('plantDetection', false), <int, Object>{
      163: false,
    });
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

  test('standby and language encode onto the 09-03 DPs', () {
    expect(TuyaConfig.settingDps('standby', true), <int, Object>{151: true});
    expect(TuyaConfig.settingDps('standbyDelay', 45), <int, Object>{152: 45});
    // 152 的范围是 1–180，超出的值夹回边界而不是原样下发。
    expect(TuyaConfig.settingDps('standbyDelay', 0), <int, Object>{152: 1});
    expect(TuyaConfig.settingDps('standbyDelay', 900), <int, Object>{152: 180});
    expect(TuyaConfig.settingDps('deviceLanguage', 'zh'), <int, Object>{
      153: 'Chinese',
    });
    expect(TuyaConfig.settingDps('deviceLanguage', 'en'), <int, Object>{
      153: 'English',
    });
    expect(TuyaConfig.settingDps('deviceLanguage', 'fr'), isNull);
  });

  test('LED rides on the display brightness DP', () {
    // 09-03 的功能点表里没有单独的 LED 开关，LED 页和显示页共用 117。
    expect(TuyaConfig.settingDps('led', false), <int, Object>{117: false});
    expect(
      TuyaConfig.settingDps('autoBrightness', false),
      TuyaConfig.settingDps('led', false),
    );
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
