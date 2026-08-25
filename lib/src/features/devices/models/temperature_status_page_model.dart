import '../../../tuya/tuya_models.dart';

/// The comfortable band this app falls back on, in Celsius. The device
/// reports its own verdict through `air_temperature_status`; these numbers
/// only fill in until it does, and get converted for display.
const _comfortableLow = 18.0;
const _comfortableHigh = 28.0;

class TemperatureStatusPageModel {
  const TemperatureStatusPageModel({
    required this.deviceId,
    required this.status,
    required this.description,
    required this.temperature,
    required this.advice,
    this.settings = const DeviceControlSettings(),
  });

  factory TemperatureStatusPageModel.fromDevice(SmartPlanterDevice device) {
    final settings = device.settings;
    final temperature = device.sensors.airTemperature;
    // `air_temperature_status` (DP 113) when the device has reported it,
    // otherwise the app's own thresholds — which have to be moved into the
    // unit the device is reporting in before they mean anything.
    final low = settings.temperatureFromCelsius(_comfortableLow);
    final high = settings.temperatureFromCelsius(_comfortableHigh);
    final status = switch (device.status.temperature) {
      ComfortLevel.low => '偏低',
      ComfortLevel.suitable => '适宜',
      ComfortLevel.high => '偏高',
      null => switch (temperature) {
        _ when temperature < low => '偏低',
        _ when temperature > high => '偏高',
        _ => '适宜',
      },
    };
    final description = switch (status) {
      '偏低' => '当前空气温度偏低，请注意为植物保暖。',
      '偏高' => '当前空气温度偏高，请保持环境通风。',
      _ => '温度适宜植物生长。',
    };
    return TemperatureStatusPageModel(
      deviceId: device.id,
      status: status,
      description: description,
      temperature: temperature,
      advice:
          '适宜温度范围为'
          '${settings.formatCelsiusRange(_comfortableLow, _comfortableHigh)}。'
          '\n温度过高或过低都会影响植物健康生长哦。',
      settings: settings,
    );
  }

  final String deviceId;
  final String status;
  final String description;

  /// As the device reports it: already in [settings]'s unit.
  final double temperature;
  final String advice;
  final DeviceControlSettings settings;

  String get temperatureLabel => settings.formatTemperature(temperature);
  String get temperatureSymbol => settings.temperatureSymbol;
}
