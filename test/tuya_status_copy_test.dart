import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_status_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('四条状态功能点的每个枚举值都有文案', () {
    for (final value in WaterNeedsStatus.values) {
      expect(TuyaStatusCopy.waterNeeds[value], isNotNull, reason: '$value');
    }
    for (final value in LightingCondition.values) {
      expect(TuyaStatusCopy.lighting[value], isNotNull, reason: '$value');
    }
    for (final value in ComfortLevel.values) {
      expect(TuyaStatusCopy.airTemperature[value], isNotNull, reason: '$value');
      expect(TuyaStatusCopy.airHumidity[value], isNotNull, reason: '$value');
    }
  });

  test('113 和 115 共用 ComfortLevel，但文案必须是两套', () {
    for (final value in ComfortLevel.values) {
      expect(
        TuyaStatusCopy.airTemperature[value]!.label,
        isNot(TuyaStatusCopy.airHumidity[value]!.label),
      );
    }
  });

  test('设备没上报时的兜底判据', () {
    // 107 看水仓水位（DP 105 量程 0–200 mL），不看土壤湿度。
    expect(TuyaStatusCopy.waterNeedsFor(5), WaterNeedsStatus.shortage);
    expect(TuyaStatusCopy.waterNeedsFor(80), WaterNeedsStatus.drinking);
    expect(TuyaStatusCopy.waterNeedsFor(180), WaterNeedsStatus.watery);

    expect(TuyaStatusCopy.lightingFor(100), LightingCondition.shortage);
    expect(TuyaStatusCopy.lightingFor(620), LightingCondition.good);
    expect(TuyaStatusCopy.lightingFor(2000), LightingCondition.veryGood);

    expect(TuyaStatusCopy.humidityFor(30), ComfortLevel.low);
    expect(TuyaStatusCopy.humidityFor(56), ComfortLevel.suitable);
    expect(TuyaStatusCopy.humidityFor(80), ComfortLevel.high);

    expect(
      TuyaStatusCopy.temperatureFor(12, low: 18, high: 28),
      ComfortLevel.low,
    );
    expect(
      TuyaStatusCopy.temperatureFor(24, low: 18, high: 28),
      ComfortLevel.suitable,
    );
    expect(
      TuyaStatusCopy.temperatureFor(31, low: 18, high: 28),
      ComfortLevel.high,
    );
    // 华氏度下阈值先换算，再比大小：24℃ 报成 75.2℉ 仍然是「正舒适」。
    expect(
      TuyaStatusCopy.temperatureFor(75.2, low: 64.4, high: 82.4),
      ComfortLevel.suitable,
    );
  });

  test('设备上报的枚举优先于兜底', () {
    const device = DeviceStatusReport(
      waterNeeds: WaterNeedsStatus.watery,
      lighting: LightingCondition.shortage,
    );
    expect(TuyaStatusCopy.waterNeeds[device.waterNeeds]!.label, '喝撑了');
    expect(TuyaStatusCopy.lighting[device.lighting]!.label, '晒不够');
  });
}
