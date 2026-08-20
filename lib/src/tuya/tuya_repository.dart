import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'tuya_config.dart';
import 'tuya_history_codec.dart';
import 'tuya_models.dart';

abstract class TuyaRepository {
  /// [seedMockDevice] pre-binds a demo planter to the mock backend. The static
  /// UI demo turns it off so the flow starts from the "no device yet" screen.
  factory TuyaRepository.create({bool seedMockDevice = true}) =>
      TuyaConfig.enabled
      ? MethodChannelTuyaRepository()
      : MockTuyaRepository(seedDevice: seedMockDevice);

  Future<bool> initialize();
  Future<AppUser?> restoreSession();
  Future<void> sendVerificationCode({
    required String account,
    required String countryCode,
    required int type,
  });
  Future<AppUser> login({
    required String account,
    required String credential,
    required LoginRegion region,
    required bool verificationCode,
  });
  Future<AppUser> register({
    required String account,
    required String password,
    required String code,
    required LoginRegion region,
  });
  Future<void> resetPassword({
    required String account,
    required String newPassword,
    required String code,
    required LoginRegion region,
  });
  Future<void> updateNickname(String nickname);
  Future<void> logout();
  Future<void> deleteAccount();
  Future<List<SmartPlanterDevice>> getDevices();
  Future<SmartPlanterDevice> pair(PairingRequest request);

  /// Fetches and caches a provisioning token ahead of [pair].
  ///
  /// Only AP mode needs this called explicitly, and it has to happen while the
  /// phone is still on a network with internet access: joining the device's
  /// hotspot cuts off the cloud, and [pair] would otherwise try to fetch the
  /// token from there and fail. The token stays in the native layer.
  Future<void> prepareActivatorToken();

  /// Nearby access points, used before provisioning to check that the phone is
  /// on 2.4 GHz and — in AP mode — that the device hotspot is up.
  Future<WifiScan> scanWifi();
  Future<void> publishDps(String deviceId, Map<int, Object> dps);
  Future<void> renameDevice(String deviceId, String name);
  Future<void> removeDevice(String deviceId, {required bool resetFactory});
  Future<List<double>> getHistory(
    String deviceId,
    SensorMetric metric,
    ReportRange range,
  );
  Future<String> createShareLink(String deviceId);
  Future<String?> checkFirmware(String deviceId);
  Future<void> startFirmwareUpgrade(String deviceId);
  Future<void> uploadAnimation(String deviceId, AnimationAsset asset);
}

class MethodChannelTuyaRepository implements TuyaRepository {
  MethodChannelTuyaRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(TuyaConfig.channelName);

