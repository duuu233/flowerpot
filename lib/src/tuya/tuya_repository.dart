import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'tuya_config.dart';
import 'tuya_models.dart';

abstract class TuyaRepository {
  factory TuyaRepository.create() =>
      TuyaConfig.enabled ? MethodChannelTuyaRepository() : MockTuyaRepository();

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

  @override
  Future<List<double>> getHistory(
    String deviceId,
    SensorMetric metric,
    ReportRange range,
  ) async {
    final raw = await _invoke<List<Object?>>('getStatistics', <String, Object?>{
      'deviceId': deviceId,
      'dpId': TuyaConfig.dp[_metricCode(metric)],
      'range': range.name,
    });
    return (raw ?? <Object?>[])
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList();
  }

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
    Object? dp(String code) {
      final id = TuyaConfig.dp[code];
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

    final settings = DeviceControlSettings(
      autoBrightness: boolean(dp('autoBrightness'), true),
      soundInteraction: boolean(dp('soundInteraction'), true),
      soundSensitivity: integer(dp('soundSensitivity'), 60),
      touchInteraction: boolean(dp('touchInteraction'), true),
      touchSensitivity: integer(dp('touchSensitivity'), 70),
      vibration: boolean(dp('vibration'), true),
      napEnabled: boolean(dp('napEnabled'), true),
      napPeriod: '${dp('napPeriod') ?? '12:30-13:30'}',
      nightEnabled: boolean(dp('nightEnabled'), true),
      nightPeriod: '${dp('nightPeriod') ?? '23:00-07:00'}',
      weatherService: boolean(dp('weatherService'), true),
      temperatureUnit: '${dp('temperatureUnit') ?? 'celsius'}',
      clockFormat: '${dp('clockFormat') ?? '24h'}',
    );
    return SmartPlanterDevice(
      id: '${raw['deviceId'] ?? raw['devId'] ?? ''}',
      productId: '${raw['productId'] ?? raw['pid'] ?? ''}',
      name: '${raw['name'] ?? '智能花盆'}',
      online: boolean(raw['online'], false),
      signal: integer(raw['signal'], 0),
      battery: integer(dp('battery'), 0),
      charging: boolean(dp('charging'), false),
      boundAt: DateTime.fromMillisecondsSinceEpoch(
        integer(
              raw['activeTime'],
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
            ) *
            1000,
      ),
      plant: PlantCatalog.byId(raw['plantId']?.toString()),
      sensors: SensorSnapshot(
        waterLevel: integer(dp('waterLevel'), 0),
        soilMoisture: integer(dp('soilMoisture'), 0),
        illuminance: integer(dp('illuminance'), 0),
        ppfd: integer(dp('ppfd'), 0),
        airTemperature: decimal(dp('airTemperature'), 0),
        relativeHumidity: integer(dp('relativeHumidity'), 0),
      ),
      settings: settings,
      firmwareVersion: '${raw['firmwareVersion'] ?? '--'}',
      macAddress: '${raw['mac'] ?? '--'}',
    );
  }

  static String _metricCode(SensorMetric metric) => switch (metric) {
    SensorMetric.waterLevel => 'waterLevel',
    SensorMetric.soilMoisture => 'soilMoisture',
    SensorMetric.light => 'illuminance',
    SensorMetric.ppfd || SensorMetric.dli => 'ppfd',
    SensorMetric.temperature => 'airTemperature',
    SensorMetric.humidity => 'relativeHumidity',
    SensorMetric.battery => 'battery',
  };
}

class MockTuyaRepository implements TuyaRepository {
  MockTuyaRepository({this.latency = const Duration(milliseconds: 260)});

  final Duration latency;
  AppUser? _user;
  late final List<SmartPlanterDevice> _devices = <SmartPlanterDevice>[
    _demoDevice(),
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
    final base = _devices.first.sensors.valueFor(metric);
    return List<double>.generate(count, (index) {
      final wave =
          math.sin(index / math.max(2, count / 6) * math.pi) *
          math.max(2, base * .1);
      final drift = math.cos(index * 1.7) * math.max(1, base * .035);
      return math.max(0, base + wave + drift);
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

  static SmartPlanterDevice _demoDevice() => SmartPlanterDevice(
    id: 'planter-demo-01',
    productId: 'pid-smart-planter',
    name: '客厅的绿意',
    online: true,
    signal: 86,
    battery: 78,
    charging: false,
    boundAt: DateTime.now().subtract(const Duration(days: 126)),
    plant: PlantCatalog.items.first,
    sensors: const SensorSnapshot(
      waterLevel: 72,
      soilMoisture: 56,
      illuminance: 836,
      ppfd: 146,
      airTemperature: 24.6,
      relativeHumidity: 61,
    ),
    settings: const DeviceControlSettings(),
    firmwareVersion: '1.0.8',
    macAddress: 'A4:C1:38:7B:2D:10',
  );
}

class TuyaException implements Exception {
  const TuyaException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
