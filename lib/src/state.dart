import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/cache/image_cache_cleanup.dart';
import 'features/auth/domain/auth_validator.dart';
import 'tuya/tuya_config.dart';
import 'tuya/tuya_models.dart';
import 'tuya/tuya_repository.dart';

class FlowerpotState extends ChangeNotifier {
  FlowerpotState({required TuyaRepository repository})
    : _repository = repository;

  TuyaRepository _repository;
  bool _initialized = false;
  bool _busy = false;
  bool _sdkReady = false;
  bool _demoMode = false;
  bool _notificationsEnabled = true;
  int _sessionEpoch = 0;
  String _languageCode = 'zh';
  AppUser? _user;
  WifiScan? _wifiScan;
  String? _selectedDeviceId;
  List<SmartPlanterDevice> _devices = <SmartPlanterDevice>[];

  /// Devices whose plant has been picked in this session.
  ///
  /// [SmartPlanterDevice.plant] is non-nullable, so the "no plant yet" screen
  /// cannot be derived from the device itself; a freshly bound planter stays
  /// unplanted until the user confirms a choice in the plant picker.
  final Set<String> _plantedDevices = <String>{};

  /// Plant and control changes the backend cannot persist yet: the mock keeps
  /// its own copies and `publishDps` is a no-op, so a refresh would otherwise
  /// undo the plant the user just picked and every toggle they flipped.
  final Map<String, PlantProfile> _plantOverrides = <String, PlantProfile>{};
  final Map<String, DeviceControlSettings> _settingsOverrides =
      <String, DeviceControlSettings>{};
  /// Seeded so the animation page has something to show. The list filters out
  /// `builtin://` paths, so these carry file-like paths and are visible.
  final List<AnimationAsset> _animations = <AnimationAsset>[
    AnimationAsset(
      id: 'welcome',
      name: '清晨问候.gif',
      path: '/storage/emulated/0/YSplanter/清晨问候.gif',
      createdAt: DateTime(2026, 8, 12, 9, 20),
      synced: true,
    ),
    AnimationAsset(
      id: 'rain',
      name: '下雨啦.gif',
      path: '/storage/emulated/0/YSplanter/下雨啦.gif',
      createdAt: DateTime(2026, 8, 14, 18, 5),
      synced: true,
    ),
    AnimationAsset(
      id: 'sleepy',
      name: '晚安打盹.gif',
      path: '/storage/emulated/0/YSplanter/晚安打盹.gif',
      createdAt: DateTime(2026, 8, 16, 22, 40),
      synced: false,
    ),
  ];

  bool get initialized => _initialized;
  bool get busy => _busy;
  bool get sdkReady => _sdkReady;
  bool get demoMode => _demoMode;
  bool get authenticated => _user != null;
  bool get notificationsEnabled => _notificationsEnabled;

  /// Whether business calls are answered by the in-app mock backend instead of
  /// the native bridge. True without `TUYA_ENABLED`, and also after the demo
  /// shortcut replaced the repository at runtime.
  bool get usingMockBackend => _repository is MockTuyaRepository;
  String get languageCode => _languageCode;
  AppUser? get user => _user;

  /// Last nearby-network scan, populated by [probeWifi].
  WifiScan? get wifiScan => _wifiScan;
  List<SmartPlanterDevice> get devices => List.unmodifiable(_devices);
  List<AnimationAsset> get animations => List.unmodifiable(_animations);

  SmartPlanterDevice? get selectedDevice {
    if (_devices.isEmpty) return null;
    return _devices.firstWhere(
      (device) => device.id == _selectedDeviceId,
      orElse: () => _devices.first,
    );
  }

  bool hasPlant(String? deviceId) =>
      deviceId != null && _plantedDevices.contains(deviceId);

