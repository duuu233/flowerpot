abstract final class TuyaConfig {
  /// Native SDK calls are opt-in so the project remains runnable before the
  /// platform-specific security components and credentials are supplied.
  static const enabled = bool.fromEnvironment('TUYA_ENABLED');

  static const channelName = 'com.common.yikaltd/tuya';
  static const defaultHomeName = '我的花园';

  /// Product DP mapping. Update this table to match the PID configured in the
  /// Tuya Developer Platform. All UI reads and writes go through these codes.
  static const dp = <String, int>{
    'waterLevel': 101,
    'soilMoisture': 102,
    'illuminance': 103,
    'ppfd': 104,
    'airTemperature': 105,
    'relativeHumidity': 106,
    'battery': 107,
    'charging': 108,
    'autoBrightness': 109,
    'soundInteraction': 110,
    'soundSensitivity': 111,
    'touchInteraction': 112,
    'touchSensitivity': 113,
    'vibration': 114,
    'napEnabled': 115,
    'napPeriod': 116,
    'nightEnabled': 117,
    'nightPeriod': 118,
    'weatherService': 119,
    'temperatureUnit': 120,
    'clockFormat': 121,
    'calibrateWaterLevel': 122,
    'repairSystem': 123,
  };
}
