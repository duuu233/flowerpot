import 'package:flowerpot/src/tuya/tuya_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the product DP table matches the platform export', () {
    // 101–165 来自 assets/智能花盆test(yciq4kssu1fv8umn)_09_16.xlsx，一个不缺、
    // 也没有多出来的号。
    expect(TuyaConfig.productId, 'yciq4kssu1fv8umn');
    // ⚠️ **键比 DP 号多两个**：162（plant_present / plant_confirm）和 163
    // （plant_confirm_switch / plant_detect_switch）各留了平台改名前后的两个
    // 标识符，好让按旧名查的地方也能查到。所以这里不能拿 `dp.length` 当 DP 个数
    // 比——2026-09-12 加别名时这条断言就是这么断的（`dp.length` 65 对 63）。
    expect(TuyaConfig.dp.length, 67);
    expect(
      TuyaConfig.dp.values.toSet(),
      List<int>.generate(65, (index) => 101 + index).toSet(),
    );
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
    // 09-07 新增的两条植物功能点，加上 09-12 正式导出的检测开关。
    expect(TuyaConfig.dp['plant_type'], 161);
    expect(TuyaConfig.dp['plant_confirm'], 162);
    expect(TuyaConfig.dp['plant_detect_switch'], 163);
    // 09-16 新增的两条日历史。
    expect(TuyaConfig.dp['temp_daily_hist'], 164);
    expect(TuyaConfig.dp['humi_daily_hist'], 165);
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
    for (final identifier in TuyaConfig.historyVariableFrames) {
      expect(TuyaConfig.dp, contains(identifier));
    }
    // 按指标查的两张表，键必须是 history 里真有的指标。
    for (final key in <String>[
      ...TuyaConfig.historySampleBytes.keys,
      ...TuyaConfig.historyScale.keys,
    ]) {
      expect(TuyaConfig.history, contains(key));
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

  test('LED 走自己的 166，和屏幕的 117 分开', () {
    // 2026-09-28 新增 DP 说明：166 双色 LED 与 117 屏幕是两个独立开关，APP 不要共用一个。
    expect(TuyaConfig.settingDps('led', true), <int, Object>{166: true});
    expect(
      TuyaConfig.settingDps('autoBrightness', false),
      <int, Object>{117: false},
    );
    expect(TuyaConfig.dp['ota_result'], 168);
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