  SmartPlanterDevice? deviceById(String id) {
    for (final device in _devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _languageCode = preferences.getString('languageCode') ?? 'zh';
      _notificationsEnabled =
          preferences.getBool('notificationsEnabled') ?? true;
    } catch (_) {
      // Local preference failures do not block SDK/session initialization.
    }
    try {
      _sdkReady = await _repository.initialize();
    } catch (_) {
      _sdkReady = false;
    }
    try {
      _user = await _repository.restoreSession();
      if (_user != null) {
        _sessionEpoch++;
        await _refreshDevicesForSession(ignoreErrors: true);
      }
    } catch (_) {
      _user = null;
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<ActionResult> sendCode({
    required String account,
    required LoginRegion region,
    required int type,
  }) => _guard(() async {
    final normalizedAccount = _normalizeAccount(account, region);
    await _repository.sendVerificationCode(
      account: normalizedAccount,
      countryCode: region == LoginRegion.domestic ? '86' : '1',
      type: type,
    );
    return const ActionResult(true, '验证码已发送');
  });

  Future<ActionResult> login({
    required String account,
    required String credential,
    required LoginRegion region,
    required bool verificationCode,
  }) => _guard(() async {
    final normalizedAccount = _normalizeAccount(account, region);
    final normalizedCredential = AuthValidator.credential(
      credential,
      verificationCode: verificationCode,
    );
    _user = await _repository.login(
      account: normalizedAccount,
      credential: normalizedCredential,
      region: region,
      verificationCode: verificationCode,
    );
    _sessionEpoch++;
    await _refreshDevicesForSession(ignoreErrors: true);
    return const ActionResult(true, '登录成功');
  });

  Future<ActionResult> register({
    required String account,
    required String password,
    required String code,
    required LoginRegion region,
  }) => _guard(() async {
    final normalizedAccount = _normalizeAccount(account, region);
    final normalizedPassword = AuthValidator.password(password);
    final normalizedCode = AuthValidator.code(code);
    _user = await _repository.register(
      account: normalizedAccount,
      password: normalizedPassword,
      code: normalizedCode,
      region: region,
    );
    _sessionEpoch++;
    await _refreshDevicesForSession(ignoreErrors: true);
    return const ActionResult(true, '账号创建成功');
  });

  Future<ActionResult> resetPassword({
    required String account,
    required String newPassword,
    required String code,
    required LoginRegion region,
  }) => _guard(() async {
    final normalizedAccount = _normalizeAccount(account, region);
    final normalizedCode = AuthValidator.code(code);
    final normalizedPassword = AuthValidator.password(
      newPassword,
      minimumLength: 6,
    );
    await _repository.resetPassword(
      account: normalizedAccount,
      newPassword: normalizedPassword,
      code: normalizedCode,
      region: region,
    );
    return const ActionResult(true, '密码已更新，请使用新密码登录');
  });

  /// [seedDevice] matches the startup seeding so the demo shortcut and a
  /// normal login land on the same screen.
  Future<ActionResult> enterDemo({bool seedDevice = true}) async {
    _demoMode = true;
    _repository = MockTuyaRepository(
      latency: const Duration(milliseconds: 80),
      seedDevice: seedDevice,
    );
    await _repository.initialize();
    return login(
      account: 'demo@flowerpot.local',
      credential: 'demo',
      region: LoginRegion.overseas,
      verificationCode: false,
    );
  }

  Future<void> refreshDevices() async {
    await _refreshDevicesForSession(ignoreErrors: false);
  }

  /// Re-runs SDK initialization so the reason behind [sdkReady] becomes
  /// visible. Startup swallows this failure to keep the app usable.
  Future<ActionResult> probeSdk() => _guard(() async {
    final ready = await _repository.initialize();
    _sdkReady = ready;
    return ready
        ? const ActionResult(true, 'SDK 初始化通过')
        : const ActionResult(false, 'SDK 初始化返回不可用', code: 'sdk_unavailable');
  });

  /// Asks the SDK whether it still holds a login session and aligns the local
  /// session with that answer.
  Future<ActionResult> probeSession() => _guard(() async {
    final user = await _repository.restoreSession();
    if (user == null) {
      // Probing a session is not leaving the demo: the repository swapped in by
      // [enterDemo] stays in place, so the flag has to survive the reset.
      final demo = _demoMode;
      _clearLocalSession();
      _demoMode = demo;
      return const ActionResult(false, 'SDK 未持有登录会话', code: 'no_session');
    }
    _user = user;
    _sessionEpoch++;
    await _refreshDevicesForSession(ignoreErrors: true);
    return ActionResult(true, '会话有效，设备 ${_devices.length} 台');
  });

  /// Nearby access points, for diagnosing provisioning: in AP mode the device
  /// hotspot has to be visible, and EZ mode only works from a 2.4 GHz network.
  /// Diagnostics-only state, read by the SDK console.
  Future<ActionResult> probeWifi() => _guard(() async {
    final scan = await _repository.scanWifi();
    _wifiScan = scan;
    final current = scan.current;
    final band = switch (scan.currentIs24g) {
      true => '2.4G',
      false => '5G，EZ 配网需要切到 2.4G',
      null => '频段未知',
    };
    final hotspots = scan.networks.where((n) => n.looksLikeDeviceHotspot).length;
    return ActionResult(
      true,
      '扫描到 ${scan.networks.length} 个网络'
      '${current == null ? '' : '，当前 $current（$band）'}'
      '${hotspots == 0 ? '' : '，其中 $hotspots 个疑似设备热点'}',
    );
  });

  /// Device refresh that reports home query, auto-create and device list
  /// failures instead of hiding them like the silent session refresh.
  Future<ActionResult> probeDevices() => _guard(() async {
    await _refreshDevicesForSession(ignoreErrors: false);
    return ActionResult(true, '设备列表已刷新，共 ${_devices.length} 台');
  });

  Future<ActionResult> logout() => _guard(() async {
    try {
      await _repository.logout();
    } catch (_) {
      // Local logout must remain available while the SDK/network is offline.
    }
    _clearLocalSession();
    return const ActionResult(true, '已退出登录');
  });

  Future<ActionResult> deleteAccount() => _guard(() async {
    await _repository.deleteAccount();
    _clearLocalSession();
    return const ActionResult(true, '账号已注销');
  });

  Future<ActionResult> pairDevice(PairingRequest request) => _guard(() async {
    final device = await _repository.pair(request);
    _devices = <SmartPlanterDevice>[
      ..._devices.where((item) => item.id != device.id),
      device,
    ];
    _selectedDeviceId = device.id;
    return const ActionResult(true, '设备配网成功');
  });

  void selectDevice(String id) {
    _selectedDeviceId = id;
    notifyListeners();
  }

  Future<ActionResult> renameDevice(String id, String name) => _guard(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const TuyaException('name', '设备名称不能为空');
    await _repository.renameDevice(id, trimmed);
    _replaceDevice(id, (device) => device.copyWith(name: trimmed));
    return const ActionResult(true, '设备名称已更新');
  });

  Future<ActionResult> selectPlant(String id, PlantProfile plant) =>
      _guard(() async {
        _plantedDevices.add(id);
        _plantOverrides[id] = plant;
        _replaceDevice(id, (device) => device.copyWith(plant: plant));
        return ActionResult(true, '已选择${plant.name}');
      });

  Future<ActionResult> updateSetting(
    String id,
    String key,
    Object value,
  ) => _guard(() async {
    final dpId = TuyaConfig.dp[key];
    if (dpId == null) throw TuyaException('unknown_dp', '未配置功能点：$key');
    await _repository.publishDps(id, <int, Object>{dpId: value});
    _replaceDevice(id, (device) {
      final current = device.settings;
      final next = switch (key) {
        'autoBrightness' => current.copyWith(autoBrightness: value as bool),
        'soundInteraction' => current.copyWith(soundInteraction: value as bool),
        'soundSensitivity' => current.copyWith(soundSensitivity: value as int),
        'touchInteraction' => current.copyWith(touchInteraction: value as bool),
        'touchSensitivity' => current.copyWith(touchSensitivity: value as int),
        'vibration' => current.copyWith(vibration: value as bool),
        'napEnabled' => current.copyWith(napEnabled: value as bool),
        'napPeriod' => current.copyWith(napPeriod: value as String),
        'nightEnabled' => current.copyWith(nightEnabled: value as bool),
        'nightPeriod' => current.copyWith(nightPeriod: value as String),
        'weatherService' => current.copyWith(weatherService: value as bool),
        'temperatureUnit' => current.copyWith(temperatureUnit: value as String),
        'clockFormat' => current.copyWith(clockFormat: value as String),
        _ => current,
      };
      _settingsOverrides[id] = next;
      return device.copyWith(settings: next);
    });
    return const ActionResult(true, '设置已同步');
  });

  Future<List<double>> historyFor(
    String id,
    SensorMetric metric,
    ReportRange range,
  ) => _repository.getHistory(id, metric, range);

  Future<ActionResult> addAnimation(
    String deviceId, {
    required String name,
    required String path,
  }) => _guard(() async {
    final asset = AnimationAsset(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      path: path,
      createdAt: DateTime.now(),
    );
    _animations.insert(0, asset);
    await _repository.uploadAnimation(deviceId, asset);
    final index = _animations.indexWhere((item) => item.id == asset.id);
    if (index >= 0) _animations[index] = asset.copyWith(synced: true);
    return const ActionResult(true, '图片已上传并同步');
  });

  Future<ActionResult> syncAnimations(String deviceId) => _guard(() async {
    final files = _animations
        .where((item) => !item.path.startsWith('builtin://'))
        .toList(growable: false);
    if (files.isEmpty) return const ActionResult(true, '暂无需要同步的文件');
    for (final file in files) {
      await _repository.uploadAnimation(deviceId, file);
      final index = _animations.indexWhere((item) => item.id == file.id);
      if (index >= 0) _animations[index] = file.copyWith(synced: true);
    }
    return ActionResult(true, '已同步 ${files.length} 个文件');
  });

  void pinAnimation(String id) {
    final index = _animations.indexWhere((item) => item.id == id);
    if (index <= 0) return;
    final item = _animations.removeAt(index);
    _animations.insert(0, item);
    notifyListeners();
  }

  void deleteAnimation(String id) {
    _animations.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  Future<ActionResult> createShareLink(String id) => _guard(() async {
    final link = await _repository.createShareLink(id);
    return ActionResult(true, link);
  });

  Future<String?> checkFirmware(String id) => _repository.checkFirmware(id);

  Future<ActionResult> upgradeFirmware(String id, String version) => _guard(
    () async {
      await _repository.startFirmwareUpgrade(id);
      _replaceDevice(id, (device) => device.copyWith(firmwareVersion: version));
      return ActionResult(true, '固件已升级至 $version');
    },
  );

  Future<ActionResult> runMaintenance(String id, String action) =>
      _guard(() async {
        final dpId = TuyaConfig.dp[action];
        if (dpId == null) throw TuyaException('unknown_dp', '未配置维护功能点：$action');
        await _repository.publishDps(id, <int, Object>{dpId: true});
        return const ActionResult(true, '指令已发送，请保持设备在线');
      });

  Future<ActionResult> removeDevice(String id, {required bool resetFactory}) =>
      _guard(() async {
        await _repository.removeDevice(id, resetFactory: resetFactory);
        _devices.removeWhere((device) => device.id == id);
        _plantedDevices.remove(id);
        _selectedDeviceId = _devices.firstOrNull?.id;
        return ActionResult(true, resetFactory ? '设备已解绑并清除数据' : '设备已解绑');
      });

  Future<ActionResult> updateProfile({
    required String nickname,
    String? avatarUrl,
  }) => _guard(() async {
    final value = nickname.trim();
    if (value.isEmpty) {
      throw const TuyaException('nickname', '用户名不能为空');
    }
    await _repository.updateNickname(value);
    _user = _user?.copyWith(nickname: value, avatarUrl: avatarUrl);
    return const ActionResult(true, '基本信息已保存');
  });

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('languageCode', code);
  }

  Future<void> setNotifications(bool enabled) async {
    _notificationsEnabled = enabled;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('notificationsEnabled', enabled);
  }

  void _replaceDevice(
    String id,
    SmartPlanterDevice Function(SmartPlanterDevice device) replace,
  ) {
    final index = _devices.indexWhere((device) => device.id == id);
    if (index >= 0) _devices[index] = replace(_devices[index]);
    notifyListeners();
  }

  Future<ActionResult> _guard(Future<ActionResult> Function() action) async {
    if (_busy) return const ActionResult(false, '请等待当前操作完成', code: 'busy');
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } on AuthValidationException catch (error) {
      return ActionResult(false, error.message, code: 'invalid_input');
    } on TuyaException catch (error) {
      return ActionResult(false, error.message, code: error.code);
    } catch (error) {
      return ActionResult(false, '操作失败：$error', code: 'unexpected_error');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _refreshDevicesForSession({required bool ignoreErrors}) async {
    final epoch = _sessionEpoch;
    try {
      final devices = await _repository.getDevices();
      if (epoch != _sessionEpoch) return;
      _devices = devices.map(_withLocalOverrides).toList();
      if (_devices.isEmpty) {
        _selectedDeviceId = null;
      } else if (_devices.every((item) => item.id != _selectedDeviceId)) {
        _selectedDeviceId = _devices.first.id;
      }
      notifyListeners();
    } catch (_) {
      if (!ignoreErrors) rethrow;
    }
  }

  SmartPlanterDevice _withLocalOverrides(SmartPlanterDevice device) {
    final plant = _plantOverrides[device.id];
    final settings = _settingsOverrides[device.id];
    if (plant == null && settings == null) return device;
    return device.copyWith(plant: plant, settings: settings);
  }

  void _clearLocalSession() {
    _sessionEpoch++;
    _user = null;
    _devices = <SmartPlanterDevice>[];
    _plantedDevices.clear();
    _plantOverrides.clear();
    _settingsOverrides.clear();
    _selectedDeviceId = null;
    _demoMode = false;
    ImageCacheCleanup.clearAll();
  }

  String _normalizeAccount(String account, LoginRegion region) {
    final normalized = account.trim();
    if (_repository is MockTuyaRepository && normalized.isNotEmpty) {
      return normalized;
    }
    return AuthValidator.account(normalized, region);
  }
}
