import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('temperature unit (DP 146)', () {
    test('celsius labels the reading without converting it', () {
      const settings = DeviceControlSettings();

      expect(settings.temperatureSymbol, '°C');
      expect(settings.formatTemperature(24.6), '24.6°C');
      expect(settings.temperatureFromCelsius(18), 18);
    });

    test('fahrenheit only relabels: DP 112 already reports °F', () {
      const settings = DeviceControlSettings(temperatureUnit: 'fahrenheit');

      // 76.3 is what the device reports once it is switched to °F; converting
      // it again here is exactly the bug this guards.
      expect(settings.formatTemperature(76.3), '76.3°F');
      expect(settings.temperatureSymbol, '°F');
    });

    test('the app own comfort range moves into the device unit', () {
      const settings = DeviceControlSettings(temperatureUnit: 'fahrenheit');

      expect(settings.temperatureFromCelsius(18), closeTo(64.4, 0.01));
      expect(settings.formatCelsiusRange(18, 28), '64°F~82°F');
    });
  });

  group('clock format (DP 147)', () {
    test('24h labels pass through unchanged', () {
      const settings = DeviceControlSettings();

      expect(settings.formatClock('13:30'), '13:30');
      expect(settings.formatPeriod('23:00-07:00'), '23:00-07:00');
    });

    test('12h splits the day at noon and midnight', () {
      const settings = DeviceControlSettings(clockFormat: '12h');

      expect(settings.formatClock('13:30'), '下午 1:30');
      expect(settings.formatClock('00:15'), '上午 12:15');
      expect(settings.formatClock('12:00'), '下午 12:00');
      expect(settings.formatPeriod('23:00-07:00'), '下午 11:00-上午 7:00');
    });

    test('an unparsable label is left alone', () {
      const settings = DeviceControlSettings(clockFormat: '12h');

      expect(settings.formatClock('--:--'), '--:--');
      expect(settings.formatClock('25:00'), '25:00');
    });
  });
}
