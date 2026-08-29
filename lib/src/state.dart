import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/backend/backend.dart';
import 'core/cache/image_cache_cleanup.dart';
import 'core/network/api_exception.dart';
import 'features/auth/domain/auth_validator.dart';
import 'tuya/tuya_config.dart';
import 'tuya/tuya_models.dart';
import 'tuya/tuya_repository.dart';

class FlowerpotState extends ChangeNotifier {
  FlowerpotState({
    required TuyaRepository repository,
    AppBackendRepository? backendRepository,
  }) : _repository = repository,
       _backend = backendRepository ?? const DisabledAppBackendRepository();

  TuyaRepository _repository;
  final AppBackendRepository _backend;
  bool _initialized = false;
  bool _busy = false;
  bool _sdkReady = false;
  bool _demoMode = false;
  bool _notificationsEnabled = true;
  int _sessionEpoch = 0;
  String _languageCode = 'zh';
  AppUser? _user;
  WifiScan? _wifiScan;

  /// 每台设备最近一次的固件升级进度，界面据此显示进度条。
  final Map<String, OtaProgress> _otaProgress = <String, OtaProgress>{};

  /// 已发起升级但尚未收到 success 的目标版本号，收到后才写回设备。
  final Map<String, String> _pendingOtaVersion = <String, String>{};

  /// [probeWifi] 自己的重入保护，见那里的说明。
  bool _wifiScanning = false;

  /// When [prepareActivatorToken] last succeeded. The token itself never
  /// leaves the native layer; this only tells the Wi-Fi page whether the AP
  /// step is still covered.
  DateTime? _activatorTokenAt;
  String? _selectedDeviceId;
  List<SmartPlanterDevice> _devices = <SmartPlanterDevice>[];

  /// Server-side device rows keyed by the Tuya device id. Plant and image APIs
  /// require `userProductId`, so this mapping is resolved once and reused.
  final Map<String, BackendUserProduct> _backendDevices =
      <String, BackendUserProduct>{};
  final Map<String, List<PlantProfile>> _backendPlants =
      <String, List<PlantProfile>>{};
  final Map<String, List<AnimationAsset>> _backendAnimations =
      <String, List<AnimationAsset>>{};
  final Map<String, PlantProfile> _knownPlantsByIdentifier =
      <String, PlantProfile>{};

  /// Live device reports. See [_applyDeviceUpdate].
  StreamSubscription<DeviceUpdate>? _deviceUpdates;
  StreamSubscription<OtaProgress>? _otaUpdates;

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