  final MethodChannel _channel;

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw TuyaException(error.code, error.message ?? '涂鸦 SDK 调用失败');
    } on MissingPluginException {
      throw const TuyaException('sdk_unavailable', '原生涂鸦 SDK 尚未接入');
    }
  }

  @override
  Future<bool> initialize() async => await _invoke<bool>('initialize') ?? false;

  @override
  Future<AppUser?> restoreSession() async {
    final raw = await _invoke<Map<Object?, Object?>>('currentUser');
    return raw == null ? null : _user(raw);
  }

  @override
  Future<void> sendVerificationCode({
    required String account,
    required String countryCode,
    required int type,
  }) => _invoke<void>('sendVerificationCode', <String, Object?>{
    'account': account,
    'countryCode': countryCode,
    'type': type,
  });

  @override
  Future<AppUser> login({
    required String account,
    required String credential,
    required LoginRegion region,
    required bool verificationCode,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>('login', <String, Object?>{
      'account': account,
      'credential': credential,
      'countryCode': region == LoginRegion.domestic ? '86' : '1',
      'verificationCode': verificationCode,
      'email': region == LoginRegion.overseas,
    });
    if (raw == null) throw const TuyaException('empty_user', '登录未返回用户信息');
    return _user(raw);
  }

  @override
  Future<AppUser> register({
    required String account,
    required String password,
    required String code,
    required LoginRegion region,
  }) async {
    final raw =
        await _invoke<Map<Object?, Object?>>('register', <String, Object?>{
          'account': account,
          'password': password,
          'code': code,
          'countryCode': region == LoginRegion.domestic ? '86' : '1',
          'email': region == LoginRegion.overseas,
        });
    if (raw == null) throw const TuyaException('empty_user', '注册未返回用户信息');
    return _user(raw);
  }

  @override
  Future<void> resetPassword({
    required String account,
    required String newPassword,
    required String code,
    required LoginRegion region,
  }) => _invoke<void>('resetPassword', <String, Object?>{
    'account': account,
    'newPassword': newPassword,
    'code': code,
    'countryCode': region == LoginRegion.domestic ? '86' : '1',
    'email': region == LoginRegion.overseas,
  });

  @override
  Future<void> updateNickname(String nickname) =>
      _invoke<void>('updateNickname', <String, Object?>{'nickname': nickname});

  @override
  Future<void> logout() => _invoke<void>('logout');

  @override
  Future<void> deleteAccount() => _invoke<void>('cancelAccount');

  @override
  Future<List<SmartPlanterDevice>> getDevices() async {
    final raw = await _invoke<List<Object?>>('getDevices') ?? <Object?>[];
    return raw.whereType<Map<Object?, Object?>>().map(_device).toList();
  }

  @override
  Future<SmartPlanterDevice> pair(PairingRequest request) async {
    final raw = await _invoke<Map<Object?, Object?>>(
      'pairWifiDevice',
      <String, Object?>{
        'ssid': request.ssid,
        'password': request.password,
        'mode': request.mode,
        'homeName': TuyaConfig.defaultHomeName,
      },
    );
    if (raw == null) throw const TuyaException('pair_failed', '配网未返回设备信息');
    return _device(raw);
  }

  @override
  Future<void> prepareActivatorToken() =>
      _invoke<void>('prepareActivatorToken');

  @override
  Future<WifiScan> scanWifi() async {
    final raw = await _invoke<Map<Object?, Object?>>('scanWifi');
    if (raw == null) throw const TuyaException('scan_failed', 'Wi-Fi 扫描未返回结果');
    final networks = (raw['networks'] as List<Object?>? ?? <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => WifiNetwork(
            ssid: '${item['ssid'] ?? ''}',
            level: (item['level'] as num?)?.toInt() ?? -100,
            frequency: (item['frequency'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
    return WifiScan(
      networks: networks,
      current: raw['current']?.toString(),
      currentFrequency: (raw['currentFrequency'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) =>
      _invoke<void>('publishDps', <String, Object?>{
        'deviceId': deviceId,
        'dps': dps.map((key, value) => MapEntry('$key', value)),
      });

  @override
  Future<void> renameDevice(String deviceId, String name) => _invoke<void>(
    'renameDevice',
    <String, Object?>{'deviceId': deviceId, 'name': name},
  );

  @override
  Future<void> removeDevice(String deviceId, {required bool resetFactory}) =>
      _invoke<void>(
        resetFactory ? 'resetFactory' : 'removeDevice',
        <String, Object?>{'deviceId': deviceId},
      );

  /// History decoded from the raw DPs in the most recent [getDevices]
  /// snapshot, keyed by device id.
  ///
  /// The product reports its own history packets, so this no longer calls the
  /// cloud statistics service — which needs a paid platform subscription the
  /// account does not have.
  final Map<String, DeviceHistory> _history = <String, DeviceHistory>{};

  @override
  Future<List<double>> getHistory(
    String deviceId,
    SensorMetric metric,
    ReportRange range,
  ) async => _history[deviceId]?.series(metric, range) ?? const <double>[];

  @override
  Future<String> createShareLink(String deviceId) async =>
      await _invoke<String>('createShareLink', <String, Object?>{
        'deviceId': deviceId,
      }) ??
      '';

  @override
  Future<String?> checkFirmware(String deviceId) =>
      _invoke<String>('checkFirmware', <String, Object?>{'deviceId': deviceId});

  @override
  Future<void> startFirmwareUpgrade(String deviceId) => _invoke<void>(
    'startFirmwareUpgrade',
    <String, Object?>{'deviceId': deviceId},
  );

  @override
  Future<void> uploadAnimation(String deviceId, AnimationAsset asset) =>
      _invoke<void>('uploadAnimation', <String, Object?>{
        'deviceId': deviceId,
        'path': asset.path,
        'name': asset.name,
      });

  AppUser _user(Map<Object?, Object?> raw) => AppUser(
    id: '${raw['uid'] ?? raw['id'] ?? ''}',
    nickname: '${raw['nickname'] ?? raw['nickName'] ?? '植物守护者'}',
    account: '${raw['account'] ?? raw['username'] ?? ''}',
    avatarUrl: raw['avatarUrl']?.toString(),
  );

  SmartPlanterDevice _device(Map<Object?, Object?> raw) {
    final dps = (raw['dps'] as Map<Object?, Object?>?) ?? <Object?, Object?>{};

    // DP values arrive keyed by id. Whether that id is a string or a number
    // depends on how the platform channel encoded the map, so try both.
    Object? dp(String identifier) {
      final id = TuyaConfig.dp[identifier];
      return dps['$id'] ?? dps[id];
    }

    int integer(Object? value, int fallback) => switch (value) {
      int value => value,
      num value => value.round(),
      String value => int.tryParse(value) ?? fallback,
      _ => fallback,
    };

    double decimal(Object? value, double fallback) => switch (value) {
      num value => value.toDouble(),
      String value => double.tryParse(value) ?? fallback,
      _ => fallback,
    };

    bool boolean(Object? value, bool fallback) => switch (value) {
      bool value => value,
      String value => value == 'true',
      _ => fallback,
    };

    // Reads a DP the device transmits as an integer multiplied by a power of
    // ten. Sending the raw number straight to the UI is how 24.6 °C turns into
    // 246 °C on the temperature card.
    double scaled(String identifier, double fallback) {
      final value = dp(identifier);
      if (value == null) return fallback;
      final scale = TuyaConfig.dpScale[identifier] ?? 1;
      return decimal(value, fallback * scale) / scale;
    }

    // Joins the two minutes-past-midnight DPs behind a schedule into the
    // `HH:MM-HH:MM` label every settings screen edits.
    String period(
      String startIdentifier,
      String endIdentifier,
      String fallback,
    ) {
      final start = dp(startIdentifier);
      final end = dp(endIdentifier);
      if (start == null || end == null) return fallback;
      final startLabel = TuyaConfig.clockLabel(integer(start, -1));
      final endLabel = TuyaConfig.clockLabel(integer(end, -1));
      if (startLabel == null || endLabel == null) return fallback;
      return '$startLabel-$endLabel';
    }

    // Null when the device has not reported the status DP yet, or reported a
    // value the firmware added after this table was written. Callers fall back
    // to their own thresholds rather than showing a blank.
    T? reported<T>(String identifier, Map<String, T> values) {
      final value = dp(identifier);
      return value == null ? null : values['$value'];
    }

    DeviceHistory decodeHistory() {
      final series = <String, List<double>>{};
      TuyaConfig.history.forEach((metricKey, ranges) {
        final metric = _historyMetric(metricKey);
        final sampleBytes = TuyaConfig.historySampleBytes[metricKey] ?? 1;
        ranges.forEach((rangeName, identifier) {
          final range = ReportRange.values.byName(rangeName);
          final decoded = TuyaHistoryCodec.decode(
            dp(identifier),
            range: range,
            sampleBytes: sampleBytes,
          );
          if (decoded.isNotEmpty) {
            series[DeviceHistory.key(metric, range)] = decoded;
          }
        });
      });
      return series.isEmpty ? DeviceHistory.empty : DeviceHistory(series);
    }

    final batteryStatus = reported(
      'battery_status',
      const <String, BatteryStatus>{
        'shortage': BatteryStatus.shortage,
        'good': BatteryStatus.good,
        'charging': BatteryStatus.charging,
      },
    );
    final status = DeviceStatusReport(
      battery: batteryStatus,
      waterNeeds: reported(
        'water_needs_status',
        const <String, WaterNeedsStatus>{
          'shortage': WaterNeedsStatus.shortage,
          'drinking': WaterNeedsStatus.drinking,
          'watery': WaterNeedsStatus.watery,
        },
      ),
      lighting: reported(
        'lighting_condition',
        const <String, LightingCondition>{
          'shortage': LightingCondition.shortage,
          'good': LightingCondition.good,
          'very_good': LightingCondition.veryGood,
        },
      ),
      temperature: reported(
        'air_temperature_status',
        const <String, ComfortLevel>{
          'cold': ComfortLevel.low,
          'suitable': ComfortLevel.suitable,
          'heat': ComfortLevel.high,
        },
      ),
      humidity: reported('air_humidity_status', const <String, ComfortLevel>{
        'dry': ComfortLevel.low,
        'suitable': ComfortLevel.suitable,
        'damp': ComfortLevel.high,
      }),
    );

    final settings = DeviceControlSettings(
      autoBrightness: boolean(dp('disp_brightness_switch'), true),
      soundInteraction: boolean(dp('voice_interaction_switch'), true),
      soundSensitivity: integer(dp('sound_sensitivity'), 60),
      touchInteraction: boolean(dp('touch_interact_switch'), true),
      touchSensitivity: integer(dp('touch_sense_sensitivity'), 70),
      vibration: boolean(dp('vibration_switch'), true),
      touchKeyVibration: boolean(dp('touch_vib_switch'), true),
      touchPlantVibration: boolean(dp('touch_plant_vib_switch'), true),
      napEnabled: boolean(dp('nap_time_switch'), true),
      napPeriod: period('nap_start_time', 'nap_end_time', '12:30-13:30'),
      nightEnabled: boolean(dp('night_sleep_switch'), true),
      nightPeriod: period(
        'night_sleep_start_time',
        'night_sleep_end_time',
        '23:00-07:00',
      ),
      temperatureUnit:
          _temperatureUnits['${dp('temp_unit_convert')}'] ?? 'celsius',
      clockFormat: '${dp('time_format') ?? '24h'}',
    );

    final deviceId = '${raw['deviceId'] ?? raw['devId'] ?? ''}';
    final history = decodeHistory();
    _history[deviceId] = history;

    final reportedDays = dp('together_days');
    // DP 148 is the firmware the device runs; `getPv` on the device bean is the
    // protocol version, so it is only a fallback.
    final firmware = dp('firmware_version') ?? raw['firmwareVersion'];
    return SmartPlanterDevice(
      id: deviceId,
      productId: '${raw['productId'] ?? raw['pid'] ?? ''}',
      name: '${raw['name'] ?? '智能花盆'}',
      online: boolean(raw['online'], false),
      signal: integer(raw['signal'], 0),
      battery: integer(dp('battery_level'), 0),
      charging: boolean(
        dp('charge_status'),
        batteryStatus == BatteryStatus.charging,
      ),
      boundAt: DateTime.fromMillisecondsSinceEpoch(
        integer(
              raw['activeTime'],
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
            ) *
            1000,
      ),
      plant: PlantCatalog.byId(raw['plantId']?.toString()),
      sensors: SensorSnapshot(
        waterLevel: integer(dp('water_level'), 0),
        soilMoisture: integer(dp('soil_moist'), 0),
        illuminance: integer(dp('light_intensity'), 0),
        ppfd: decimal(dp('light_ppfd_value'), 0),
        par: decimal(dp('light_par_value'), 0),
        airTemperature: scaled('air_temperature', 0),
        relativeHumidity: scaled('air_humidity', 0).round(),
      ),
      settings: settings,
      firmwareVersion: '${firmware ?? '--'}',
      macAddress: '${raw['mac'] ?? '--'}',
      hardwareVersion: '${dp('hardware_version') ?? '--'}',
      plantVariety: '${dp('plant_variety') ?? ''}',
      deviceStatus: '${dp('device_status') ?? ''}',
      reportedDays: reportedDays == null ? null : integer(reportedDays, 0),
      status: status,
      history: history,
    );
  }

  /// `temp_unit_convert` enum value back to the label the settings sheet uses.
  static final Map<String, String> _temperatureUnits = <String, String>{
    for (final entry in TuyaConfig.temperatureUnits.entries)
      entry.value: entry.key,
  };

  static SensorMetric _historyMetric(String key) => switch (key) {
    'waterLevel' => SensorMetric.waterLevel,
    'soilMoisture' => SensorMetric.soilMoisture,
    _ => SensorMetric.light,
  };
}

class MockTuyaRepository implements TuyaRepository {
  MockTuyaRepository({
    this.latency = const Duration(milliseconds: 260),
    this.seedDevice = true,
  });

  final Duration latency;

  /// Whether the account already owns a planter before any pairing runs.
  final bool seedDevice;

  AppUser? _user;
  late final List<SmartPlanterDevice> _devices = <SmartPlanterDevice>[
    if (seedDevice) _demoDevice(),
  ];

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<bool> initialize() async {
    await _wait();
    return true;
  }

  @override
  Future<AppUser?> restoreSession() async {
    await _wait();
    return _user;
  }

  @override
  Future<void> sendVerificationCode({
    required String account,
    required String countryCode,
    required int type,
  }) => _wait();

  @override
  Future<AppUser> login({
    required String account,
    required String credential,
    required LoginRegion region,
    required bool verificationCode,
  }) async {
    await _wait();
    if (account.trim().isEmpty || credential.trim().isEmpty) {
      throw const TuyaException('invalid_input', '请输入完整登录信息');
    }
    return _user = AppUser(
      id: 'mock-user',
      nickname: '植物守护者',
      account: account.trim(),
      // Bundled demo portrait, so the header and profile page are not an empty
      // grey circle during a walkthrough.
      avatarUrl: 'assets/images/demo_user_avatar.png',
    );
  }

  @override
  Future<AppUser> register({
    required String account,
    required String password,
    required String code,
    required LoginRegion region,
  }) => login(
    account: account,
    credential: password,
    region: region,
    verificationCode: false,
  );

  @override
  Future<void> resetPassword({
    required String account,
    required String newPassword,
    required String code,
    required LoginRegion region,
  }) async {
    await _wait();
    if (account.trim().isEmpty ||
        code.trim().isEmpty ||
        newPassword.length < 6) {
      throw const TuyaException('invalid_input', '请填写完整信息，新密码至少 6 位');
    }
  }

  @override
  Future<void> updateNickname(String nickname) async {
    await _wait();
    _user = _user?.copyWith(nickname: nickname);
  }

  @override
  Future<void> logout() async {
    await _wait();
    _user = null;
  }

  @override
  Future<void> deleteAccount() => logout();

  @override
  Future<List<SmartPlanterDevice>> getDevices() async {
    await _wait();
    return List<SmartPlanterDevice>.of(_devices);
  }

  @override
  Future<SmartPlanterDevice> pair(PairingRequest request) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    final device = _demoDevice().copyWith(name: '窗边的小花园');
    if (_devices.every((item) => item.id != device.id)) _devices.add(device);
    return device;
  }

  @override
  Future<void> prepareActivatorToken() => _wait();

  @override
  Future<WifiScan> scanWifi() async {
    await _wait();
    return const WifiScan(
      current: 'TP-LINK_2.4G',
      currentFrequency: 2437,
      networks: <WifiNetwork>[
        WifiNetwork(ssid: 'TP-LINK_2.4G', level: -46, frequency: 2437),
        WifiNetwork(ssid: 'SmartLife-A1B2', level: -58, frequency: 2412),
        WifiNetwork(ssid: 'TP-LINK_5G', level: -52, frequency: 5180),
        WifiNetwork(ssid: 'Xiaomi_2.4G', level: -71, frequency: 2462),
      ],
    );
  }

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) => _wait();

  @override
  Future<void> renameDevice(String deviceId, String name) async {
    await _wait();
    final index = _devices.indexWhere((device) => device.id == deviceId);
    if (index >= 0) _devices[index] = _devices[index].copyWith(name: name);
  }

  @override
  Future<void> removeDevice(
    String deviceId, {
    required bool resetFactory,
  }) async {
    await _wait();
    _devices.removeWhere((device) => device.id == deviceId);
  }

  @override
  Future<List<double>> getHistory(
    String deviceId,
    SensorMetric metric,
    ReportRange range,
  ) async {
    await _wait();
    final count = switch (range) {
      ReportRange.day => 24,
      ReportRange.week => 7,
      ReportRange.month => 30,
    };
    if (metric == SensorMetric.dli) return _dliSeries(count);
    // Each metric gets its own shape. A single rescaled waveform made every
    // status page look like a copy of the previous one.
    final device = _devices.firstWhere(
      (item) => item.id == deviceId,
      orElse: () => _devices.isEmpty ? _demoDevice() : _devices.first,
    );
    final current = device.sensors.valueFor(metric);
    return switch (metric) {
      SensorMetric.waterLevel => _series(
        count,
        // A watering top-up part way through the window, then slow uptake.
        (progress) => progress < .38
            ? 62 + progress * 24
            : 88 - (progress - .38) * 26,
        jitter: 1.4,
        minimum: 30,
        maximum: 100,
      ),
      SensorMetric.soilMoisture => _series(
        count,
        (progress) => 66 + math.sin(progress * math.pi * 1.6) * 7,
        jitter: 1.2,
        minimum: 35,
        maximum: 96,
      ),
      SensorMetric.temperature => _series(
        count,
        // Cool before dawn, peak mid-afternoon.
        (progress) => 23.4 + math.sin((progress - .22) * math.pi * 1.7) * 4.2,
        jitter: .35,
        minimum: 16,
        maximum: 34,
      ),
      SensorMetric.humidity => _series(
        count,
        (progress) => 54 - math.sin((progress - .2) * math.pi * 1.7) * 9,
        jitter: 1,
        minimum: 30,
        maximum: 85,
      ),
      SensorMetric.battery => _series(
        count,
        // The demo planter is charging, so the curve climbs and levels off.
        (progress) => 62 + math.min(progress * 1.35, 1.0) * 32,
        jitter: .6,
        minimum: 20,
        maximum: 100,
      ),
      SensorMetric.light => _series(
        count,
        (progress) => 120 + math.sin(progress * math.pi) * 260,
        jitter: 12,
        minimum: 0,
        maximum: 900,
      ),
      SensorMetric.ppfd => _series(
        count,
        (progress) => 1.8 + math.sin(progress * math.pi) * 5.4,
        jitter: .18,
        minimum: 0,
        maximum: 12,
      ),
      SensorMetric.dli => <double>[current],
    };
  }

  /// Daily light integral, in the 0.5–1.3 range the bar chart can actually
  /// draw: its axis is floored at 1.0, so a peak below that renders as an
  /// empty card.
  static List<double> _dliSeries(int count) => _series(
    count,
    (progress) => .72 + math.sin(progress * math.pi * 1.3) * .34,
    jitter: .05,
    minimum: .18,
    maximum: 1.3,
  );

  /// Builds [count] points from a 0→1 shape, with a small repeatable jitter so
  /// the line looks measured rather than drawn.
  static List<double> _series(
    int count,
    double Function(double progress) shape, {
    required double jitter,
    required double minimum,
    required double maximum,
  }) {
    return List<double>.generate(count, (index) {
      final progress = count == 1 ? 0.0 : index / (count - 1);
      final noise = math.sin(index * 2.399) * jitter;
      return (shape(progress) + noise).clamp(minimum, maximum);
    });
  }

  @override
  Future<String> createShareLink(String deviceId) async {
    await _wait();
    return 'https://app.flowerpot.example/share/$deviceId?code=PLANT88';
  }

  @override
  Future<String?> checkFirmware(String deviceId) async {
    await _wait();
    return '1.1.0';
  }

  @override
  Future<void> startFirmwareUpgrade(String deviceId) async {
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  @override
  Future<void> uploadAnimation(String deviceId, AnimationAsset asset) =>
      _wait();

  /// Readings are picked to land in the "healthy" band of every status page:
  /// soil at 97 read as 偏湿 on the home card while the water page called the
  /// same value 适宜, and it clamped above the 0–100 chart axis.
  static SmartPlanterDevice _demoDevice() => SmartPlanterDevice(
    id: 'vdevo17235508413621',
    productId: 'ysp8k2mqrbvz4nx1',
    name: '客厅的绿意',
    online: true,
    signal: 86,
    battery: 94,
    charging: true,
    boundAt: DateTime.now().subtract(const Duration(days: 126)),
    plant: PlantCatalog.items.first,
    sensors: const SensorSnapshot(
      waterLevel: 78,
      soilMoisture: 65,
      illuminance: 620,
      ppfd: 6.4,
      airTemperature: 24.6,
      relativeHumidity: 56,
    ),
    settings: const DeviceControlSettings(),
    firmwareVersion: '1.0.8',
    macAddress: 'A4:C1:38:7B:2D:10',
    hardwareVersion: '26',
  );
}

class TuyaException implements Exception {
  const TuyaException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
