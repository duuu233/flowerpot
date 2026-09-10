import 'dart:async';

import 'package:flutter/services.dart';

import 'tuya_config.dart';
import 'tuya_history_codec.dart';
import 'tuya_memorial_codec.dart';
import 'tuya_models.dart';

/// 显式国家码优先；缺省时按区域回落到国内 86 / 海外 1。
String _resolveCountryCode(LoginRegion region, String? override) {
  final explicit = override?.trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  return region == LoginRegion.domestic ? '86' : '1';
}

abstract class TuyaRepository {
  factory TuyaRepository.create() => MethodChannelTuyaRepository();

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

  /// 涂鸦自有账号体系登录：用 APP 后端下发的内部编号 [uid] 与配套密码登录，
  /// 涂鸦侧没有该账号时自动注册。
  ///
  /// 国内账号走的是这条路而不是 [login]：后端返回的 `userNo`（形如
  /// `GA7593223`）不是手机号，拿它调手机号登录会被涂鸦回 `USER_PASSWD_WRONG`，
  /// 文案上看起来却像密码错，很容易把排查方向带偏。
  Future<AppUser> loginWithUid({
    required String uid,
    required String password,
    required String countryCode,
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

  /// 由 App 直接连上设备热点，省掉「去系统设置连 Wi-Fi」那一步。
  ///
  /// 给了 [ssid] 就精确连它；只给 [prefix] 时由系统列出匹配的热点让用户挑。
  /// 返回是否连上并把进程流量绑了过去。Android 9 及以下不支持，抛
  /// `hotspot_join_unsupported`，调用方据此回落到手动引导。
  Future<bool> joinDeviceHotspot({String? ssid, String? prefix});

  /// 释放上面那条连接，让手机回到原来的网络。
  ///
  /// 配网失败后必须调：热点连接和进程网络绑定都是原生层的状态，不释放的话
  /// 进程会一直绑在一个没有互联网的网络上，之后所有云端调用都失败。没有连接
  /// 在跑时调用也安全，什么都不做。
  Future<void> leaveDeviceHotspot();

  /// 中止进行中的配网：停掉 activator，释放设备热点连接与进程网络绑定。
  ///
  /// 进行中的 [pair] 会以 `pair_cancelled` 失败返回，而不是等满超时。没有配网
  /// 在跑时调用也安全。用户中途退出配网页、或 Dart 侧等待超时时调用。
  Future<void> cancelPairing();

  /// 当前使用的涂鸦家庭 id。设备列表按家庭查，家庭对不上就会是空的。
  Future<String> currentHomeId();

  /// 固定这次会话使用的家庭 id。
  ///
  /// 家庭是涂鸦账号下的东西，和设备、和 APP 后端都没有关系：只要账号没变，就该
  /// 一直用同一个家庭，而不是每次登录重新从家庭列表里挑。App 把第一次解析到的
  /// 家庭按账号记在本地，之后每次会话开始就用这个方法钉给原生。
  Future<void> useHome(String homeId);

  /// 本账号的家庭名标记（`YS-<userNo>`）。
  ///
  /// 家庭 id 由涂鸦分配、App 造不出来，但**家庭名**是我们说了算的：建家时用这个
  /// 名字，之后从家庭列表里认领时优先认名字对上的那个。这样"哪个家庭属于这个
  /// 账号"不再依赖列表顺序，也不需要后端加字段。
  Future<void> useHomeTag(String tag);

  /// Nearby access points, used before provisioning to check that the phone is
  /// on 2.4 GHz and — in AP mode — that the device hotspot is up.
  /// 读一次附近网络。
  ///
  /// [refresh] = true 时**主动发起一次系统扫描**再等结果——这条路受 Android 的
  /// 配额限制（前台每 2 分钟 4 次）。false 时只读系统的扫描缓存，**不受配额限制、
  /// 也不必等**：系统自己（连接管理、其它应用、设置页）也在扫，缓存会被它们刷新。
  /// 搜索页据此「30 秒一次真扫 + 2 秒一次读缓存」，比只靠真扫快得多。
  Future<WifiScan> scanWifi({bool refresh = true});
  Future<void> publishDps(String deviceId, Map<int, Object> dps);
  Future<void> renameDevice(String deviceId, String name);
  Future<void> removeDevice(String deviceId, {required bool resetFactory});
  Future<List<double>> getHistory(
    String deviceId,
    SensorMetric metric,
    ReportRange range,
  );
  Future<String> createShareLink(String deviceId);
  Future<FirmwareUpdate?> checkFirmware(String deviceId);
  Future<void> startFirmwareUpgrade(String deviceId);
  Future<void> uploadAnimation(String deviceId, AnimationAsset asset);

  /// Changes the devices push on their own: DP reports, online state and
  /// unbinds that happened elsewhere.
  ///
  /// A broadcast stream — several screens may listen at once — that stays
  /// silent rather than failing on a platform whose bridge does not push yet.
  Stream<DeviceUpdate> get deviceUpdates;

  /// 固件升级进度。和 [deviceUpdates] 走同一条事件通道，同样在没有推送能力的
  /// 平台上保持静默而不是抛错。
  Stream<OtaProgress> get otaUpdates;
}

class MethodChannelTuyaRepository implements TuyaRepository {
  MethodChannelTuyaRepository({MethodChannel? channel, EventChannel? events})
    : _channel = channel ?? const MethodChannel(TuyaConfig.channelName),
      _events = events ?? const EventChannel(TuyaConfig.eventChannelName);

  final MethodChannel _channel;
  final EventChannel _events;

  /// Last raw device map per device id, as the native side sent it.
  ///
  /// A DP report carries only the points that changed, so it has to be merged
  /// into something; this is that something. Filled by every [_device] decode,
  /// which covers the device list, pairing and the merges themselves.
  final Map<String, Map<Object?, Object?>> _snapshots =
      <String, Map<Object?, Object?>>{};

  /// 原始事件流，只订阅一次后分给下面两个消费者。
  ///
  /// A platform that does not implement the event channel delivers one
  /// MissingPluginException and nothing else. Live updates stay off there
  /// instead of taking every listener down with them.
  late final Stream<Object?> _rawEvents = _events
      .receiveBroadcastStream()
      .handleError((Object _) {});

  @override
  late final Stream<DeviceUpdate> deviceUpdates = _rawEvents
      .map(_deviceUpdate)
      .where((update) => update != null)
      .cast<DeviceUpdate>();

  @override
  late final Stream<OtaProgress> otaUpdates = _rawEvents
      .map(_otaUpdate)
      .where((update) => update != null)
      .cast<OtaProgress>();

  /// 解析原生的 OTA 事件：`{deviceId, ota: {status, percent?, message?}}`。
  OtaProgress? _otaUpdate(Object? event) {
    if (event is! Map) return null;
    final ota = event['ota'];
    if (ota is! Map) return null;
    final deviceId = '${event['deviceId'] ?? ''}';
    if (deviceId.isEmpty) return null;
    final status = switch ('${ota['status'] ?? ''}') {
      'success' => OtaStatus.success,
      'failed' => OtaStatus.failed,
      'running' => OtaStatus.running,
      _ => null,
    };
    if (status == null) return null;
    final percent = ota['percent'];
    return OtaProgress(
      deviceId: deviceId,
      status: status,
      percent: percent is num ? percent.toInt().clamp(0, 100) : null,
      message: ota['message']?.toString(),
    );
  }

  /// Turns one native event into an update, or null when there is nothing to
  /// report.
  ///
  /// Shape of the event is documented on the Android side's `devListenerProxy`:
  /// always a `deviceId`, plus any of `dps`, `online`, `removed` and `device`.
  DeviceUpdate? _deviceUpdate(Object? event) {
    if (event is! Map) return null;
    final deviceId = '${event['deviceId'] ?? ''}';
    if (deviceId.isEmpty) return null;

    if (event['removed'] == true) {
      _snapshots.remove(deviceId);
      _history.remove(deviceId);
      return DeviceUpdate.removed(deviceId);
    }

    final snapshot = _snapshots[deviceId];
    // A push for a device this session never listed. There is no snapshot to
    // merge into, and inventing one would drop every field the event omits;
    // the next device-list load picks it up in full.
    if (snapshot == null) return null;

    final merged = Map<Object?, Object?>.of(snapshot);
    // A device-info change ships the whole bean, so it lands first and the DP
    // delta is applied on top.
    final device = event['device'];
    if (device is Map) merged.addAll(device);
    final dps = event['dps'];
    if (dps is Map) {
      final known = merged['dps'];
      merged['dps'] = <Object?, Object?>{
        if (known is Map) ...known,
        ...dps,
      };
    }
    final online = event['online'];
    if (online is bool) merged['online'] = online;

    return DeviceUpdate.changed(_device(merged));
  }

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
  Future<AppUser> loginWithUid({
    required String uid,
    required String password,
    required String countryCode,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>(
      'loginWithUid',
      <String, Object?>{
        'uid': uid,
        'password': password,
        'countryCode': _resolveCountryCode(LoginRegion.domestic, countryCode),
      },
    );
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
    final devices = raw
        .whereType<Map<Object?, Object?>>()
        .map(_device)
        .toList();
    // Devices the account no longer owns leave their snapshot and decoded
    // history behind otherwise.
    final owned = devices.map((device) => device.id).toSet();
    _snapshots.removeWhere((id, _) => !owned.contains(id));
    _history.removeWhere((id, _) => !owned.contains(id));
    return devices;
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
  Future<bool> joinDeviceHotspot({String? ssid, String? prefix}) async =>
      await _invoke<bool>('joinDeviceHotspot', <String, Object?>{
        'ssid': ssid ?? '',
        'prefix': prefix ?? '',
      }) ??
      false;

  @override
  Future<void> leaveDeviceHotspot() => _invoke<void>('leaveDeviceHotspot');

  @override
  Future<void> cancelPairing() => _invoke<void>('cancelPairing');

  @override
  Future<String> currentHomeId() async =>
      await _invoke<String>('currentHomeId') ?? '';

  @override
  Future<void> useHome(String homeId) =>
      _invoke<void>('setHomeId', <String, Object?>{'homeId': homeId});

  @override
  Future<void> useHomeTag(String tag) =>
      _invoke<void>('setHomeTag', <String, Object?>{'tag': tag});

  @override
  Future<WifiScan> scanWifi({bool refresh = true}) async {
    final raw = await _invoke<Map<Object?, Object?>>('scanWifi', <String, Object?>{
      'refresh': refresh,
    });
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
      throttled: raw['throttled'] == true,
      ageMs: (raw['ageMs'] as num?)?.toInt(),
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
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async =>
      _firmwareUpdate(
        await _invoke<Object>('checkFirmware', <String, Object?>{
          'deviceId': deviceId,
        }),
      );

  /// 桥接回的是 `{version, currentVersion}`；装着旧原生包的机器只回一个版本号
  /// 字符串，那种情况按「只知道新版本」处理，不至于整块功能失效。
  static FirmwareUpdate? _firmwareUpdate(Object? raw) {
    String clean(Object? value) {
      final text = value?.toString().trim() ?? '';
      return text == 'null' ? '' : text;
    }

    if (raw is String) {
      final version = clean(raw);
      return version.isEmpty ? null : FirmwareUpdate(version: version);
    }
    if (raw is! Map) return null;
    final version = clean(raw['version']);
    if (version.isEmpty) return null;
    final current = clean(raw['currentVersion']);
    return FirmwareUpdate(
      version: version,
      currentVersion: current.isEmpty ? null : current,
    );
  }

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
      // 151 defaults to 0 in the export: an unreported device never sleeps.
      standbyEnabled: boolean(dp('standby_switch'), false),
      standbyDelayMinutes: integer(dp('standby_delay'), 30),
      deviceLanguage: _deviceLanguages['${dp('language')}'] ?? 'zh',
      // 163 未上报时按「开」处理，见 DeviceControlSettings.plantDetection。
      plantDetection: boolean(dp('plant_detect_switch'), true),
    );

    final deviceId = '${raw['deviceId'] ?? raw['devId'] ?? ''}';
    final history = decodeHistory();
    _history[deviceId] = history;
    // Kept so the next DP report has a full device to merge into.
    _snapshots[deviceId] = raw;

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
      plant: PlantProfile.unavailable,
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
      plantConfirm: PlantConfirmState.fromDp(dp('plant_confirm')),
      deviceStatus: '${dp('device_status') ?? ''}',
      reportedDays: reportedDays == null ? null : integer(reportedDays, 0),
      status: status,
      history: history,
      birthday: TuyaMemorialCodec.decodeFixedDate(dp('memorial_birthday')),
      weddingDay: TuyaMemorialCodec.decodeFixedDate(dp('memorial_wedding')),
      lastOperationResult: '${dp('op_result') ?? ''}',
    );
  }

  /// `temp_unit_convert` enum value back to the label the settings sheet uses.
  static final Map<String, String> _temperatureUnits = <String, String>{
    for (final entry in TuyaConfig.temperatureUnits.entries)
      entry.value: entry.key,
  };

  /// `language` (153) enum value back to the app's own `zh`/`en` code.
  static final Map<String, String> _deviceLanguages = <String, String>{
    for (final entry in TuyaConfig.deviceLanguages.entries)
      entry.value: entry.key,
  };

  static SensorMetric _historyMetric(String key) => switch (key) {
    'waterLevel' => SensorMetric.waterLevel,
    'soilMoisture' => SensorMetric.soilMoisture,
    _ => SensorMetric.light,
  };
}

class TuyaException implements Exception {
  const TuyaException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