  /// Built-in device animations are not user-uploaded files, so the page
  /// filters their `builtin://` paths and only counts backend/local uploads.
  final List<AnimationAsset> _animations = <AnimationAsset>[
    AnimationAsset(
      id: 'welcome',
      name: '清晨问候.gif',
      path: 'builtin://welcome',
      createdAt: DateTime(2026, 8, 12, 9, 20),
      synced: true,
    ),
    AnimationAsset(
      id: 'rain',
      name: '下雨啦.gif',
      path: 'builtin://rain',
      createdAt: DateTime(2026, 8, 14, 18, 5),
      synced: true,
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
  bool get usingAppBackend => _backend.enabled;
  String get languageCode => _languageCode;
  AppUser? get user => _user;

  /// Last nearby-network scan, populated by [probeWifi]. Read by the pairing
  /// flow as well as the SDK console.
  WifiScan? get wifiScan => _wifiScan;

  /// Tuya signs a provisioning token for 10 minutes and the bridge caches it
  /// for 8. The UI expires it earlier so switching to the device hotspot does
  /// not eat the whole margin.
  static const Duration activatorTokenLifetime = Duration(minutes: 7);

  /// Whether a provisioning token fetched by [prepareActivatorToken] should
  /// still be valid. AP pairing needs one before the phone leaves the router.
  bool get activatorTokenReady {
    final fetchedAt = _activatorTokenAt;
    return fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < activatorTokenLifetime;
  }

  List<SmartPlanterDevice> get devices => List.unmodifiable(_devices);
  List<AnimationAsset> get animations => animationsFor(_selectedDeviceId);

  List<AnimationAsset> animationsFor(String? deviceId) {
    final items = _backend.enabled
        ? deviceId == null
              ? const <AnimationAsset>[]
              : _backendAnimations[deviceId] ?? const <AnimationAsset>[]
        : _animations;
    return List.unmodifiable(items);
  }

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
      await _backend.initialize(languageCode: _languageCode);
    } catch (_) {
      // A REST outage must not prevent the Tuya SDK from restoring its session.
    }
    try {
      _sdkReady = await _repository.initialize();
    } catch (_) {
      _sdkReady = false;
    }
    _listenForDeviceUpdates();
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
    if (region == LoginRegion.domestic && _backend.enabled) {
      // The APP backend uses 0 for login/register and 1 for password reset;
      // the UI's legacy Tuya values (1/2/3) are normalized here.
      await _backend.sendSms(
        mobile: normalizedAccount,
        sendType: type == 3 ? 1 : 0,
      );
      return const ActionResult(true, '验证码已发送');
    }
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
    if (region == LoginRegion.domestic && _backend.enabled) {
      final backendAccount = verificationCode
          ? await _backend.loginWithCode(
              mobile: normalizedAccount,
              code: normalizedCredential,
            )
          : await _backend.loginWithPassword(
              mobile: normalizedAccount,
              password: normalizedCredential,
            );
      _user = await _loginTuyaAccount(backendAccount);
    } else {
      _user = await _repository.login(
        account: normalizedAccount,
        credential: normalizedCredential,
        region: region,
        verificationCode: verificationCode,
      );
    }
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
    if (region == LoginRegion.domestic && _backend.enabled) {
      final backendAccount = await _backend.registerMobile(
        mobile: normalizedAccount,
        code: normalizedCode,
        password: normalizedPassword,
      );
      _user = await _loginTuyaAccount(backendAccount);
    } else {
      _user = await _repository.register(
        account: normalizedAccount,
        password: normalizedPassword,
        code: normalizedCode,
        region: region,
      );
    }
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
    _backend.clearSession();
    _repository = MockTuyaRepository(
      latency: const Duration(milliseconds: 80),
      seedDevice: seedDevice,
    );
    await _repository.initialize();
    // The old subscription belongs to the repository being replaced.
    _listenForDeviceUpdates();
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
        : const ActionResult(
            false,
            'APP-sdk_unavailable SDK 初始化返回不可用',
            code: 'sdk_unavailable',
          );
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
      return const ActionResult(
        false,
        'APP-no_session SDK 未持有登录会话',
        code: 'no_session',
      );
    }
    _user = user;
    _sessionEpoch++;
    await _refreshDevicesForSession(ignoreErrors: true);
    return ActionResult(true, '会话有效，设备 ${_devices.length} 台');
  });

  /// Nearby access points: AP 配网要能看见设备热点，而设备本身只连 2.4 GHz。
  ///
  /// Used by the pairing flow — the search step looks for planter hotspots and
  /// the Wi-Fi step lists real 2.4 GHz routers — and by the SDK console. Does
  /// not touch the Tuya SDK, so it answers even before initialization.
  ///
  /// 不参与 [_guard] 的全局单操作锁：这是个只读调用，和别的操作没有真实冲突，
  /// 而 Android 上一次扫描要好几秒。占着锁的话，这期间用户发起的任何操作——
  /// 换页后再扫一次、配网页取令牌——都会被挡成「请等待当前操作完成」，在选择
  /// 设备页上还会被当成扫描失败的原因显示出来。这里只防它自己重入。
  Future<ActionResult> probeWifi() async {
    if (_wifiScanning) {
      return const ActionResult(
        false,
        'APP-wifi_scanning 正在扫描附近网络，请稍候',
        code: 'wifi_scanning',
      );
    }
    _wifiScanning = true;
    try {
      return await _run(_probeWifi);
    } finally {
      _wifiScanning = false;
      notifyListeners();
    }
  }

  Future<ActionResult> _probeWifi() async {
    final scan = await _repository.scanWifi();
    _wifiScan = scan;
    final current = scan.current;
    final band = switch (scan.currentIs24g) {
      true => '2.4G',
      false => '5G，设备只能连 2.4G',
      null => '频段未知',
    };
    final hotspots = scan.networks
        .where((n) => n.looksLikeDeviceHotspot)
        .length;
    return ActionResult(
      true,
      '扫描到 ${scan.networks.length} 个网络'
      '${current == null ? '' : '，当前 $current（$band）'}'
      '${hotspots == 0 ? '' : '，其中 $hotspots 个疑似设备热点'}',
    );
  }

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
    _backend.clearSession();
    _clearLocalSession();
    return const ActionResult(true, '已退出登录');
  });

  Future<ActionResult> deleteAccount() => _guard(() async {
    await _repository.deleteAccount();
    _backend.clearSession();
    _clearLocalSession();
    return const ActionResult(true, '账号已注销');
  });

  /// Pre-fetches the provisioning token, which AP mode has to do before the
  /// phone leaves the router for the device hotspot. See
  /// [TuyaRepository.prepareActivatorToken].
  Future<ActionResult> prepareActivatorToken() => _guard(() async {
    await _repository.prepareActivatorToken();
    _activatorTokenAt = DateTime.now();
    return const ActionResult(true, '已获取配网令牌，8 分钟内有效，现在可以切到设备热点');
  });

  Future<ActionResult> pairDevice(PairingRequest request) => _guard(() async {
    final device = await _repository.pair(request);
    // Tuya tokens are single-use and the bridge drops its cached copy on
    // success, so the next AP attempt has to fetch a new one.
    _activatorTokenAt = null;
    _devices = <SmartPlanterDevice>[
      ..._devices.where((item) => item.id != device.id),
      device,
    ];
    _selectedDeviceId = device.id;
    if (_backend.enabled && _backend.hasSession) {
      try {
        await _ensureBackendDevice(device.id);
      } on ApiException catch (error) {
        return ActionResult(
          true,
          '设备已配网；后台关联待重试：'
          '${_tagged(_apiSource(error.code), error.code, error.message)}',
          code: 'backend_device_pending',
        );
      }
    }
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

  /// Loads the plants configured for this device's backend product. The local
  /// catalog remains the offline/demo fallback only.
  Future<List<PlantProfile>> loadPlantCatalog(
    String deviceId, {
    String keyword = '',
  }) async {
    if (!_backend.enabled) {
      final normalized = keyword.trim().toLowerCase();
      if (normalized.isEmpty) return PlantCatalog.items;
      return PlantCatalog.items
          .where(
            (plant) =>
                plant.name.contains(normalized) ||
                plant.latinName.toLowerCase().contains(normalized),
          )
          .toList(growable: false);
    }
    if (!_backend.hasSession) {
      throw const ApiException(
        'BACKEND_SESSION_REQUIRED',
        'APP 后端登录状态已失效，请重新登录',
      );
    }
    final backendDevice = await _ensureBackendDevice(deviceId);
    final productId = backendDevice.productId;
    if (productId == null || productId <= 0) {
      throw const ApiException('PRODUCT_ID_MISSING', '后台设备未关联产品，无法加载植物列表');
    }
    final plants = await _backend.getProductPlants(
      productId: productId,
      keyword: keyword,
    );
    _rememberPlants(plants);
    return plants;
  }

  Future<PlantProfile> loadPlantDetail(PlantProfile plant) async {
    final productPlantId = plant.productPlantId;
    if (!_backend.enabled || !_backend.hasSession || productPlantId == null) {
      return plant;
    }
    final detail = await _backend.getPlantDetail(productPlantId);
    _rememberPlants(<PlantProfile>[detail]);
    return detail;
  }

  /// Persists the selection first, then writes its backend English identifier
  /// to reportable/writable DP 116. A DP failure deliberately keeps the server
  /// binding so the same selection can be retried without losing user data.
  Future<ActionResult> selectPlant(String id, PlantProfile plant) =>
      _guard(() async {
        final identifier = plant.tuyaIdentifier.trim();
        if (identifier.isEmpty) {
          throw const ApiException(
            'PLANT_IDENTIFIER_MISSING',
            '该植物尚未配置英文标识符，请先在后端植物管理中补充',
          );
        }

        var boundPlant = plant;
        if (_backend.enabled) {
          final backendDevice = await _ensureBackendDevice(id);
          final productPlantId = plant.productPlantId;
          if (productPlantId == null || productPlantId <= 0) {
            throw const ApiException(
              'PRODUCT_PLANT_ID_MISSING',
              '该植物缺少后台编号，无法绑定',
            );
          }

          var current =
              _backendPlants[id] ??
              await _backend.getUserPlants(backendDevice.userProductId);
          final same = current.where(
            (item) =>
                item.productPlantId == productPlantId ||
                item.tuyaIdentifier == identifier,
          );
          if (same.isEmpty) {
            final activeIdentifier =
                deviceById(id)?.plantVariety.trim().toLowerCase() ?? '';
            final previous =
                current
                    .where(
                      (item) =>
                          activeIdentifier.isNotEmpty &&
                          item.tuyaIdentifier.trim().toLowerCase() ==
                              activeIdentifier,
                    )
                    .firstOrNull ??
                current.firstOrNull;
            if (previous?.userProductPlantId case final previousId?) {
              await _backend.deleteUserPlant(previousId);
            }
            try {
              await _backend.addUserPlant(
                userProductId: backendDevice.userProductId,
                productPlantId: productPlantId,
              );
            } catch (_) {
              // Restore the previous binding where possible. The original
              // error is still reported to the user.
              final rollbackId = previous?.productPlantId;
              if (rollbackId != null) {
                try {
                  await _backend.addUserPlant(
                    userProductId: backendDevice.userProductId,
                    productPlantId: rollbackId,
                  );
                } catch (_) {}
              }
              rethrow;
            }
            current = await _backend.getUserPlants(backendDevice.userProductId);
          }
          _backendPlants[id] = current;
          _rememberPlants(current);
          boundPlant = current.firstWhere(
            (item) =>
                item.productPlantId == productPlantId ||
                item.tuyaIdentifier == identifier,
            orElse: () => plant,
          );
        }

        _setPlantSelection(id, boundPlant);
        try {
          await _publishPlantVariety(id, identifier);
        } on TuyaException catch (error) {
          return ActionResult(
            false,
            '植物已绑定，但同步到设备失败：${error.message}，请重试',
            code: error.code,
          );
        }
        return ActionResult(true, '已选择${boundPlant.name}并同步到设备');
      });

  Future<ActionResult> updateSetting(
    String id,
    String key,
    Object value,
  ) => _guard(() async {
    final dps = TuyaConfig.settingDps(key, value);
    if (dps == null) {
      throw TuyaException('unsupported_dp', '当前产品未提供该功能点：$key');
    }
    await _repository.publishDps(id, dps);
    _replaceDevice(id, (device) {
      final current = device.settings;
      final next = switch (key) {
        'autoBrightness' => current.copyWith(autoBrightness: value as bool),
        'soundInteraction' => current.copyWith(soundInteraction: value as bool),
        'soundSensitivity' => current.copyWith(soundSensitivity: value as int),
        'touchInteraction' => current.copyWith(touchInteraction: value as bool),
        'touchSensitivity' => current.copyWith(touchSensitivity: value as int),
        'vibration' => current.copyWith(vibration: value as bool),
        'touchKeyVibration' => current.copyWith(
          touchKeyVibration: value as bool,
        ),
        'touchPlantVibration' => current.copyWith(
          touchPlantVibration: value as bool,
        ),
        'napEnabled' => current.copyWith(napEnabled: value as bool),
        'napPeriod' => current.copyWith(napPeriod: value as String),
        'nightEnabled' => current.copyWith(nightEnabled: value as bool),
        'nightPeriod' => current.copyWith(nightPeriod: value as String),
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
    if (_backend.enabled) {
      final backendDevice = await _ensureBackendDevice(deviceId);
      await _backend.uploadImage(
        userProductId: backendDevice.userProductId,
        filePath: path,
      );
      await _refreshBackendImages(deviceId, backendDevice);
      return const ActionResult(true, '图片已上传');
    }
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
    if (_backend.enabled) {
      final backendDevice = await _ensureBackendDevice(deviceId);
      await _refreshBackendImages(deviceId, backendDevice);
      return ActionResult(true, '已同步 ${animationsFor(deviceId).length} 个云端文件');
    }
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

  Future<ActionResult> deleteAnimation(String deviceId, String id) =>
      _guard(() async {
        if (_backend.enabled) {
          final imageId = int.tryParse(id);
          if (imageId == null) {
            throw const ApiException('IMAGE_ID_INVALID', '图片编号无效，无法删除');
          }
          await _backend.deleteImages(<int>[imageId]);
          _backendAnimations[deviceId]?.removeWhere((item) => item.id == id);
        } else {
          _animations.removeWhere((item) => item.id == id);
        }
        return const ActionResult(true, '图片已删除');
      });

  Future<void> refreshAnimations(String deviceId) async {
    if (!_backend.enabled || !_backend.hasSession) return;
    final backendDevice = await _ensureBackendDevice(deviceId);
    await _refreshBackendImages(deviceId, backendDevice);
  }

  Future<ActionResult> createShareLink(String id) => _guard(() async {
    final link = await _repository.createShareLink(id);
    return ActionResult(true, link);
  });

  Future<String?> checkFirmware(String id) => _repository.checkFirmware(id);

  /// 发起固件升级。
  ///
  /// 只负责"发起"：涂鸦的 `startOta` 返回时设备才刚开始下载，之后的进度和最终
  /// 结果都从 [otaUpdates] 回来。版本号因此不在这里改写，而是等 success 事件
  /// ——否则设备还在烧录，界面就已经显示新版本了。
  Future<ActionResult> upgradeFirmware(String id, String version) => _guard(
    () async {
      await _repository.startFirmwareUpgrade(id);
      _pendingOtaVersion[id] = version;
      _otaProgress[id] = OtaProgress(
        deviceId: id,
        status: OtaStatus.running,
        percent: 0,
      );
      return const ActionResult(true, '升级已开始，请保持设备通电并留在网络中');
    },
  );

  /// 某台设备最近一次的升级进度，没有发起过升级时为 null。
  OtaProgress? otaProgressFor(String deviceId) => _otaProgress[deviceId];

  /// Advances `water_level_calib` (DP 140) by one step.
  ///
  /// The DP is an enum of stages rather than a single "calibrate" command, so
  /// the dialog reports which step the user just confirmed and the device
  /// samples at that point.
  Future<ActionResult> calibrateWaterLevel(String id, int step) =>
      _guard(() async {
        if (step < 0 || step >= TuyaConfig.calibrationSteps.length) {
          throw TuyaException('unknown_dp', '未知的校准步骤：$step');
        }
        await _publishCalibration(id, TuyaConfig.calibrationSteps[step]);
        return const ActionResult(true, '指令已发送，请保持设备在线');
      });

  /// Leaves calibration mode when the user backs out part way through, so the
  /// device does not sit waiting for the rest of the sequence.
  Future<ActionResult> cancelWaterLevelCalibration(String id) =>
      _guard(() async {
        await _publishCalibration(id, TuyaConfig.calibrationCancel);
        return const ActionResult(true, '已取消校准');
      });

  /// Tells the planter itself to reset (DP 141) before the SDK unbinds it.
  ///
  /// The SDK's `resetFactory` clears the cloud binding; the DP is what the
  /// firmware acts on, so it goes first — after the unbind the app has no route
  /// to the device. An offline or rejecting device does not block the unbind
  /// the user asked for.
  ///
  /// Still to confirm with firmware: what the device does on receiving 141, and
  /// whether it drops the binding on its own as well.
  Future<void> _publishFactoryReset(String id) async {
    final dpId = TuyaConfig.dp['factory_reset'];
    if (dpId == null) return;
    try {
      await _repository.publishDps(id, <int, Object>{dpId: true});
    } on TuyaException {
      // Unreachable device: unbinding locally is still what was asked for.
    }
  }

  Future<void> _publishCalibration(String id, String step) async {
    final dpId = TuyaConfig.dp['water_level_calib'];
    if (dpId == null) {
      throw const TuyaException('unsupported_dp', '当前产品未提供水位校准功能点');
    }
    await _repository.publishDps(id, <int, Object>{dpId: step});
  }

  Future<void> _publishPlantVariety(String id, String identifier) async {
    final dpId = TuyaConfig.dp['plant_variety'];
    if (dpId == null) {
      throw const TuyaException('unsupported_dp', '当前产品未提供植物品种功能点');
    }
    await _repository.publishDps(id, <int, Object>{dpId: identifier});
  }

  Future<ActionResult> removeDevice(String id, {required bool resetFactory}) =>
      _guard(() async {
        if (resetFactory) await _publishFactoryReset(id);
        await _repository.removeDevice(id, resetFactory: resetFactory);
        final backendDevice = _backendDevices[id];
        ApiException? backendCleanupError;
        if (_backend.enabled && backendDevice != null) {
          try {
            await _backend.deleteUserProduct(backendDevice.userProductId);
          } on ApiException catch (error) {
            // Tuya has already unbound the device. Finish the local removal and
            // surface the stale backend row as a retryable partial result.
            backendCleanupError = error;
          }
        }
        _backendDevices.remove(id);
        _devices.removeWhere((device) => device.id == id);
        _plantedDevices.remove(id);
        _backendPlants.remove(id);
        _backendAnimations.remove(id);
        _plantOverrides.remove(id);
        _settingsOverrides.remove(id);
        _selectedDeviceId = _devices.firstOrNull?.id;
        if (backendCleanupError != null) {
          return ActionResult(
            true,
            '设备已解绑；后台记录清理待重试：${backendCleanupError.message}',
            code: 'backend_device_delete_pending',
          );
        }
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
    _backend.setLanguage(code);
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

  void _listenForDeviceUpdates() {
    _deviceUpdates?.cancel();
    _deviceUpdates = _repository.deviceUpdates.listen(_applyDeviceUpdate);
    _otaUpdates?.cancel();
    _otaUpdates = _repository.otaUpdates.listen(_applyOtaProgress);
  }

  /// 固件升级的实时进度。
  ///
  /// 升级要几分钟，期间设备一直在下载和烧录，所以版本号只在收到 success 时才
  /// 更新——`startOta` 返回只代表升级发起成功。失败和进度都留在这里给界面读。
  void _applyOtaProgress(OtaProgress progress) {
    _otaProgress[progress.deviceId] = progress;
    if (progress.status == OtaStatus.success) {
      final target = _pendingOtaVersion.remove(progress.deviceId);
      if (target != null) {
        _replaceDevice(
          progress.deviceId,
          (device) => device.copyWith(firmwareVersion: target),
        );
      }
    } else if (progress.status == OtaStatus.failed) {
      _pendingOtaVersion.remove(progress.deviceId);
    }
    notifyListeners();
  }

  /// Applies a change the device pushed on its own.
  ///
  /// The device is authoritative here: the pushed snapshot already carries
  /// every DP the app knew plus the ones that just changed, so the local
  /// settings copy is refreshed from it rather than replayed over it — that
  /// copy only exists because the mock backend cannot persist a write, and a
  /// stale one would mask a switch pressed on the planter itself. DP 116 is
  /// reportable, so a recognized identifier also replaces the local plant.
  void _applyDeviceUpdate(DeviceUpdate update) {
    final removedId = update.removedId;
    if (removedId != null) {
      if (_devices.every((device) => device.id != removedId)) return;
      _devices = _devices.where((device) => device.id != removedId).toList();
      _plantedDevices.remove(removedId);
      _backendDevices.remove(removedId);
      _backendPlants.remove(removedId);
      _backendAnimations.remove(removedId);
      _plantOverrides.remove(removedId);
      _settingsOverrides.remove(removedId);
      if (_selectedDeviceId == removedId) {
        _selectedDeviceId = _devices.firstOrNull?.id;
      }
      notifyListeners();
      return;
    }
    final device = update.device;
    if (device == null) return;
    final index = _devices.indexWhere((item) => item.id == device.id);
    // A report for a device the session does not hold: the next list refresh
    // is what introduces it.
    if (index < 0) return;
    _settingsOverrides[device.id] = device.settings;
    final reportedPlant = _plantForIdentifier(device.plantVariety);
    if (reportedPlant != null) {
      _plantOverrides[device.id] = reportedPlant;
      _plantedDevices.add(device.id);
    }
    _devices[index] = device.copyWith(
      plant: reportedPlant ?? _plantOverrides[device.id],
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _deviceUpdates?.cancel();
    _otaUpdates?.cancel();
    _backend.close();
    super.dispose();
  }

  void _replaceDevice(
    String id,
    SmartPlanterDevice Function(SmartPlanterDevice device) replace,
  ) {
    final index = _devices.indexWhere((device) => device.id == id);
    if (index >= 0) _devices[index] = replace(_devices[index]);
    notifyListeners();
  }

  /// 给失败文案打上来源标签，toast 上一眼看出是谁拒绝了这次请求：
  ///
  /// - `接口-<code>`：APP 后端 REST 返回的失败（`retCode` 或 HTTP 状态码）；
  /// - `涂鸦-<code>`：涂鸦 SDK 原生层返回的失败，与 APP 后端无关；
  /// - `APP-<code>`：APP 自己产生的失败（本地校验、网络层、未预期异常）。
  ///
  /// 涂鸦单列而不并进「接口」：两者是不同的服务，混成一类会把涂鸦拒绝的登录
  /// 指向 APP 后端，排查方向正好反了。
  static String _tagged(String source, Object code, String message) =>
      '$source-$code $message';

  /// 后端的 `retCode` 与 HTTP 状态码都是数字；APP 网络层自己抛的是
  /// `NETWORK_TIMEOUT` 这类大写字符串常量，据此区分 [ApiException] 的来源。
  static String _apiSource(Object code) => code is int ? '接口' : 'APP';

  Future<ActionResult> _guard(Future<ActionResult> Function() action) async {
    if (_busy) {
      return const ActionResult(false, 'APP-busy 请等待当前操作完成', code: 'busy');
    }
    _busy = true;
    notifyListeners();
    try {
      return await _run(action);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 异常收口，不占用 [_busy]。给那些和其它操作没有真实冲突、又可能跑很久的
  /// 只读调用用，[_guard] 自己也走这里。
  Future<ActionResult> _run(Future<ActionResult> Function() action) async {
    try {
      return await action();
    } on AuthValidationException catch (error) {
      return ActionResult(
        false,
        _tagged('APP', 'invalid_input', error.message),
        code: 'invalid_input',
      );
    } on TuyaException catch (error) {
      return ActionResult(
        false,
        _tagged('涂鸦', error.code, error.message),
        code: error.code,
      );
    } on ApiException catch (error) {
      if (error.isAuthError) _clearLocalSession();
      return ActionResult(
        false,
        _tagged(_apiSource(error.code), error.code, error.message),
        code: error.code.toString(),
      );
    } catch (error) {
      return ActionResult(
        false,
        _tagged('APP', 'unexpected_error', '操作失败：$error'),
        code: 'unexpected_error',
      );
    }
  }

  Future<void> _refreshDevicesForSession({required bool ignoreErrors}) async {
    final epoch = _sessionEpoch;
    try {
      final devices = await _repository.getDevices();
      if (epoch != _sessionEpoch) return;
      _devices = devices.map(_withLocalOverrides).toList();
      if (_backend.enabled && _backend.hasSession) {
        try {
          await _syncBackendDevices(epoch);
        } catch (_) {
          if (!ignoreErrors) rethrow;
        }
      }
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
    final plant =
        _plantForIdentifier(device.plantVariety) ?? _plantOverrides[device.id];
    final settings = _settingsOverrides[device.id];
    if (plant != null) {
      _plantOverrides[device.id] = plant;
      _plantedDevices.add(device.id);
    }
    if (plant == null && settings == null) return device;
    return device.copyWith(plant: plant, settings: settings);
  }

  Future<AppUser> _loginTuyaAccount(BackendAuthAccount backendAccount) async {
    try {
      await _repository.loginWithUid(
        uid: backendAccount.tuyaAccount,
        password: backendAccount.tuyaPassword,
        countryCode: backendAccount.countryCode,
      );
    } catch (_) {
      // Do not leave a valid APP token paired with a failed Tuya session.
      _backend.clearSession();
      rethrow;
    }
    return AppUser(
      id: backendAccount.tuyaAccount,
      nickname: backendAccount.nickname,
      account: backendAccount.account,
      avatarUrl: backendAccount.avatarUrl,
    );
  }

  Future<void> _syncBackendDevices(int epoch) async {
    final rows = await _backend.getUserProducts();
    if (epoch != _sessionEpoch) return;
    final activeIds = _devices.map((device) => device.id).toSet();
    _backendDevices.removeWhere((id, _) => !activeIds.contains(id));
    _backendPlants.removeWhere((id, _) => !activeIds.contains(id));
    _backendAnimations.removeWhere((id, _) => !activeIds.contains(id));

    for (final device in _devices) {
      final summary = rows
          .where((row) => row.deviceId == device.id)
          .firstOrNull;
      if (summary == null) continue;
      final detail = summary.productId == null
          ? await _backend.getUserProductDetail(summary.userProductId)
          : summary;
      if (epoch != _sessionEpoch) return;
      _backendDevices[device.id] = detail;
      final plants = await _backend.getUserPlants(detail.userProductId);
      if (epoch != _sessionEpoch) return;
      _backendPlants[device.id] = plants;
      _rememberPlants(plants);
      final reportedIdentifier = device.plantVariety.trim().toLowerCase();
      final activePlant =
          plants
              .where(
                (plant) =>
                    reportedIdentifier.isNotEmpty &&
                    plant.tuyaIdentifier.trim().toLowerCase() ==
                        reportedIdentifier,
              )
              .firstOrNull ??
          plants.firstOrNull;
      if (activePlant != null) {
        _setPlantSelection(device.id, activePlant, notify: false);
      }
    }

    _devices = _devices.map(_withLocalOverrides).toList(growable: false);
  }

  Future<BackendUserProduct> _ensureBackendDevice(String deviceId) async {
    if (!_backend.enabled || !_backend.hasSession) {
      throw const ApiException(
        'BACKEND_SESSION_REQUIRED',
        'APP 后端登录状态已失效，请重新登录',
      );
    }
    final cached = _backendDevices[deviceId];
    if (cached != null && cached.productId != null) return cached;

    final rows = await _backend.getUserProducts();
    final summary = rows.where((row) => row.deviceId == deviceId).firstOrNull;
    if (summary != null) {
      final detail = summary.productId == null
          ? await _backend.getUserProductDetail(summary.userProductId)
          : summary;
      _backendDevices[deviceId] = detail;
      return detail;
    }

    final device = deviceById(deviceId);
    if (device == null) {
      throw const ApiException('DEVICE_NOT_FOUND', '未找到需要关联的设备');
    }
    final products = await _backend.getProducts();
    final normalizedProductId = device.productId.trim().toLowerCase();
    final matches = products
        .where(
          (product) =>
              product.broadcastId.trim().toLowerCase() == normalizedProductId,
        )
        .toList(growable: false);
    final product = matches.length == 1
        ? matches.single
        : products.length == 1
        ? products.single
        : null;
    if (product == null) {
      throw ApiException(
        'PRODUCT_MAPPING_NOT_FOUND',
        '后台未找到涂鸦产品 ${device.productId} 对应的产品，请先配置 broadcastId',
      );
    }
    var created = await _backend.addUserProduct(
      deviceId: device.id,
      product: product,
    );
    if (created.productId == null) {
      created = created.copyWith(productId: product.productId);
    }
    _backendDevices[deviceId] = created;
    return created;
  }

  Future<void> _refreshBackendImages(
    String deviceId,
    BackendUserProduct backendDevice,
  ) async {
    final images = await _backend.getImages(backendDevice.userProductId);
    _backendAnimations[deviceId] = images
        .map(
          (image) => AnimationAsset(
            id: image.id.toString(),
            name: image.name,
            path: image.url,
            createdAt: DateTime.now(),
            synced: true,
          ),
        )
        .toList(growable: true);
    notifyListeners();
  }

  void _rememberPlants(Iterable<PlantProfile> plants) {
    for (final plant in plants) {
      final identifier = plant.tuyaIdentifier.trim().toLowerCase();
      if (identifier.isNotEmpty) _knownPlantsByIdentifier[identifier] = plant;
    }
  }

  PlantProfile? _plantForIdentifier(String identifier) {
    final normalized = identifier.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    return _knownPlantsByIdentifier[normalized] ??
        PlantCatalog.findByTuyaIdentifier(normalized);
  }

  void _setPlantSelection(
    String deviceId,
    PlantProfile plant, {
    bool notify = true,
  }) {
    _rememberPlants(<PlantProfile>[plant]);
    _plantedDevices.add(deviceId);
    _plantOverrides[deviceId] = plant;
    final index = _devices.indexWhere((device) => device.id == deviceId);
    if (index >= 0) {
      _devices[index] = _devices[index].copyWith(
        plant: plant,
        plantVariety: plant.tuyaIdentifier,
      );
    }
    if (notify) notifyListeners();
  }

  void _clearLocalSession() {
    _sessionEpoch++;
    _user = null;
    _devices = <SmartPlanterDevice>[];
    _plantedDevices.clear();
    _plantOverrides.clear();
    _settingsOverrides.clear();
    _backendDevices.clear();
    _backendPlants.clear();
    _backendAnimations.clear();
    _knownPlantsByIdentifier.clear();
    _animations.removeWhere((item) => !item.path.startsWith('builtin://'));
    _selectedDeviceId = null;
    _demoMode = false;
    // The native token belongs to the account that fetched it.
    _activatorTokenAt = null;
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
