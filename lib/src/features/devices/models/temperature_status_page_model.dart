import '../../../tuya/tuya_models.dart';
import '../../../tuya/tuya_status_copy.dart';

/// The comfortable band this app falls back on, in Celsius. The device
/// reports its own verdict through `air_temperature_status`; these numbers
/// only fill in until it does, and get converted for display. 首页的养护建议读
/// 的是同一份，所以放在 [TuyaStatusCopy] 上而不是各写一份。
const _comfortableLow = TuyaStatusCopy.comfortableLowCelsius;
const _comfortableHigh = TuyaStatusCopy.comfortableHighCelsius;

class TemperatureStatusPageModel {
  const TemperatureStatusPageModel({
    required this.deviceId,
    required this.status,
    required this.description,
    required this.temperature,
    required this.advice,
    this.settings = const DeviceControlSettings(),
  });

  /// [language] 决定文案取中文还是英文表，见 [TuyaStatusCopy]。
  factory TemperatureStatusPageModel.fromDevice(
    SmartPlanterDevice device, {
    String language = 'zh',
  }) {
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
    final copy = TuyaStatusCopy.airTemperatureCopy(level, language: language);
    return TemperatureStatusPageModel(
      deviceId: device.id,
      status: copy.label,
      description: copy.description,
      temperature: temperature,
      // 养护建议由产品统一给稿，和状态文字同一张表，见 TuyaStatusCopy。
      advice: copy.advice,
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
