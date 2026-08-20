abstract final class TuyaConfig {
  /// Native SDK calls are opt-in so the project remains runnable before the
  /// platform-specific security components and credentials are supplied.
  static const enabled = bool.fromEnvironment('TUYA_ENABLED');

  static const channelName = 'com.common.yikaltd/tuya';
  static const defaultHomeName = '我的花园';

  /// PID the [dp] table below was exported from.
  ///
  /// Only used to label the table; the app never sends it. A device bound to a
  /// different PID reports different DP ids, so re-export the table instead of
  /// editing rows by hand.
  static const productId = 'orhqsdjyigmh8bwa';

  /// Product DP table, keyed by the Tuya *identifier* rather than by an app
  /// concept, so a row can be diffed against the platform export character for
  /// character. App-facing names resolve through [setting] and [history];
  /// sensor reads name their identifier at the point of use.
  ///
  /// Source: `assets/智能花盆test(orhqsdjyigmh8bwa)_08_20.xlsx`, sheet 功能点,
  /// exported 2026-08-20.
  static const dp = <String, int>{
    // Reported state.
    'device_status': 101, // string, rw
    'together_days': 102, // value 1-1100 天, reported once a day at 00:00
    'battery_level': 103, // value 0-100 %
    'battery_status': 104, // enum shortage/good/charging
    'water_level': 105, // value 0-200 mL
    'soil_moist': 106, // value 0-100 %
    'water_needs_status': 107, // enum shortage/drinking/watery
    'lighting_condition': 108, // enum shortage/good/very_good
    'light_intensity': 109, // value 0-9000 lux
    'light_ppfd_value': 110, // value 0-9000 μmol/m²/s
    'light_par_value': 111, // value 0-9000 μmol/m²
    'air_temperature': 112, // value 0-2200, 倍数 1 -> tenths of a degree
    'air_temperature_status': 113, // enum cold/suitable/heat
    'air_humidity': 114, // value 0-1000, 倍数 1 -> tenths of a percent
    'air_humidity_status': 115, // enum dry/suitable/damp
    'plant_variety': 116, // string

    // Control.
    'disp_brightness_switch': 117, // bool
    'voice_interaction_switch': 118, // bool
    'sound_sensitivity': 119, // value 0-100 %
    'touch_interact_switch': 120, // bool
    'touch_sense_sensitivity': 121, // value 0-100 %
    'vibration_switch': 122, // bool
    'touch_vib_switch': 123, // bool
    'touch_plant_vib_switch': 124, // bool
    'nap_time_switch': 125, // bool
    'nap_start_time': 126, // value 0-1440 minutes past midnight
    'nap_end_time': 127, // value 0-1440 minutes past midnight
    'night_sleep_switch': 128, // bool
    'night_sleep_start_time': 129, // value 0-1440 minutes past midnight
    'night_sleep_end_time': 130, // value 0-1440 minutes past midnight

    // Reported history, raw. See `TuyaHistoryCodec` for the byte layout.
    'tank_level_daily_hist': 131,
    'tank_level_weekly_hist': 132,
    'tank_level_monthly_hist': 133,
    'soil_moist_daily_hist': 134,
    'soil_moist_weekly_hist': 135,
    'soil_moist_monthly_hist': 136,
    'light_daily_hist': 137,
    'light_weekly_hist': 138,
    'light_monthly_hist': 139,

    // Maintenance and media.
    'water_level_calib': 140, // enum step0..step5, step5 cancels
    'factory_reset': 141, // bool, write only
    'dl_url': 142, // raw, write only
    'dl_show': 143, // string, write only
    'dl_cancel': 144, // bool, write only
    'charge_status': 145, // bool
    'temp_unit_convert': 146, // enum C/F
    'time_format': 147, // enum 24h/12h
    'firmware_version': 148, // string
    'hardware_version': 149, // value 1-100
    're_pairing': 150, // bool, write only
  };

  /// DPs the device transmits as an integer scaled by a power of ten (涂鸦
  /// "倍数"). Reads divide, writes multiply.
  static const dpScale = <String, int>{
    'air_temperature': 10,
    'air_humidity': 10,
  };

  /// Writable settings the app exposes, mapped to the DP that backs them.
  ///
  /// The two schedules are absent because each spans a pair of DPs; they are
  /// resolved by [settingDps] instead.
  static const setting = <String, String>{
    'autoBrightness': 'disp_brightness_switch',
    'soundInteraction': 'voice_interaction_switch',
    'soundSensitivity': 'sound_sensitivity',
    'touchInteraction': 'touch_interact_switch',
    'touchSensitivity': 'touch_sense_sensitivity',
    'vibration': 'vibration_switch',
    'touchKeyVibration': 'touch_vib_switch',
    'touchPlantVibration': 'touch_plant_vib_switch',
    'napEnabled': 'nap_time_switch',
    'nightEnabled': 'night_sleep_switch',
    'temperatureUnit': 'temp_unit_convert',
    'clockFormat': 'time_format',
  };

  /// Reported history series, keyed by app metric then by range.
  static const history = <String, Map<String, String>>{
    'waterLevel': <String, String>{
      'day': 'tank_level_daily_hist',
      'week': 'tank_level_weekly_hist',
      'month': 'tank_level_monthly_hist',
    },
    'soilMoisture': <String, String>{
      'day': 'soil_moist_daily_hist',
      'week': 'soil_moist_weekly_hist',
      'month': 'soil_moist_monthly_hist',
    },
    'illuminance': <String, String>{
      'day': 'light_daily_hist',
      'week': 'light_weekly_hist',
      'month': 'light_monthly_hist',
    },
  };

  /// Bytes per sample in the raw history DPs. Everything but light is a single
  /// unsigned byte.
  static const historySampleBytes = <String, int>{'illuminance': 2};

  /// `temp_unit_convert` enum values against the labels the settings sheet
  /// uses.
  static const temperatureUnits = <String, String>{
    'celsius': 'C',
    'fahrenheit': 'F',
  };

  /// Steps of `water_level_calib`, indexed by the calibration dialog step the
  /// user just confirmed.
  ///
  /// The platform export only says "步骤" and that step5 cancels, so which
  /// stage each value samples is a firmware detail: confirm the mapping
  /// against the device before shipping calibration.
  static const calibrationSteps = <String>['step0', 'step1', 'step2', 'step3'];
  static const calibrationCancel = 'step5';

  /// Encodes one app setting into the DPs that carry it.
  ///
  /// Returns null when the product has no DP for [key], which is how the app
  /// tells "not wired up yet" apart from "the device rejected it".
  static Map<int, Object>? settingDps(String key, Object value) {
    switch (key) {
      case 'napPeriod':
        return _periodDps('nap_start_time', 'nap_end_time', value);
      case 'nightPeriod':
        return _periodDps(
          'night_sleep_start_time',
          'night_sleep_end_time',
          value,
        );
      case 'temperatureUnit':
        final unit = temperatureUnits[value];
        if (unit == null) return null;
        return _single('temp_unit_convert', unit);
    }
    final identifier = setting[key];
    if (identifier == null) return null;
    final scale = dpScale[identifier];
    if (scale != null && value is num) {
      return _single(identifier, (value * scale).round());
    }
    return _single(identifier, value);
  }

  /// Minutes past midnight for a `HH:MM` label, or null when it does not parse.
  static int? minutesOfDay(String label) {
    final parts = label.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts.first);
    final minute = int.tryParse(parts.last);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  /// `HH:MM` for minutes past midnight, or null when out of range.
  ///
  /// The DP allows 1440, which is midnight at the far end of the day; it maps
  /// back onto `00:00`.
  static String? clockLabel(int minutes) {
    if (minutes < 0 || minutes > 1440) return null;
    final wrapped = minutes % 1440;
    final hour = (wrapped ~/ 60).toString().padLeft(2, '0');
    final minute = (wrapped % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static Map<int, Object>? _periodDps(
    String startIdentifier,
    String endIdentifier,
    Object value,
  ) {
    if (value is! String) return null;
    final parts = value.split('-');
    if (parts.length != 2) return null;
    final start = minutesOfDay(parts.first);
    final end = minutesOfDay(parts.last);
    if (start == null || end == null) return null;
    final startId = dp[startIdentifier];
    final endId = dp[endIdentifier];
    if (startId == null || endId == null) return null;
    return <int, Object>{startId: start, endId: end};
  }

  static Map<int, Object>? _single(String identifier, Object value) {
    final id = dp[identifier];
    return id == null ? null : <int, Object>{id: value};
  }
}
