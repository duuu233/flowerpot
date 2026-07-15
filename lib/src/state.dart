import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String _languageCode = 'zh';
  AppUser? _user;
  String? _selectedDeviceId;
  List<SmartPlanterDevice> _devices = <SmartPlanterDevice>[];
  final List<AnimationAsset> _animations = <AnimationAsset>[
    AnimationAsset(
      id: 'welcome',
      name: '清晨问候',
      path: 'builtin://morning',
      createdAt: DateTime(2026),
      synced: true,
    ),
    AnimationAsset(
      id: 'rain',
      name: '下雨啦',
      path: 'builtin://rain',
      createdAt: DateTime(2026, 1, 2),
      synced: true,
    ),
  ];

  bool get initialized => _initialized;
  bool get busy => _busy;
  bool get sdkReady => _sdkReady;
  bool get demoMode => _demoMode;
  bool get authenticated => _user != null;
  bool get notificationsEnabled => _notificationsEnabled;
  String get languageCode => _languageCode;
  AppUser? get user => _user;
  List<SmartPlanterDevice> get devices => List.unmodifiable(_devices);
  List<AnimationAsset> get animations => List.unmodifiable(_animations);

  SmartPlanterDevice? get selectedDevice {
    if (_devices.isEmpty) return null;
    return _devices.firstWhere(
      (device) => device.id == _selectedDeviceId,
      orElse: () => _devices.first,
    );
  }

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
      _sdkReady = await _repository.initialize();
      _user = await _repository.restoreSession();
      if (_user != null) await refreshDevices();
    } catch (_) {
      _sdkReady = false;
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
    if (account.trim().isEmpty) throw const TuyaException('account', '请先填写账号');
    await _repository.sendVerificationCode(
      account: account.trim(),
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
    _user = await _repository.login(
      account: account,
      credential: credential,
      region: region,
      verificationCode: verificationCode,
    );
    await refreshDevices();
    return const ActionResult(true, '登录成功');
  });

  Future<ActionResult> register({
    required String account,
    required String password,
    required String code,
    required LoginRegion region,
  }) => _guard(() async {
    _user = await _repository.register(
      account: account,
      password: password,
      code: code,
      region: region,
    );
    await refreshDevices();
    return const ActionResult(true, '账号创建成功');
  });

  Future<ActionResult> resetPassword({
    required String account,
    required String newPassword,
    required String code,
    required LoginRegion region,
  }) => _guard(() async {
    if (account.trim().isEmpty || code.trim().isEmpty) {
      throw const TuyaException('invalid_input', '请填写账号和验证码');
    }
    if (newPassword.length < 6) {
      throw const TuyaException('weak_password', '新密码至少需要 6 位');
    }
    await _repository.resetPassword(
      account: account.trim(),
      newPassword: newPassword,
      code: code.trim(),
      region: region,
    );
    return const ActionResult(true, '密码已更新，请使用新密码登录');
  });

  Future<ActionResult> enterDemo() async {
    _demoMode = true;
    _repository = MockTuyaRepository(latency: const Duration(milliseconds: 80));
    await _repository.initialize();
    return login(
      account: 'demo@flowerpot.local',
      credential: 'demo',
      region: LoginRegion.overseas,
      verificationCode: false,
    );
  }

  Future<void> refreshDevices() async {
    _devices = await _repository.getDevices();
    if (_devices.isNotEmpty) _selectedDeviceId ??= _devices.first.id;
    notifyListeners();
  }

  Future<ActionResult> logout() => _guard(() async {
    await _repository.logout();
    _user = null;
    _devices = <SmartPlanterDevice>[];
    _selectedDeviceId = null;
    _demoMode = false;
    return const ActionResult(true, '已退出登录');
  });

  Future<ActionResult> deleteAccount() => _guard(() async {
    await _repository.deleteAccount();
    _user = null;
    _devices = <SmartPlanterDevice>[];
    _selectedDeviceId = null;
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
    if (_busy) return const ActionResult(false, '请等待当前操作完成');
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } on TuyaException catch (error) {
      return ActionResult(false, error.message);
    } catch (error) {
      return ActionResult(false, '操作失败：$error');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
