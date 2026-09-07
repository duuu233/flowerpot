import '../../../tuya/tuya_models.dart';
import '../../../tuya/tuya_status_copy.dart';

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
    final level =
        device.status.temperature ??
        TuyaStatusCopy.temperatureFor(
          temperature,
          low: settings.temperatureFromCelsius(_comfortableLow),
          high: settings.temperatureFromCelsius(_comfortableHigh),
        );
    final copy = TuyaStatusCopy.airTemperature[level]!;
    return TemperatureStatusPageModel(
      deviceId: device.id,
      status: copy.label,
      description: copy.description,
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
