import 'package:flowerpot/src/tuya/tuya_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plant DP identifiers are unique and stable', () {
    expect(TuyaConfig.dp.length, 23);
    expect(TuyaConfig.dp.values.toSet().length, TuyaConfig.dp.length);
    expect(TuyaConfig.dp['soilMoisture'], 102);
    expect(TuyaConfig.dp['repairSystem'], 123);
  });
}
