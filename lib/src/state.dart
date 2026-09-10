import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/backend/backend.dart';
import 'core/cache/image_cache_cleanup.dart';
import 'core/network/api_exception.dart';
import 'features/auth/domain/auth_validator.dart';
import 'shared/l10n/app_language.dart';
import 'tuya/tuya_config.dart';
import 'tuya/tuya_memorial_codec.dart';
import 'tuya/tuya_models.dart';
import 'tuya/tuya_repository.dart';

class FlowerpotState extends ChangeNotifier {
  FlowerpotState({
    required TuyaRepository repository,
    AppBackendRepository? backendRepository,
  }) : _repository = repository,
       _backend = backendRepository ?? const DisabledAppBackendRepository();

  final TuyaRepository _repository;
  final AppBackendRepository _backend;
  bool _initialized = false;
  bool _busy = false;
  bool _sdkReady = false;
  bool _notificationsEnabled = true;
  int _sessionEpoch = 0;
  String _languageCode = 'zh';
  AppUser? _user;
  WifiScan? _wifiScan;

  /// 每台设备最近一次的固件升级进度，界面据此显示进度条。
  final Map<String, OtaProgress> _otaProgress = <String, OtaProgress>{};

  /// 每台设备最后一次收到升级事件的时刻，用来判断升级是不是断在半路。见
  /// [otaStalled]。
  final Map<String, DateTime> _otaUpdatedAt = <String, DateTime>{};

  /// 已发起升级但尚未收到 success 的目标版本号，收到后才写回设备。
  final Map<String, String> _pendingOtaVersion = <String, String>{};

  /// 云端说这台设备可以装、但还没装上的固件。
  ///
  /// 值由涂鸦 SDK 给出（App 不和设备直接说话），已经和当前版本比过，所以
  /// 「有值」就等于「有新版本」——小红点看的就是这个。里面同时带着 SDK 报的
  /// 「该组件当前版本」，弹窗上两行版本号因此来自同一条 OTA 记录。
  final Map<String, FirmwareUpdate> _availableFirmware =
      <String, FirmwareUpdate>{};

  /// [probeWifi] 自己的重入保护，见那里的说明。
  bool _wifiScanning = false;

  /// When [TuyaRepository.prepareActivatorToken] last succeeded. The token itself never
  /// leaves the native layer; this only tells the Wi-Fi page whether the AP
  /// step is still covered.
  DateTime? _activatorTokenAt;
  String? _selectedDeviceId;
  List<SmartPlanterDevice> _devices = <SmartPlanterDevice>[];

  /// 最近一次读取设备列表失败的原因，成功一次就清空。
  ///
  /// 登录、恢复会话这些路径读不到列表时不打断流程（`ignoreErrors: true`），但
  /// 「账号下没有设备」和「设备列表没读出来」在界面上必须分得开：两者以前都画成
  /// 「暂无设备」，用户重新登录后设备读不出来，看起来就像设备全没了。
  String? _deviceLoadError;

  /// 最近一次 APP 后端会话失效的原因，重新登录成功后清空。
  String? _backendSessionError;

  /// 本次会话开始时从本地缓存钉给原生的家庭；没有钉过就是 null。
  ///
  /// 用它区分「这次用的是缓存的家庭」还是「原生按涂鸦列表现挑的」——前者读出
  /// 0 台设备时要作废缓存重来一次，后者就是账号下真的没设备。
  String? _pinnedHome;

  /// 最近一次读取设备列表时所用的家庭 id（原生侧 `currentHomeId`）。
  ///
  /// 设备清单是按家庭查的，0 台设备最常见的原因不是没配上，而是这次查的家庭和
  /// 配网时用的不是同一个；这个值在真实页面上要看得见，不能只躺在联调页里。
  String? _lastHomeId;

  /// Server-side device rows keyed by the Tuya device id. Plant and image APIs
  /// require `userProductId`, so this mapping is resolved once and reused.
  final Map<String, BackendUserProduct> _backendDevices =
      <String, BackendUserProduct>{};
  final Map<String, List<AnimationAsset>> _backendAnimations =
      <String, List<AnimationAsset>>{};
  final Map<String, PlantProfile> _knownPlantsByIdentifier =
      <String, PlantProfile>{};

  /// 拉过植物目录仍然对不上的 DP 116 标识符。设备每次上报都会走一遍解析，没有
  /// 这份记录就会为同一个对不上的标识符反复打接口。
  final Set<String> _unresolvedPlantIdentifiers = <String>{};

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

  /// Custom memorial days per device id. DP 154 is write-only in practice —
  /// the device upserts by id and never reports the set back — so this map is
  /// the only record of which ids exist and what the user titled them, and it
  /// is persisted with the session.
  final Map<String, List<MemorialEntry>> _memorials =
      <String, List<MemorialEntry>>{};

  final List<AnimationAsset> _animations = <AnimationAsset>[];

  bool get initialized => _initialized;
  bool get busy => _busy;
  bool get sdkReady => _sdkReady;
  bool get authenticated => _user != null;
  bool get notificationsEnabled => _notificationsEnabled;

  bool get usingAppBackend => _backend.enabled;
  String get languageCode => _languageCode;

  /// 界面语言。文案目录 `AppL10n` 和 `MaterialApp` 都读这一个来源，
  /// 认不出的历史取值按简体中文处理，见 [AppLanguage.fromCode]。
  AppLanguage get language => AppLanguage.fromCode(_languageCode);
  AppUser? get user => _user;

  /// Last nearby-network scan, populated by [probeWifi]. Read by the pairing
  /// flow as well as the SDK console.
  WifiScan? get wifiScan => _wifiScan;

  /// 配网走到第几步了。配网页据此画「1.连接设备 / 2.发送Wi-Fi信息 / 3.连接云端」
  /// 那张进度卡；不在配网时是 [PairingStage.idle]。
  PairingStage get pairingStage => _pairingStage;
  PairingStage _pairingStage = PairingStage.idle;

  void _setPairingStage(PairingStage stage) {
    if (_pairingStage == stage) return;
    _pairingStage = stage;
    notifyListeners();
  }

  /// Tuya signs a provisioning token for 10 minutes and the bridge caches it
  /// for 8. The UI expires it earlier so switching to the device hotspot does
  /// not eat the whole margin.
  static const Duration activatorTokenLifetime = Duration(minutes: 7);

  /// Whether a provisioning token fetched by [TuyaRepository.prepareActivatorToken] should
  /// still be valid. AP pairing needs one before the phone leaves the router.
  bool get activatorTokenReady {
    final fetchedAt = _activatorTokenAt;
    return fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < activatorTokenLifetime;
  }

  List<SmartPlanterDevice> get devices => List.unmodifiable(_devices);

  String? get deviceLoadError => _deviceLoadError;

  String? get lastHomeId => _lastHomeId;

  /// 一行现场信息：涂鸦账号、这次查的家庭、读到几台、失败原因。
  ///
  /// 设备列表读不出来时直接画在页面上——比让用户去联调页翻要快，而且这几项正好
  /// 是判断「家庭选错了」还是「登进了别的账号」所需要的全部输入。
  String get sessionDiagnostics => <String>[
    'uid ${_user?.id ?? '-'}',
    '家庭 ${_lastHomeId ?? '-'}',
    '设备 ${_devices.length} 台',
    ?_deviceLoadError,
    if (_backendSessionError != null) '后端会话：$_backendSessionError',
  ].join(' · ');
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

  /// 设备有没有植物，以 DP 116 `plant_variety` 为准。
  ///
  /// 只看 [_plantedDevices] 会漏判：那个集合要等 116 的标识符能在植物目录里解析
  /// 成 [PlantProfile] 才会加进去，冷启动后目录还没拉的设备明明有植物也会被当成
  /// 空的，然后被详情页入口直接送去添加植物。
  bool hasPlant(String? deviceId) {
    if (deviceId == null) return false;
    final device = deviceById(deviceId);
    // DP 116 报 -1 就是明确「盆里没有植物」，比缓存权威：拔掉植物之后
    // `_plantedDevices` 里还留着上一株，不先判这条会一直显示有植物。
    if (device != null && PlantVariety.isMissing(device.plantVariety)) {
      return false;
    }
    if (_plantedDevices.contains(deviceId)) return true;
    return PlantVariety.hasPlant(device?.plantVariety);
  }

  /// DP 162 `plant_confirm`：设备要不要 App 弹引导窗，取值见 [PlantConfirmState]。
  PlantConfirmState plantConfirmState(String? deviceId) {
    if (deviceId == null) return PlantConfirmState.hidden;
    return deviceById(deviceId)?.plantConfirm ?? PlantConfirmState.hidden;
  }

  /// 设备正在等 App 弹「发现新植物」引导窗（DP 162 == 1）。
  bool plantGuidePending(String? deviceId) =>
      plantConfirmState(deviceId) == PlantConfirmState.prompt;

  /// 设备当前上报的植物 id（DP 116）。老固件报字符串标识符时返回 null。
  int? reportedPlantId(String? deviceId) {
    if (deviceId == null) return null;
    return PlantVariety.parse(deviceById(deviceId)?.plantVariety);
  }

  /// 设备当前上报的那一株在目录里的名字，解析不出来时返回 null。
  ///
  /// 引导窗的「已检测到 xxx 植物」用它；名字来自 APP 后端的植物目录，DP 116 只
  /// 给 id。
  String? reportedPlantName(String? deviceId) {
    if (deviceId == null) return null;
    final identifier = deviceById(deviceId)?.plantVariety.trim() ?? '';
    if (identifier.isEmpty || PlantVariety.isMissing(identifier)) return null;
    return _plantForIdentifier(identifier)?.name;
  }

  /// 设备明确报了「盆里没有植物」（DP 116 == -1）。
  ///
  /// 与 [hasPlant] 不是简单取反：老固件报字符串标识符时两者都按「有植物」算，
  /// 只有真的收到 -1 才是没有。
  bool plantMissing(String? deviceId) {
    if (deviceId == null) return false;
    final device = deviceById(deviceId);
    if (device == null) return false;
    return PlantVariety.isMissing(device.plantVariety);
  }

  /// 自动检测植物开关（`plant_detect_switch`）。关掉之后设备不再比对盆里的植物，
  /// App 也就不再弹植物确认——包括关之前设备已经报上来、还没处置的那次异常。
  bool plantDetectionEnabled(String? deviceId) {
    if (deviceId == null) return true;
    return deviceById(deviceId)?.settings.plantDetection ?? true;
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
      _restoreMemorials(preferences.getString(_memorialsKey));
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
        await _startSession();
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
    // 登录注册一体：验证码登录遇到没注册过的手机号时，后端仓库会用同一条验证码
    // 补一次注册，这里只负责把「新建了账号」这件事说给用户听。
    var created = false;
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
      created = backendAccount.registered;
      _user = await _loginTuyaAccount(backendAccount);
      _backendSessionError = null;
      await _rememberBackendUserId(backendAccount.userId);
      await _applyBackendHome(backendAccount.tuyaHomeId);
    } else {
      _user = await _repository.login(
        account: normalizedAccount,
        credential: normalizedCredential,
        region: region,
        verificationCode: verificationCode,
      );
    }
    await _startSession();
    return ActionResult(true, created ? '已为你创建账号并登录' : '登录成功');
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
      _backendSessionError = null;
      await _rememberBackendUserId(backendAccount.userId);
      await _applyBackendHome(backendAccount.tuyaHomeId);
    } else {
      _user = await _repository.register(
        account: normalizedAccount,
        password: normalizedPassword,
        code: normalizedCode,
        region: region,
      );
    }
    await _startSession();
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
    // 国内账号的登录密码归 APP 后端管——涂鸦那边用的是后端下发的 tuYaPwd，
    // 用户根本没见过——所以重置要打后端。海外仍然是涂鸦自己的邮箱账号体系。
    if (region == LoginRegion.domestic && _backend.enabled) {
      await _backend.resetPassword(
        mobile: normalizedAccount,
        verifyCode: normalizedCode,
        password: normalizedPassword,
      );
    } else {
      await _repository.resetPassword(
        account: normalizedAccount,
        newPassword: normalizedPassword,
        code: normalizedCode,
        region: region,
      );
    }
    return const ActionResult(true, '密码已更新，请使用新密码登录');
  });

  Future<void> refreshDevices() async {
    await _refreshDevicesForSession(ignoreErrors: false);
  }


  /// Nearby access points: AP 配网要能看见设备热点，而设备本身只连 2.4 GHz。
  ///
  /// Used by the pairing flow — the search step looks for planter hotspots and
  /// the Wi-Fi step lists real 2.4 GHz routers. Does
  /// not touch the Tuya SDK, so it answers even before initialization.
  ///
  /// 不参与 [_guard] 的全局单操作锁：这是个只读调用，和别的操作没有真实冲突，
  /// 而 Android 上一次扫描要好几秒。占着锁的话，这期间用户发起的任何操作——
  /// 换页后再扫一次、配网页取令牌——都会被挡成「请等待当前操作完成」，在选择
  /// 设备页上还会被当成扫描失败的原因显示出来。这里只防它自己重入。
  ///
  /// [refresh] = false 时**只读系统的扫描缓存、不主动发起扫描**：那条路不受
  /// Android 的扫描配额限制（前台每 2 分钟 4 次 `startScan`），也不必等广播，
  /// 所以搜索页可以 1 秒读一次；真扫按配额均匀排到 32 秒一次。系统自己（连接管理、
  /// 其它应用、设置页）也在扫，缓存会被它们刷新——这正是「读缓存」能提速的原因。
  Future<ActionResult> probeWifi({bool refresh = true}) async {
    if (_wifiScanning) {
      return const ActionResult(
        false,
        '正在扫描附近网络，请稍候',
        code: 'wifi_scanning',
      );
    }
    _wifiScanning = true;
    try {
      return await _run(() => _probeWifi(refresh: refresh));
    } finally {
      _wifiScanning = false;
      notifyListeners();
    }
  }

  Future<ActionResult> _probeWifi({required bool refresh}) async {
    final scan = await _repository.scanWifi(refresh: refresh);
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

  /// 会把失败说出来的设备列表刷新：设备列表页的下拉刷新 / 重试共用这一个
  /// 入口。和会话恢复那条静默路径（`ignoreErrors: true`）相反，家庭查询、自动建家
  /// 和设备列表的失败都作为 [ActionResult] 返回，不会被吞掉。
  Future<ActionResult> reloadDevices() => _run(() async {
    await _refreshDevicesForSession(ignoreErrors: false);
    // 带上家庭 id：0 台设备最常见的原因不是没配上，而是查的家庭和配网时用的
    // 不是同一个，而那在 Dart 侧原本完全看不出来。
    final home = await _repository.currentHomeId().catchError((_) => '?');
    return ActionResult(
      true,
      '设备列表已刷新，共 ${_devices.length} 台（家庭 $home）',
    );
  });

  Future<ActionResult> logout() => _guard(() async {
    // Invalidate pending profile/device reads before waiting for network logout.
    _clearLocalSession();
    notifyListeners();
    if (_backend.enabled && _backend.hasSession) {
      try {
        await _backend.logout();
      } catch (_) {
        // 服务端退登失败不该把用户卡在已登录界面，本地令牌照样清掉。
      }
    }
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
    // 先注销 APP 后端账号，它才是登录入口。反过来先删涂鸦账号的话，一旦这步
    // 失败，用户还能登录进来、却拿不到可用的涂鸦会话，设备一台都出不来。
    if (_backend.enabled && _backend.hasSession) {
      await _backend.deactivateAccount();
    }
    await _repository.deleteAccount();
    _backend.clearSession();
    _clearLocalSession();
    return const ActionResult(true, '账号已注销');
  });

  Future<ActionResult> pairDevice(PairingRequest request) =>
      _guard(() => _pairInternal(request));

  /// Dart 侧兜底的等待上限。原生各自有超时（系统弹框 60 秒、activator 120 秒），
  /// 这里只防原生永远不回话的情况——那会让 [_guard] 的 busy 锁永远不放，整个
  /// App 都点不动。到点后主动 [cancelPairing]，让原生把资源放掉。
  static const Duration hotspotJoinDeadline = Duration(seconds: 90);
  static const Duration pairingDeadline = Duration(seconds: 150);

  /// 一步走完 AP 配网：取令牌 → 连设备热点 → 配网。
  ///
  /// 三件事必须按这个顺序、并且在同一次操作里完成：令牌只能在手机还连着路由器
  /// 时去云端取，而连上设备热点之后就没有外网了。拆成三个按钮让用户自己按顺序
  /// 点，中间任何一步走神都会失败，而失败原因（令牌过期、没连上热点）从涂鸦的
  /// `1006 out of time` 里完全看不出来。
  ///
  /// 平台连不了热点（iOS、Android 9 及以下）时回落到手动路径：先看手机是不是
  /// 已经连在设备热点上，不是就以 `hotspot_manual_required` 失败并保留令牌，
  /// 页面据此引导用户去系统设置连热点；用户连好后带 [hotspotJoinedManually]
  /// 再调一次，令牌在有效期内直接复用，不再去云端取（那时已经没有外网了）。
  ///
  /// 任何一步失败都会释放热点连接与进程网络绑定：那是原生层的状态，不释放的话
  /// 进程会一直绑在一个没有互联网的网络上，之后的回查设备、重试取令牌全部失败，
  /// 看起来就像「设备被占住了」。
  /// 配网前的准备：先把家庭确认下来、再取令牌，这两步都要走云端，必须在手机
  /// 还连着路由器时完成。
  ///
  /// 连上设备热点之后手机就没有外网，那时再查家庭轻则失败、重则拿到一份空列表
  /// 被当成「这个账号还没有家庭」而新建一个——账号里从此多一个空家庭，下次登录
  /// 就可能读到它、一台设备都没有。所以配网页先跑这一步、转个圈，成了才去连热点。
  Future<ActionResult> prepareForPairing() => _guard(() async {
    var home = '';
    try {
      home = await _repository.currentHomeId();
    } on TuyaException catch (error) {
      // 装着旧原生包的机器上没有这个方法，不拦路：取令牌本身也会解析家庭。
      // 其它错误都是真的没查到，照常抛出去。
      if (error.code != 'sdk_unavailable') rethrow;
    }
    // ⚠️ **家庭没确认下来不再拦路。**
    //
    // 这道门禁是 2026-09-09 的 `d0ab4d0` 加的，本意是「别在设备热点上查家庭、
    // 免得拿到空列表自动建一个空家庭」。但它把「查不到」也当成了「不能配网」：
    // `currentHomeId` 返回 0 只表示此刻还没解析出来，涂鸦的 activator 自己会在
    // 配网时解析家庭，而这一步跑在**还连着路由器**的时候，本来就不存在建空家庭
    // 的风险。原样抛出去的结果是「开始配网」直接失败、配网根本没开始——用户看到
    // 的就是「昨天还能配，今天点了没反应」。
    //
    // 现在只把它记进诊断信息，照常往下走：真的没有家庭时，配网自己会失败，
    // 那时的报错才是真实原因。
    final homeUnresolved = home == '0';
    if (home.isNotEmpty && !homeUnresolved) {
      _lastHomeId = home;
      await _rememberHome(home);
    }
    if (!activatorTokenReady) {
      await _repository.prepareActivatorToken();
      _activatorTokenAt = DateTime.now();
    }
    notifyListeners();
    return ActionResult(
      true,
      switch (home) {
        '' => '准备就绪',
        '0' => '准备就绪（家庭待解析）',
        _ => '准备就绪（家庭 $home）',
      },
    );
  });

  /// 「热点配网新流程」查到的、**设备自己扫到的** Wi-Fi 列表。
  List<DeviceWifiNetwork> get deviceWifiNetworks => _deviceWifiNetworks;
  List<DeviceWifiNetwork> _deviceWifiNetworks = const <DeviceWifiNetwork>[];

  /// 新流程第一步：让 SDK 连上设备热点并读回设备扫到的 Wi-Fi 列表。
  ///
  /// 成功即意味着**设备已经连上了**——这一步替代了原来「手机扫热点 + App 用
  /// `WifiNetworkSpecifier` 去连」的一整套，也就没有那个系统入网授权框了。
  ///
  /// ⚠️ 只对新固件有效（TuyaOS ≥ 3.6.1）。老固件上会以 `207206`（设备状态无法识别）
  /// 或超时失败，那时才需要退回原流程。
  Future<ActionResult> connectDeviceForPairing({
    Duration timeout = const Duration(seconds: 60),
  }) => _guard(() async {
    _setPairingStage(PairingStage.connectingDevice);
    try {
      final networks = await _repository.apQueryDeviceWifi(timeout: timeout);
      _deviceWifiNetworks = networks;
      notifyListeners();
      return ActionResult(true, '已连接设备，读到 ${networks.length} 个可用网络');
    } finally {
      _setPairingStage(PairingStage.idle);
    }
  });

  /// 新流程第二步：把路由器凭据下发给设备。
  /// 放掉设备热点连接，把手机的 Wi-Fi **还原回原来那个网络**。
  ///
  /// 我们用 `WifiNetworkSpecifier` 连设备热点期间，手机是真的离开了路由器、**没有外网**。
  /// 原生的 `leaveDeviceHotspot` 会取消那个网络请求并解开进程绑定，系统随即自动切回
  /// 已保存的路由器——所以"还原"这件事只要**保证调到**就行。
  ///
  /// ⚠️ **每一条离开配网动线的路径都必须调它**，包括配网成功那条：成功之后设备会关掉
  /// 自己的热点，进程若还绑在那个已经消失的网络上，紧接着读设备列表就会失败——看起来
  /// 就是「配网成功但读不到设备」。
  ///
  /// 不走 [_guard]、不抛错、可以重复调：它的职责就是"无论如何把网络还回去"，
  /// 任何一次调用失败都不该盖过调用方真正要报的东西。
  Future<void> releaseDeviceHotspot() async {
    try {
      await _repository.leaveDeviceHotspot();
    } catch (_) {
      // 没有连接可放、平台没实现，都不影响。
    }
  }

  /// 单独把手机连到设备热点上，不配网。
  ///
  /// 2026-09-10 产品定的动线：**搜索页扫到设备就先把热点连上**，之后才让用户选路由器
  /// Wi-Fi、输密码。这样排有两个好处：
  ///
  /// 1. 解掉一个矛盾——手机一旦挂在设备热点上，「带出当前 Wi-Fi 名」这条规则只能留空
  ///    （填热点名等于让设备去连它自己）。先连热点、再让用户自己选，本来就不需要带出。
  /// 2. 把那次系统确认框挪到用户刚点完设备、注意力还在这件事上的时候。
  ///
  /// ⚠️ **调用方必须先等 `prepareForPairing()` 跑完。** 取令牌、取安全配置、确认家庭
  /// 都要走云端，而这一步一执行手机就没有外网了。
  ///
  /// ⚠️ 连上之后**不要以为它一定还在**：`WifiNetworkSpecifier` 建的是进程专属的一次性
  /// 连接，系统可能在用户选 Wi-Fi、输密码那段时间里把它掉掉。所以
  /// [pairViaDeviceHotspot] 的第①步照常保留——已连就跳过，掉了就重连。
  Future<ActionResult> connectDeviceHotspot({String? hotspotSsid}) =>
      _guard(() async {
        final target =
            hotspotSsid ??
            _wifiScan?.deviceHotspots.map((item) => item.ssid).firstOrNull;
        _setPairingStage(PairingStage.connectingDevice);
        try {
          final joinedByApp = await _joinHotspotForPairing(
            target: target,
            joinedManually: false,
          );
          return ActionResult(
            true,
            joinedByApp ? '已连接设备热点' : '手机已经在设备热点上',
          );
        } finally {
          _setPairingStage(PairingStage.idle);
        }
      });

  /// 涂鸦「热点配网新流程」的完整序列。
  ///
  /// ## 三步，顺序不能动
  ///
  /// | 步骤 | 做什么 | 对应 |
  /// | --- | --- | --- |
  /// | ① | **把手机连到搜索页扫到的那个设备热点上** | `_joinHotspotForPairing`（确切 SSID） |
  /// | ② | 建立与设备的通道并查它的状态 | `apQueryDeviceWifi` = `queryDeviceConfigState` |
  /// | ③ | 下发路由器 SSID/密码 | `apStartPairing` = `startActivator` |
  ///
  /// 取令牌、取安全配置、确认家庭这三件**走云端**的事由搜索页的 `prepareForPairing`
  /// 在**手机还连着路由器时**做完——①一执行手机就没有外网了。
  ///
  /// ## 为什么①必须由我们做（2026-09-10 实测结论，不要再推翻）
  ///
  /// 「搜到」和「能连上」是两件事：搜索页用 `WifiManager.getScanResults()` 只能**看见**
  /// 热点名，连上要另一套 API。而 Android 10+ 上让应用连指定热点**只有**
  /// `WifiNetworkSpecifier` + `requestNetwork` 一条公开路，它**必然弹一次系统确认框**，
  /// 关不掉、也不能由 App 代点（`addNetwork`/`enableNetwork` 对 targetSdk ≥ 29 的应用
  /// always fail）。
  ///
  /// **涂鸦 SDK 也不例外**——它只是跑在本进程里的库、没有额外特权。实测：完整官方序列下
  /// 单独调②，跑满 45 秒报 `207220`（配网任务整体超时），**全程没有弹出任何系统框、
  /// 手机始终在路由器上** ⇒ 它根本没去连。文档里「SDK 会在指定时间内自动去连接 AP 热点」
  /// 那句写在**「恢复配网」**一节，讲的是中途掉线后重连**它已经连过的**热点；同一页开篇
  /// 写的才是通用前提——「将手机连接到配网设备 Wi-Fi 热点后……**但用户需要手动切换手机的
  /// Wi-Fi 设置**」。
  ///
  /// ## 产品口径：自动选中，一次确认
  ///
  /// 做不到「零确认」，但做得到**自动选中**：把搜索页拿到的**确切热点名**交给系统，
  /// 框里就只有这一台、已经选好，用户点一下「连接」，全程不离开 App
  /// （2026-09-10 产品决定，见 `docs/PRODUCT_RULES.md` 1.2）。
  /// 手机已经连在该热点上时 [_joinHotspotForPairing] 直接跳过，**零点击**。
  ///
  /// ⚠️ 只给前缀会触发系统那个「查找设备…／没有找到任何设备」的搜索框，所以 Android
  /// 原生**拒绝只给前缀**（`hotspot_ssid_required`）；iOS 相反，只能给前缀。
  ///
  /// ## ②那份 Wi-Fi 列表不展示
  ///
  /// 产品口径是「配网就用手机当前连着的那个网络」，所以②回来的**设备视角 Wi-Fi 列表
  /// 收下不展示**；调它要的是建通道 + 查设备状态这个前置效果。唯一容忍的失败是
  /// `207207`（设备不支持读列表）——文档明说不影响配网。
  ///
  /// 每步耗时 + 涂鸦自己报的最后一步都写进失败消息：失败码只说「哪一类」，这两样才说
  /// 「死在哪一步」。
  Future<ActionResult> pairViaDeviceHotspot({
    required String ssid,
    required String password,
    String? hotspotSsid,
    Duration timeout = const Duration(seconds: 120),
    Duration queryTimeout = const Duration(seconds: 45),
  }) => _guard(() async {
    final steps = <String>[];
    final watch = Stopwatch()..start();
    void mark(String name) {
      steps.add('$name ${watch.elapsedMilliseconds}ms');
      watch.reset();
    }

    // 涂鸦 activator 自己报的进度（`onStep`）。智能生活 App 在 AP 配网时展示的
    // 「设备连接建立成功 / Wi-Fi 配置已下发 / 设备连接路由器成功 / 设备激活中 /
    // 设备即将上线」就是这一串。拿它把进度页从**猜**改成**真**，失败时也把最后到过
    // 哪一步写进消息——那比失败码更能说明卡在哪。
    final tuyaSteps = <String>[];

    String withSteps(String message) {
      final parts = <String>[
        ...steps,
        if (tuyaSteps.isNotEmpty) '涂鸦进度「${tuyaSteps.last}」',
      ];
      return parts.isEmpty ? message : '$message｜${parts.join(' · ')}';
    }

    // 凭据发出去了令牌就可能已被设备用掉，失败时要作废、下次重新取。
    var pairingStarted = false;
    StreamSubscription<String>? stepSub;
    var hotspotRequested = false;
    _setPairingStage(PairingStage.connectingDevice);
    try {
      stepSub = _repository.pairingSteps.listen((step) {
        tuyaSteps.add(step);
        debugPrint('[pairing] step $step');
        // 第一条 `onStep` 意味着与设备的通道已经建立；之后的都属于「设备在连路由器、
        // 连云激活」那一段。步骤常量名文档没列，所以按**到达顺序**判断——顺序是 SDK
        // 保证的，真机日志确认了名字之后可以改成按名字精确映射。
        _setPairingStage(
          tuyaSteps.length <= 1
              ? PairingStage.sendingWifi
              : PairingStage.connectingCloud,
        );
      });
      // ① 把手机连到搜索页扫到的那台设备的热点上。确切名字优先用带过来的那个，
      // 退到扫描里认出来的第一个。系统会为此弹一次确认框（删不掉，见类注释），
      // 已经连在该热点上时直接跳过、零点击。
      final target =
          hotspotSsid ??
          _wifiScan?.deviceHotspots.map((item) => item.ssid).firstOrNull;
      hotspotRequested = true;
      final joinedByApp = await _joinHotspotForPairing(
        target: target,
        joinedManually: false,
      );
      mark(joinedByApp ? '连热点(${target ?? '前缀'})' : '连热点(已连)');

      // ② 建立与设备的通道并查它的状态。回来的 Wi-Fi 列表收下不展示。
      final label = hotspotSsid == null ? '查设备' : '查设备($hotspotSsid)';
      try {
        _deviceWifiNetworks = await _repository.apQueryDeviceWifi(
          timeout: queryTimeout,
        );
        mark('$label ${_deviceWifiNetworks.length}网络');
      } on TuyaException catch (error) {
        // 207207 = 设备不支持获取 Wi-Fi 列表。文档明说不影响配网，继续。
        if (error.code != '207207') rethrow;
        mark('$label 不支持列表');
      }

      // ② 下发路由器凭据。
      pairingStarted = true;
      _setPairingStage(PairingStage.sendingWifi);
      final device = await _repository.apStartPairing(
        ssid: ssid,
        password: password,
        timeout: timeout,
      );
      mark('配网');
      // ⚠️ 凭据已经交给设备，它随即关掉热点去连路由器。**这里必须马上把手机的 Wi-Fi
      // 还回去**：下面要读设备列表、要连云端，而进程这时还绑在那个已经消失的网络上。
      // 少了这一句，表现就是「配网成功但读不到设备信息」。
      await releaseDeviceHotspot();
      _setPairingStage(PairingStage.connectingCloud);
      // 涂鸦真报了进度就不用再装：那 1–2 秒随机停留是因为第三步原来**没有任何真实
      // 信号**（见 [_cloudStageDelay]）。现在有 `onStep` 了，有就用真的。
      if (tuyaSteps.isEmpty) {
        await Future<void>.delayed(_cloudStageDelay());
      }
      _activatorTokenAt = null;
      _devices = <SmartPlanterDevice>[
        ..._devices.where((item) => item.id != device.id),
        device,
      ];
      _selectedDeviceId = device.id;
      return const ActionResult(true, '设备配网成功');
    } on TuyaException catch (error) {
      // 手动引导不是失败：热点还没连、令牌也没用过，什么都不用放。
      final manual = error.code == _manualHotspotCode;
      mark(manual ? '待手动连热点' : '失败');
      if (!manual) {
        await _releaseDeviceHotspotPairing(
          releaseHotspot: hotspotRequested,
          invalidateToken: pairingStarted,
        );
      }
      throw TuyaException(error.code, withSteps(error.message));
    } catch (_) {
      mark('失败');
      await _releaseDeviceHotspotPairing(
        releaseHotspot: hotspotRequested,
        invalidateToken: pairingStarted,
      );
      rethrow;
    } finally {
      await stepSub?.cancel();
      _setPairingStage(PairingStage.idle);
    }
  });

  /// 新流程失败后的收尾。
  ///
  /// **两样都要放**：我们自己用 `WifiNetworkSpecifier` 建的热点连接（进程网络绑定，
  /// 走 `leaveDeviceHotspot`），以及 SDK 的配网器（走 `apStopPairing`）。少放哪一样都会
  /// 让下一次配网起不来——绑着一个没有外网的网络，取令牌必然失败。
  Future<void> _releaseDeviceHotspotPairing({
    required bool releaseHotspot,
    required bool invalidateToken,
  }) async {
    if (invalidateToken) _activatorTokenAt = null;
    _deviceWifiNetworks = const <DeviceWifiNetwork>[];
    try {
      await _repository.apStopPairing();
    } catch (_) {
      // 没有在跑的配网器，或平台没实现，都不影响上报原始错误。
    }
    if (!releaseHotspot) return;
    try {
      await _repository.leaveDeviceHotspot();
    } catch (_) {
      // 原生没有连接可放，或平台没实现，同样不影响。
    }
  }

  /// 手机此刻是不是已经连在设备热点上。
  ///
  /// AP 配网的前置条件。读的是扫描缓存里的当前 SSID，不发起扫描、不占配额。
  bool get onDeviceHotspot => _wifiScan?.currentIsDeviceHotspot ?? false;

  /// 刷新一次「当前连的是哪个网络」。只读缓存，不占扫描配额。
  ///
  /// 等用户在系统 Wi-Fi 面板里连设备热点时就靠它轮询。
  Future<bool> refreshOnDeviceHotspot() async {
    await probeWifi(refresh: false);
    return onDeviceHotspot;
  }

  /// 拉起系统 Wi-Fi 选择界面，让用户自己连设备热点。
  ///
  /// 为什么是「用户自己连」而不是 App 发起：见原生 `openWifiPanel` 的说明——
  /// Android 10+ 上 App 发起必弹系统入网授权框，产品要求不要那个框。
  Future<ActionResult> openWifiPanel() =>
      _run(() async {
        await _repository.openWifiPanel();
        return const ActionResult(true, '已打开系统 Wi-Fi 列表');
      });

  /// 放掉新流程的配网器与它持有的热点连接。退出配网动线时调用。
  Future<void> stopDevicePairing() async {
    _deviceWifiNetworks = const <DeviceWifiNetwork>[];
    try {
      await _repository.apStopPairing();
    } catch (_) {
      // 没有在跑的配网器，或平台没实现，都不影响。
    }
    _setPairingStage(PairingStage.idle);
  }

  Future<ActionResult> pairViaHotspot({
    required String ssid,
    required String password,
    String? hotspotSsid,
    bool hotspotJoinedManually = false,
  }) => _guard(() async {
    // 三步各自计时并写进结果文案。整个过程只吐一个最终结果的话，卡在取令牌、
    // 连热点还是下发凭据上完全看不出来——而这三步的失败在涂鸦那边都可能表现成
    // 同一个 `1006 out of time`。
    final steps = <String>[];
    final watch = Stopwatch()..start();
    void mark(String name) {
      steps.add('$name ${watch.elapsedMilliseconds}ms');
      watch.reset();
    }

    String withSteps(String message) => '$message｜${steps.join(' · ')}';

    // 连热点这一步一旦发出去，失败时就要释放；配网一旦发出去，令牌就可能已被
    // 设备用掉，失败时要作废，下次重新取。
    var hotspotRequested = false;
    var pairingStarted = false;
    _setPairingStage(PairingStage.connectingDevice);
    try {
      if (activatorTokenReady) {
        // 上一次只走到连热点就失败了（弹框取消、手动路径），令牌没用过，还在
        // 有效期内就直接用。手动路径下这时手机已经在热点上，再去取也取不到。
        mark('令牌(复用)');
      } else {
        await _repository.prepareActivatorToken();
        _activatorTokenAt = DateTime.now();
        mark('令牌');
      }

      // 优先用扫描里真实看到的热点名（选择设备页选的那个，或扫描认出来的第一
      // 个）。退到前缀匹配时只能给一个模式，漏掉 `ty_` / `ysplanter` /
      // `SmartLift-` 这些的话，系统找不到匹配网络就不弹框、直接回
      // onUnavailable，看起来就像用户取消了。
      final target =
          hotspotSsid ??
          _wifiScan?.deviceHotspots.map((item) => item.ssid).firstOrNull;
      hotspotRequested = true;
      final joinedByApp = await _joinHotspotForPairing(
        target: target,
        joinedManually: hotspotJoinedManually,
      );
      mark(
        joinedByApp
            ? '连热点${target == null ? '(前缀)' : '($target)'}'
            : '连热点(手动)',
      );

      pairingStarted = true;
      _setPairingStage(PairingStage.sendingWifi);
      final result = await _pairInternal(
        PairingRequest(ssid: ssid, password: password, mode: 'ap'),
      );
      mark('配网');
      return ActionResult(
        result.success,
        withSteps(result.message),
        code: result.code,
      );
    } on TuyaException catch (error) {
      final manual = error.code == _manualHotspotCode;
      mark(manual ? '待手动连热点' : '失败');
      // 手动引导不是失败：令牌留着，热点也还没连，什么都不用放。
      if (!manual) {
        await _abandonPairingAttempt(
          releaseHotspot: hotspotRequested,
          invalidateToken: pairingStarted,
        );
      }
      throw TuyaException(error.code, withSteps(error.message));
    } on ApiException catch (error) {
      mark('失败');
      await _abandonPairingAttempt(
        releaseHotspot: hotspotRequested,
        invalidateToken: pairingStarted,
      );
      throw ApiException(
        error.code,
        withSteps(error.message),
        data: error.data,
      );
    } catch (_) {
      await _abandonPairingAttempt(
        releaseHotspot: hotspotRequested,
        invalidateToken: pairingStarted,
      );
      rethrow;
    } finally {
      // 成功、失败、等手动连热点，出口都在这里；不清掉的话进度卡会一直停在
      // 最后一步上，看起来像还在配。
      _setPairingStage(PairingStage.idle);
    }
  });

  static const String _manualHotspotCode = 'hotspot_manual_required';

  /// 让手机连上设备热点。返回 true 表示由 App 发起的连接（配网后由原生释放），
  /// false 表示走的是手动路径（用户自己在系统设置里连的）。
  ///
  /// 只有 `hotspot_join_unsupported` 会回落到手动路径；弹框被取消、热点不存在、
  /// 绑定失败这些都照常抛出，那是这次尝试真的失败了。
  Future<bool> _joinHotspotForPairing({
    required String? target,
    required bool joinedManually,
  }) async {
    // 手机已经连在目标热点上（上一次尝试留下的、或用户自己连的）就直接用。
    //
    // Android 10+ 每次 `requestNetwork` 都会弹一次系统确认框，而它**关不掉也
    // 不能替用户点**——那是系统的入网授权提示。能做的就是别在已经连上的时候再
    // 申请一次，白弹一个框。读当前 SSID 走只读缓存那条路，不发起扫描。
    if (target != null && !joinedManually) {
      try {
        final scan = await _repository.scanWifi(refresh: false);
        _wifiScan = scan;
        if (scan.current == target) return false;
      } catch (_) {
        // 读不到就照常往下走，最多是多弹一次框。
      }
    }
    try {
      // 有确切热点名就用它；没有就给前缀。**这两条路的可用性按平台分**：
      //
      // - Android：`WifiNetworkSpecifier` 给前缀时走「按模式搜索」那一支，系统会
      //   弹「查找设备…」并可能停在「没有找到任何设备…」——那是系统 UI，App 关不
      //   掉，只能不触发它。所以 Android 原生侧**拒绝只给前缀的请求**
      //   （`hotspot_ssid_required`）；Android 能枚举附近网络，搜索页一定拿得到
      //   确切名字。
      // - iOS：**没有任何公开 API 能列出附近 Wi-Fi**（`NEHotspotHelper` 要 Apple
      //   特批的 entitlement），所以确切名字永远拿不到。但 iOS 不需要——
      //   `NEHotspotConfiguration(ssidPrefix:)` 可以直接按前缀连上热点，系统弹一次
      //   确认框即可。前缀是 iOS 唯一可行的路，不能砍。
      final joined = await _repository
          .joinDeviceHotspot(
            ssid: target,
            prefix: target == null ? WifiNetwork.hotspotJoinPrefix : null,
          )
          .timeout(
            hotspotJoinDeadline,
            onTimeout: () => throw const TuyaException(
              'hotspot_join_timeout',
              '等待连接设备热点超时',
            ),
          );
      if (!joined) {
        throw const TuyaException('hotspot_join_failed', '未能连上设备热点');
      }
      return true;
    } on TuyaException catch (error) {
      if (error.code != 'hotspot_join_unsupported') rethrow;
    }
    // 平台不让 App 连热点。用户说已经连好了就信；否则看一眼当前网络——能确认
    // 在热点上就直接配，确认不了（iOS 没有读 SSID 的权限时 current 为空）或者
    // 明显还在路由器上，就让页面引导用户去系统设置连。
    if (joinedManually) return false;
    WifiScan? scan;
    try {
      scan = await _repository.scanWifi();
      _wifiScan = scan;
    } catch (_) {
      // 扫描失败不影响判断：按「无法确认」处理。
    }
    if (scan != null && scan.currentIsDeviceHotspot) return false;
    throw TuyaException(
      _manualHotspotCode,
      '当前系统不允许 App 直接连接热点，请到系统设置连接设备热点'
      '${target == null ? '' : '「$target」'}后，回到本页再点「开始配网」',
    );
  }

  /// 一次配网尝试失败后的收尾。
  ///
  /// [releaseHotspot] 时让原生放掉热点连接与进程网络绑定；[invalidateToken] 时
  /// 作废本地记录的令牌时间——配网已经发出去，令牌可能已经被设备用掉，重试时
  /// 重新取一枚。两边都不能抛：这里已经在错误路径上，原始错误才是要报的那个。
  Future<void> _abandonPairingAttempt({
    required bool releaseHotspot,
    required bool invalidateToken,
  }) async {
    if (invalidateToken) _activatorTokenAt = null;
    if (!releaseHotspot) return;
    try {
      await _repository.leaveDeviceHotspot();
    } catch (_) {
      // 原生没有连接可放，或平台没实现，都不影响上报原始错误。
    }
  }

  /// 中止进行中的配网并释放热点连接与网络绑定。
  ///
  /// 不走 [_guard]：配网本身正占着那把锁。进行中的 `pair` 会以 `pair_cancelled`
  /// 返回，[pairViaHotspot] 照常收尾。用户中途退出配网页时由页面调用；没有配网
  /// 在跑时调用也安全。
  Future<ActionResult> cancelPairing() => _run(() async {
    // Release native resources immediately; notify only after the async boundary.
    _activatorTokenAt = null;
    await _repository.cancelPairing();
    _setPairingStage(PairingStage.idle);
    // 令牌没被消耗，但配网是否已经送到设备上说不清，保守起见重取。
    _activatorTokenAt = null;
    return const ActionResult(true, '已中止配网，设备热点连接已释放');
  });

  /// 第三步「连接云端」的停留时长。**只在涂鸦一条 `onStep` 都没报时才用。**
  ///
  /// ⚠️ **这一步原来没有接任何实际业务**：涂鸦的 activator 返回时设备其实已经注册
  /// 到云端了，所以没有可等的东西。产品口径是先给它一个 1–2 秒的随机停留、然后
  /// 直接按成功处理——否则第三步会一闪而过，用户看到的是「第二步刚亮起就跳走了」。
  /// 2026-09-10 起已经接上了真信号：`onStep` 一旦有上报，`pairViaDeviceHotspot` 就按
  /// 真实进度走，不再用这段延时（智能生活展示的「设备激活中 / 设备即将上线」正是它）。
  /// 这里只留作**没有任何上报时**的兜底，免得第二步刚亮起就跳走。
  static Duration _cloudStageDelay() =>
      Duration(milliseconds: 1000 + Random().nextInt(1000));

  Future<ActionResult> _pairInternal(PairingRequest request) async {
    final device = await _pairOrRecover(request);
    // 凭据已经被设备收下，接下来是它自己连路由器、注册到云端。
    _setPairingStage(PairingStage.connectingCloud);
    await Future<void>.delayed(_cloudStageDelay());
    // Tuya tokens are single-use and the bridge drops its cached copy on
    // success, so the next AP attempt has to fetch a new one.
    _activatorTokenAt = null;
    _devices = <SmartPlanterDevice>[
      ..._devices.where((item) => item.id != device.id),
      device,
    ];
    _selectedDeviceId = device.id;
    // 配网是涂鸦侧的事，这里不再顺带去后端建 userProduct 记录：那条链路
    // （getUserProductList / getProductList / addUserProduct）只服务后端自己的
    // 存档，却会把「配网成功」拖成失败提示。
    return const ActionResult(true, '设备配网成功');
  }

  /// 配网，报错时回查云端确认设备是不是其实已经绑上了。
  ///
  /// 设备可能已经激活，只是 App 没等到云端的确认——AP 配网下很常见：设备一拿到
  /// 凭据就关掉热点去连路由器，手机正在从热点切回路由器的这个空档里，SDK 的确认
  /// 请求发不出去，最后报 `1006 out of time`，而设备其实已经绑到账号上了。云端
  /// 的设备列表才是权威，所以判失败之前先问一次。
  Future<SmartPlanterDevice> _pairOrRecover(PairingRequest request) async {
    final knownIds = _devices.map((item) => item.id).toSet();
    try {
      return await _repository
          .pair(request)
          .timeout(pairingDeadline, onTimeout: _abortStalledPairing);
    } on TuyaException catch (error) {
      // 主动中止和原生没回话这两种，设备都不可能刚好配上，不必再等六秒回查。
      if (error.code == 'pair_cancelled' || error.code == 'pair_timeout') {
        rethrow;
      }
      final recovered = await _recoverPairedDevice(knownIds);
      if (recovered == null) rethrow;
      debugPrint('[pair] ${error.code} 后在云端发现新设备，按成功处理');
      return recovered;
    }
  }

  /// 原生超过 [pairingDeadline] 没回话时的收尾：让它停掉并释放资源，再以
  /// `pair_timeout` 失败。原生若稍后才回话，那条回复会被平台通道丢弃。
  Future<SmartPlanterDevice> _abortStalledPairing() async {
    try {
      await _repository.cancelPairing();
    } catch (_) {
      // 已经在超时路径上，取消失败没有更好的处理。
    }
    throw const TuyaException('pair_timeout', '配网长时间没有结果，已中止');
  }

  /// 配网报错后回查云端，看是否其实已经绑上了一台新设备。
  ///
  /// 只认[knownIds]之外的设备：重试时账号里可能已经有别的花盆，不能把任意一台
  /// 当成本次配网的结果。查询本身失败就返回 null，让原来的错误照常抛出。
  Future<SmartPlanterDevice?> _recoverPairedDevice(Set<String> knownIds) async {
    // 手机这时刚从设备热点切回路由器，网络要几秒才稳，立刻查多半还是失败。
    // 配网本身已经等了两分钟，这里多花几秒换一次准确判断是划算的。
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final devices = await _repository.getDevices();
        for (final device in devices) {
          if (!knownIds.contains(device.id)) return device;
        }
      } catch (_) {
        // 这一轮网络还没好，再试。三轮都不行就保持原错误。
      }
    }
    return null;
  }

  void selectDevice(String id) {
    _selectedDeviceId = id;
    notifyListeners();
  }

  Future<ActionResult> renameDevice(String id, String name) => _guard(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const TuyaException('name', '设备名称不能为空');
    await _repository.renameDevice(id, trimmed);
    _replaceDevice(id, (device) => device.copyWith(name: trimmed));
    // 后端也要跟着改，否则管理后台看到的还是绑定时那个名字。改名在涂鸦那边
    // 已经生效了，这一步失败只降级成一句提示，不把整次改名判成失败。
    if (_backendReady) {
      final backendDevice = _backendDevices[id];
      if (backendDevice != null) {
        try {
          await _backend.editUserProduct(
            userProductId: backendDevice.userProductId,
            productName: trimmed,
            productId: backendDevice.productId,
          );
        } on ApiException catch (error) {
          return ActionResult(
            true,
            '设备名称已更新；后台同步待重试：${error.message}',
            code: 'backend_device_rename_pending',
          );
        }
      }
    }
    return const ActionResult(true, '设备名称已更新');
  });

  /// 拉后台配置的植物列表（`Client/Product/getProductPlantList`）。这是「登录 →
  /// 配网 → 给设备加植物」这条主流程上唯一的后端调用；缺失或失败不回落到演示目录。
  Future<List<PlantProfile>> loadPlantCatalog({String keyword = ''}) async {
    if (!_backend.hasSession) {
      throw const ApiException(
        'BACKEND_SESSION_REQUIRED',
        'APP 后端登录状态已失效，请重新登录',
      );
    }
    final plants = await _backend.getProductPlants(keyword: keyword);
    _rememberPlants(plants);
    return plants;
  }

  /// 把植物写进设备（DP 116）。
  ///
  /// 设备侧是权威：植物品种本来就是涂鸦的功能点，选完就写 DP，不再往后端存一份
  /// 存档（那条链路要先建 userProduct 记录，只会挡住主流程）。
  Future<ActionResult> selectPlant(String id, PlantProfile plant) =>
      _guard(() async {
        final identifier = plant.tuyaIdentifier.trim();
        if (identifier.isEmpty) {
          throw const ApiException(
            'PLANT_IDENTIFIER_MISSING',
            '该植物尚未配置涂鸦标识 ID，请先在后台植物管理中补充（与固件植物 ID 一致）',
          );
        }
        final withType = await _publishPlantSelection(
          id,
          identifier,
          plant.plantType,
        );
        _setPlantSelection(id, plant);
        return ActionResult(
          true,
          withType
              ? '已选择${plant.name}并同步到设备'
              : '已选择${plant.name}并同步到设备；该植物在后台没有配置分类（categoryType），未下发 161',
        );
      });

  /// 引导窗里的「确认」：把设备当前上报的植物 DPID 原样回写。
  ///
  /// 固件收到 116 之后会把 162 改成 0 并立即上报，弹窗就不会再来；App 这里不猜
  /// 植物，写回去的就是设备刚报上来的那个 id。能在目录里解析出这一株时顺带下发
  /// 分类（161），和主动选植物保持一致。
  Future<ActionResult> confirmDetectedPlant(String id) => _guard(() async {
    final device = deviceById(id);
    final reported = device?.plantVariety.trim() ?? '';
    if (reported.isEmpty || PlantVariety.isMissing(reported)) {
      throw const TuyaException('plant_missing', '设备当前没有上报植物，无法确认');
    }
    final plant = _plantForIdentifier(reported);
    final withType = await _publishPlantSelection(
      id,
      reported,
      plant?.plantType,
    );
    if (plant != null) _setPlantSelection(id, plant);
    return ActionResult(
      true,
      withType || plant == null
          ? '已确认当前植物'
          : '已确认当前植物；该植物在后台没有配置分类（categoryType），未下发 161',
    );
  });

  /// 按 DP 116 的标识符补齐这台设备的植物静态内容（图片、别名、引导文案、环境
  /// 需求），详情页进来时调用。
  ///
  /// 走的仍然是主流程唯一那个后端调用 `getProductPlantList`；标识符已经在目录缓存
  /// 里时不再打接口。拉不到就保留已获取的真实资料或空态，不打断详情页——光照、需水那些 DP
  /// 业务数据来自设备上报，与这次请求无关。
  Future<void> ensurePlantProfile(String deviceId) async {
    final identifier = deviceById(deviceId)?.plantVariety.trim() ?? '';
    // -1 是「盆里没有植物」，不是一个查不到的标识符，不用去后端找。
    if (identifier.isEmpty || PlantVariety.isMissing(identifier)) return;
    final normalized = _plantKey(identifier);
    // 拉过一次目录仍然对不上的标识符不再反复拉：设备每次上报都会走到这里。
    if (_unresolvedPlantIdentifiers.contains(normalized)) return;
    final cached = _knownPlantsByIdentifier.containsKey(normalized);
    if (_backend.enabled && !cached) {
      try {
        await loadPlantCatalog();
      } catch (_) {
        // 后端不可用时保留本地目录兜底，详情页照常显示设备上报的数据。
        return;
      }
    }
    final plant = _plantForIdentifier(identifier);
    if (plant == null) {
      _unresolvedPlantIdentifiers.add(normalized);
      return;
    }
    final device = deviceById(deviceId);
    if (device != null &&
        device.plant.id == plant.id &&
        _plantedDevices.contains(deviceId)) {
      return;
    }
    _setPlantSelection(deviceId, plant);
  }

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
        // 'led' 走的是同一个功能点（117），本地状态也要跟着走同一个字段。
        'autoBrightness' || 'led' => current.copyWith(
          autoBrightness: value as bool,
        ),
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
        'standby' => current.copyWith(standbyEnabled: value as bool),
        'standbyDelay' => current.copyWith(
          standbyDelayMinutes: (value as num)
              .round()
              .clamp(TuyaConfig.standbyDelayMin, TuyaConfig.standbyDelayMax),
        ),
        'deviceLanguage' => current.copyWith(deviceLanguage: value as String),
        'plantDetection' => current.copyWith(plantDetection: value as bool),
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

  /// The 纪念日 page's rows: the two fixed dates the device keeps on their own
  /// DPs, then the custom entries.
  ///
  /// The custom list lives here rather than on the device: DP 154 is an upsert
  /// channel, not a query — the device never reports the set back — so the app
  /// is the only place that knows which ids exist and what the user called
  /// them. Losing this list would leave orphaned entries on the device that
  /// nothing can name or delete, so it is persisted with the session.
  List<MemorialEntry> memorialsFor(String deviceId) {
    final device = deviceById(deviceId);
    final custom = _memorials[deviceId] ?? const <MemorialEntry>[];
    return List<MemorialEntry>.unmodifiable(<MemorialEntry>[
      MemorialEntry(
        id: 0,
        date: device?.birthday,
        type: MemorialContentType.text,
        content: '',
        enabled: device?.birthday != null,
        title: MemorialKind.birthday.label,
        kind: MemorialKind.birthday,
      ),
      MemorialEntry(
        id: 0,
        date: device?.weddingDay,
        type: MemorialContentType.text,
        content: '',
        enabled: device?.weddingDay != null,
        title: MemorialKind.wedding.label,
        kind: MemorialKind.wedding,
      ),
      ...custom,
    ]);
  }

  /// Custom entries only, which is what the 「5/10 条」 counter counts.
  List<MemorialEntry> customMemorialsFor(String deviceId) =>
      List<MemorialEntry>.unmodifiable(
        _memorials[deviceId] ?? const <MemorialEntry>[],
      );

  /// Writes one memorial day: 158/159 for the fixed pair, a 154 upsert frame
  /// for everything else.
  Future<ActionResult> saveMemorial(String deviceId, MemorialEntry entry) =>
      _guard(() async {
        if (entry.isFixed) {
          await _publishFixedMemorial(deviceId, entry);
          _replaceDevice(deviceId, (device) {
            final date = entry.enabled ? entry.date : null;
            return entry.kind == MemorialKind.birthday
                ? device.copyWith(birthday: date, clearBirthday: date == null)
                : device.copyWith(
                    weddingDay: date,
                    clearWeddingDay: date == null,
                  );
          });
          return ActionResult(true, '${entry.title}已保存');
        }
        final date = entry.date;
        if (date == null && entry.enabled) {
          throw const TuyaException('memorial_date_missing', '请先选择纪念日日期');
        }
        final entries = _memorials.putIfAbsent(
          deviceId,
          () => <MemorialEntry>[],
        );
        final index = entries.indexWhere((item) => item.id == entry.id);
        if (index < 0 && entries.length >= TuyaMemorialCodec.maxCustomEntries) {
          throw TuyaException(
            'memorial_limit_reached',
            '自定义纪念日最多 ${TuyaMemorialCodec.maxCustomEntries} 条',
          );
        }
        // 先写后端：帧里的 id 用的就是后端分配的 anniversaryId，新增时得先拿到
        // 它才写得了 DP。图片内容也在这一步上传换成 URL。
        final saved = _backendReady
            ? await _saveMemorialOnBackend(deviceId, entry, isNew: index < 0)
            : entry;
        await _publishMemorialFrame(
          deviceId,
          TuyaMemorialCodec.encodeEntry(
            id: saved.id,
            // 停用帧不带日期，但本地要留着，用户重新开启时不用再选一次。
            date: saved.date ?? DateTime.now(),
            type: saved.type,
            content: saved.content,
            enabled: saved.enabled,
          ),
        );
        if (index >= 0) {
          entries[index] = saved;
        } else {
          entries.add(saved);
        }
        await _persistMemorials();
        notifyListeners();
        return const ActionResult(true, '纪念日已保存');
      });

  /// Removes a custom entry from the device and from the local list. The fixed
  /// pair cannot be deleted — disabling it is what the UI offers instead.
  Future<ActionResult> deleteMemorial(String deviceId, int id) =>
      _guard(() async {
        // 设备先删、后端后删：删帧是幂等的，后端这步失败时条目还在列表里，用户
        // 再点一次就能补上；反过来后端先删的话，失败重试要面对一条列表里已经
        // 没有、设备上还在显示的孤儿记录。
        await _publishMemorialFrame(
          deviceId,
          TuyaMemorialCodec.encodeDelete(id),
        );
        if (_backendReady) {
          await _backend.deleteAnniversary(id);
        }
        _memorials[deviceId]?.removeWhere((item) => item.id == id);
        await _persistMemorials();
        notifyListeners();
        return const ActionResult(true, '纪念日已删除');
      });

  /// APP 后端此刻是否可用。没配后端（纯涂鸦链路）或会话已经失效
  /// 时，纪念日、设备改名这些会退回接后端之前的行为，而不是直接报错。
  bool get _backendReady => _backend.enabled && _backend.hasSession;

  /// 拉一次这台设备的纪念日列表。纪念日页进来时调用。
  ///
  /// 接上后端之前这份清单只存在 [SharedPreferences] 里，换台手机就全丢、设备上
  /// 会留下没人能命名和删除的孤儿条目；现在本地那份退化成缓存。
  Future<void> refreshMemorials(String deviceId) async {
    if (!_backendReady) return;
    try {
      final backendDevice = await _ensureBackendDevice(deviceId);
      final rows = await _backend.getAnniversaries(backendDevice.userProductId);
      _memorials[deviceId] = rows
          .map(_memorialFromBackend)
          .toList(growable: true);
      await _persistMemorials();
      notifyListeners();
    } catch (_) {
      // 拉不到就继续显示本地缓存那份，不把页面变成错误页。
    }
  }

  /// 把一条自定义纪念日写进后端，返回换上后端 id、图片换成 URL 之后的条目。
  Future<MemorialEntry> _saveMemorialOnBackend(
    String deviceId,
    MemorialEntry entry, {
    required bool isNew,
  }) async {
    final backendDevice = await _ensureBackendDevice(deviceId);
    var content = entry.content.trim();
    if (entry.type == MemorialContentType.image &&
        content.isNotEmpty &&
        !_isRemoteUrl(content)) {
      content = await _backend.uploadFile(content);
    }
    final imageContent = entry.type == MemorialContentType.image;
    final date = entry.date ?? DateTime.now();
    final id = isNew
        ? await _backend.addAnniversary(
            userProductId: backendDevice.userProductId,
            title: entry.title,
            content: content,
            imageContent: imageContent,
            date: date,
          )
        : entry.id;
    if (!isNew) {
      await _backend.editAnniversary(
        anniversaryId: id,
        userProductId: backendDevice.userProductId,
        title: entry.title,
        content: content,
        imageContent: imageContent,
        date: date,
      );
    }
    // 启用/停用是后端单独的一个接口，新增和编辑的入参里没有这个字段。
    await _backend.setAnniversaryEnabled(<int>[id], entry.enabled);
    return entry.copyWith(id: id, content: content);
  }

  static MemorialEntry _memorialFromBackend(BackendAnniversary row) =>
      MemorialEntry(
        id: row.anniversaryId,
        date: row.date,
        type: row.imageContent
            ? MemorialContentType.image
            : MemorialContentType.text,
        content: row.content,
        enabled: row.enabled,
        title: row.title,
      );

  static bool _isRemoteUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  /// An id for a new entry. Milliseconds are unique enough for a per-device
  /// list of at most ten, and stay inside the frame's unsigned 32 bits.
  int nextMemorialId(String deviceId) {
    final used = (_memorials[deviceId] ?? const <MemorialEntry>[])
        .map((item) => item.id)
        .toSet();
    var id = DateTime.now().millisecondsSinceEpoch % 0xFFFFFFFF;
    while (used.contains(id) || id == 0) {
      id = (id + 1) % 0xFFFFFFFF;
    }
    return id;
  }

  /// `del_photo` (155): removes one file from the device gallery by name.
  Future<ActionResult> deleteDevicePhoto(String deviceId, String fileName) =>
      _guard(() async {
        await _publishRawDp(deviceId, 'del_photo', ascii.encode(fileName));
        return ActionResult(true, '已通知设备删除 $fileName');
      });

  /// `del_all_photos` (156).
  Future<ActionResult> deleteAllDevicePhotos(String deviceId) =>
      _guard(() async {
        final dpId = TuyaConfig.dp['del_all_photos'];
        if (dpId == null) {
          throw const TuyaException('unsupported_dp', '当前产品未提供清空照片功能点');
        }
        await _repository.publishDps(deviceId, <int, Object>{dpId: true});
        return const ActionResult(true, '已通知设备清空照片');
      });

  /// `pin_photo` (157): the device shows this file first.
  Future<ActionResult> pinDevicePhoto(String deviceId, String fileName) =>
      _guard(() async {
        await _publishRawDp(deviceId, 'pin_photo', ascii.encode(fileName));
        return ActionResult(true, '已置顶 $fileName');
      });

  Future<void> _publishFixedMemorial(
    String deviceId,
    MemorialEntry entry,
  ) async {
    final identifier = entry.kind == MemorialKind.birthday
        ? 'memorial_birthday'
        : 'memorial_wedding';
    await _publishRawDp(
      deviceId,
      identifier,
      TuyaMemorialCodec.encodeFixedDate(entry.enabled ? entry.date : null),
    );
  }

  Future<void> _publishMemorialFrame(String deviceId, List<int> frame) =>
      _publishRawDp(deviceId, 'memorial_set', frame);

  Future<void> _publishRawDp(
    String deviceId,
    String identifier,
    List<int> bytes,
  ) async {
    final dpId = TuyaConfig.dp[identifier];
    if (dpId == null) {
      throw TuyaException('unsupported_dp', '当前产品未提供该功能点：$identifier');
    }
    await _repository.publishDps(deviceId, <int, Object>{
      dpId: TuyaMemorialCodec.encodeRaw(bytes),
    });
  }

  Future<ActionResult> addAnimation(
    String deviceId, {
    required String name,
    required String path,
  }) => _guard(() async {
    if (_backend.enabled) {
      _requireBackendSession();
      await _backend.uploadImage(deviceId: deviceId, filePath: path);
      await _refreshBackendImages(deviceId);
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
    await _refreshBackendImages(deviceId);
  }

  Future<ActionResult> createShareLink(String id) => _guard(() async {
    final link = await _repository.createShareLink(id);
    return ActionResult(true, link);
  });

  /// 问云端有没有待升级的固件，没有时返回 null。
  ///
  /// OTA 不是功能点：2026-09-03 的表里只有 148 `firmware_version` 和 149
  /// `hardware_version` 两个只读版本号，升级本身走涂鸦 SDK 的 OTA 接口
  /// （Android `newOTAInstance`/`getOtaInfo`/`startOta`，iOS
  /// `getFirmwareUpgradeInfo`/`upgradeFirmware`），由原生桥接封装。App 自始至
  /// 终不和设备直接说话：问版本、发起升级、收进度，三步都是对着 SDK。
  Future<FirmwareUpdate?> checkFirmware(String id) async {
    final update = await _repository.checkFirmware(id);
    _rememberFirmwareUpdate(id, update);
    return update;
  }

  /// 静默查一次新版本，只为了让小红点亮起来。
  ///
  /// 页面一打开就跑，所以失败必须无声：设备离线、涂鸦后台没开通 OTA 能力、网络
  /// 不通都会让 `getOtaInfo` 报错，但用户此刻并没有要求检查固件，弹一个红色
  /// toast 只会像是页面自己坏了。真正需要交代结果的是用户点「固件版本更新」
  /// 那一次，那条路径仍然照常报错。
  Future<void> refreshFirmwareUpdate(String id) async {
    try {
      await checkFirmware(id);
    } catch (_) {
      // 查不到就当作「这次没查到新版本」，保留上一次的结论。
    }
  }

  /// 这台设备有没有待装的新固件（小红点）。
  bool hasFirmwareUpdate(String deviceId) =>
      _availableFirmware.containsKey(deviceId);

  /// 待装的新固件，没有新版本时为 null。
  FirmwareUpdate? availableFirmwareFor(String deviceId) =>
      _availableFirmware[deviceId];

  /// 记下（或抹掉）一台设备的待升级固件。
  ///
  /// 涂鸦在设备已是最新时可能回 null、空串，也可能把当前版本原样回来，三种都
  /// 是「没有新版本」；只有确实不同的版本号才点亮小红点。比较的基准优先用同一
  /// 条 OTA 记录里的当前版本，取不到才退回设备列表里的固件版本。
  void _rememberFirmwareUpdate(String id, FirmwareUpdate? update) {
    final current =
        update?.currentVersion ?? deviceById(id)?.firmwareVersion;
    final version = update?.version ?? '';
    final next = version.isEmpty || version == current ? null : update;
    if (next == null) {
      if (_availableFirmware.remove(id) == null) return;
    } else {
      if (_availableFirmware[id]?.version == next.version) return;
      _availableFirmware[id] = next;
    }
    notifyListeners();
  }

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
      _otaUpdatedAt[id] = DateTime.now();
      return const ActionResult(true, '升级已开始，请保持设备通电并留在网络中');
    },
  );

  /// 某台设备最近一次的升级进度，没有发起过升级时为 null。
  OtaProgress? otaProgressFor(String deviceId) => _otaProgress[deviceId];

  /// 多久没有新的进度事件就认为这次升级已经断了。
  ///
  /// 涂鸦不保证一定回终态：设备掉电、掉线或固件包校验失败时，`onProgress`
  /// 之后可能什么都不再来。没有这条判断的话，界面会永远停在「升级中 42%」，
  /// 用户既看不出出了问题，也没法重试——只能杀掉 App。
  static const Duration otaStallTimeout = Duration(minutes: 10);

  /// 这台设备的升级是不是卡住了（仍处于 running，但已经 [otaStallTimeout]
  /// 没有任何事件）。
  bool otaStalled(String deviceId) {
    if (_otaProgress[deviceId]?.status != OtaStatus.running) return false;
    final at = _otaUpdatedAt[deviceId];
    if (at == null) return false;
    return DateTime.now().difference(at) > otaStallTimeout;
  }

  /// 丢掉本地记着的升级状态，让界面回到「可以重新检查」。
  ///
  /// 只动 App 这边：设备那头是不是真的还在升级，只有它自己知道。
  void clearOtaProgress(String deviceId) {
    if (_otaProgress.remove(deviceId) == null) return;
    _otaUpdatedAt.remove(deviceId);
    _pendingOtaVersion.remove(deviceId);
    notifyListeners();
  }

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

  /// 下发植物：116 植物品种和 161 植物分类走同一条指令。
  ///
  /// 设备靠这两条一起确定养护策略，分开发会让设备短暂拿到「新品种 + 旧分类」。
  /// 后台没给分类（或给了 1–3 之外的值）时只发 116，并把这件事回给调用方，由
  /// 页面提示，而不是猜一个分类填进去。
  ///
  /// 返回值：161 是否一起发出去了。
  Future<bool> _publishPlantSelection(
    String id,
    String identifier,
    int? category,
  ) async {
    final varietyDp = TuyaConfig.dp['plant_variety'];
    if (varietyDp == null) {
      throw const TuyaException('unsupported_dp', '当前产品未提供植物品种功能点');
    }
    final dps = <int, Object>{varietyDp: identifier};
    final typeDp = TuyaConfig.dp['plant_type'];
    final typeValue = TuyaConfig.plantTypeValue(category);
    if (typeDp != null && typeValue != null) dps[typeDp] = typeValue;
    await _repository.publishDps(id, dps);
    return dps.length > 1;
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
    // 相册里挑出来的是本地路径，先传上去换成 URL：本地路径换台手机就没了，
    // 后端和其它端也读不到。
    var resolvedAvatar = avatarUrl?.trim();
    if (_backend.enabled && _backend.hasSession) {
      if (resolvedAvatar != null &&
          resolvedAvatar.isNotEmpty &&
          !_isRemoteUrl(resolvedAvatar)) {
        resolvedAvatar = await _backend.uploadFile(resolvedAvatar);
      }
      if (value != _user?.nickname) {
        await _backend.changeNickname(value);
      }
      if (resolvedAvatar != null &&
          resolvedAvatar.isNotEmpty &&
          resolvedAvatar != _user?.avatarUrl) {
        await _backend.changeAvatar(resolvedAvatar);
      }
    }
    await _repository.updateNickname(value);
    _user = _user?.copyWith(nickname: value, avatarUrl: resolvedAvatar);
    return const ActionResult(true, '基本信息已保存');
  });

  /// 用后端的资料覆盖登录时缓存的昵称和头像。
  ///
  /// 登录接口只回了建号时那份，用户在别的端改过之后这边不会自己更新，所以每次
  /// 会话刷新和进个人信息页都重新拉一次。
  Future<void> refreshUserInfo({bool notify = true}) async {
    final epoch = _sessionEpoch;
    final current = _user;
    if (!_backend.enabled || !_backend.hasSession || current == null) return;
    try {
      final info = await _backend.getUserInfo();
      if (epoch != _sessionEpoch || !identical(_user, current)) return;
      _user = AppUser(
        id: current.id,
        nickname: info.nickname.isEmpty ? current.nickname : info.nickname,
        account: info.account.isEmpty ? current.account : info.account,
        avatarUrl: info.avatarUrl ?? current.avatarUrl,
      );
      if (notify) notifyListeners();
    } catch (_) {
      // 资料拉不到不影响主流程，继续用登录时那份。
    }
  }

  /// 给当前登录用户发一条短信验证码（改密码、改绑手机用），不用再传手机号。
  Future<ActionResult> sendCurrentUserCode() => _guard(() async {
    if (!_backendReady) {
      throw const ApiException(
        'BACKEND_SESSION_REQUIRED',
        'APP 后端登录状态已失效，请重新登录',
      );
    }
    await _backend.sendSmsToCurrentUser();
    return const ActionResult(true, '验证码已发送');
  });

  /// 已登录状态下修改登录密码。
  ///
  /// 后端 `/Client/User/changePassword` 校验的是短信验证码，入参里根本没有
  /// 「原密码」；而 `docs/UI/修改密码.png` 画的是原密码 + 新密码 + 确认密码。
  /// 两边对不上，所以修改密码页现在还没接上这条链路——页面加一个验证码输入
  /// （配 [sendCurrentUserCode]），或者后端补一个按原密码改的接口，二选一之后
  /// 直接调这里就行。
  Future<ActionResult> changeLoginPassword({
    required String verifyCode,
    required String newPassword,
  }) => _guard(() async {
    if (!_backendReady) {
      throw const ApiException(
        'BACKEND_SESSION_REQUIRED',
        'APP 后端登录状态已失效，请重新登录',
      );
    }
    await _backend.changePassword(
      verifyCode: AuthValidator.code(verifyCode),
      password: AuthValidator.password(newPassword, minimumLength: 6),
    );
    return const ActionResult(true, '密码已更新，请使用新密码登录');
  });

  /// 后端给出的最新版本，null = 还没查过或后端没开。
  BackendAppVersion? _appVersion;
  BackendAppVersion? get appVersion => _appVersion;

  /// 后端说有新版本：「我的 → 关于YSplanter」那一行点红点用它。
  bool get hasAppUpdate => _appVersion?.hasUpdate ?? false;

  /// 有新版本且是强制升级（`compulsory == 1`）：App 一打开就要弹不可取消的弹窗。
  bool get mustUpdateApp => hasAppUpdate && (_appVersion?.forceUpdate ?? false);

  /// 查一次 App 版本更新状态。[currentVersion] 传本机版本号，例如 `1.0.0`。
  Future<BackendAppVersion?> checkAppVersion(String currentVersion) async {
    if (!_backend.enabled || !_backend.hasSession) return null;
    try {
      _appVersion = await _backend.getLastVersion(currentVersion);
      notifyListeners();
    } catch (_) {
      // 查不到按「已是最新」处理，关于页照常可用。
    }
    return _appVersion;
  }

  /// 后台配的基础数据（用户协议、隐私政策、关于我们等），只拉一次。
  BackendBasicData _basicData = BackendBasicData.empty;
  BackendBasicData get basicData => _basicData;

  Future<BackendBasicData> loadBasicData() async {
    if (!_backend.enabled || !_backend.hasSession) return _basicData;
    if (!_basicData.isEmpty) return _basicData;
    try {
      _basicData = await _backend.getBasicData();
      notifyListeners();
    } catch (_) {
      // 后台没配就用 App 内置的那份文案。
    }
    return _basicData;
  }

  /// 帮助中心的常见问题。拉不到返回空，页面回落到内置的几条。
  Future<List<BackendFaq>> loadFaqs() async {
    if (!_backend.enabled || !_backend.hasSession) return const <BackendFaq>[];
    try {
      return await _backend.getFaqs();
    } catch (_) {
      return const <BackendFaq>[];
    }
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    _backend.setLanguage(code);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('languageCode', code);
  }

  /// Storage key for [_memorials].
  static const String _memorialsKey = 'deviceMemorials';

  Future<void> _persistMemorials() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _memorialsKey,
        jsonEncode(<String, Object?>{
          for (final entry in _memorials.entries)
            entry.key: <Object?>[
              for (final item in entry.value)
                <String, Object?>{
                  'id': item.id,
                  'date': item.date == null
                      ? null
                      : TuyaMemorialCodec.dateValue(item.date!),
                  'type': item.type.code,
                  'content': item.content,
                  'enabled': item.enabled,
                  'title': item.title,
                },
            ],
        }),
      );
    } catch (_) {
      // 存不下来不该让这次保存失败：设备那边已经写进去了。
    }
  }

  void _restoreMemorials(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return;
      decoded.forEach((deviceId, value) {
        if (value is! List<Object?>) return;
        _memorials[deviceId] = <MemorialEntry>[
          for (final item in value)
            if (item is Map<String, Object?>)
              MemorialEntry(
                id: (item['id'] as num?)?.toInt() ?? 0,
                date: item['date'] == null
                    ? null
                    : TuyaMemorialCodec.dateFromValue(
                        (item['date'] as num).toInt(),
                      ),
                type: MemorialContentType.fromCode(
                  (item['type'] as num?)?.toInt() ?? 1,
                ),
                content: (item['content'] ?? '').toString(),
                enabled: item['enabled'] as bool? ?? true,
                title: (item['title'] ?? '').toString(),
              ),
        ];
      });
    } catch (_) {
      // 存档格式变了或者被写坏了，按「本机还没有记录」处理。
    }
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
    _otaUpdatedAt[progress.deviceId] = DateTime.now();
    if (progress.status == OtaStatus.success) {
      // 装上了就不再是「待装」，小红点跟着灭掉。
      _availableFirmware.remove(progress.deviceId);
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
    // 116 报 -1 = 植物被拔走了。`SmartPlanterDevice.plant` 是非空字段（详情页
    // 各处都直接读它），所以这里不动那个对象，只把本地的「这台设备有植物」缓存
    // 清掉——界面一律以 `plantMissing()` / `hasPlant()` 判断，读的是 116 本身。
    if (PlantVariety.isMissing(device.plantVariety)) {
      _plantOverrides.remove(device.id);
      _plantedDevices.remove(device.id);
      _devices[index] = device;
      notifyListeners();
      return;
    }
    final reportedPlant = _plantForIdentifier(device.plantVariety);
    if (reportedPlant != null) {
      _plantOverrides[device.id] = reportedPlant;
      _plantedDevices.add(device.id);
    }
    _devices[index] = device.copyWith(
      plant: reportedPlant ?? _plantOverrides[device.id],
    );
    notifyListeners();
    // 设备换到了一株 App 目录里还没有的植物——用户在引导窗里点「确认」、或者换了
    // NFC 芯片之后设备重新上报 116 就是这条路径。补拉一次目录再解析，成功了由
    // ensurePlantProfile 自己刷新界面。必须放在上面这次替换之后：它读的是设备
    // 当前的 116。
    if (reportedPlant == null && device.plantVariety.trim().isNotEmpty) {
      unawaited(ensurePlantProfile(device.id));
    }
  }

  @override
  void dispose() {
    _sessionEpoch++;
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

  /// **给排查用的**来源标签，形如 `接口-406 ...` / `涂鸦-1006 ...` / `APP-busy ...`：
  ///
  /// - `接口-<code>`：APP 后端 REST 返回的失败（`retCode` 或 HTTP 状态码）；
  /// - `涂鸦-<code>`：涂鸦 SDK 原生层返回的失败，与 APP 后端无关；
  /// - `APP-<code>`：APP 自己产生的失败（本地校验、网络层、未预期异常）。
  ///
  /// 涂鸦单列而不并进「接口」：两者是不同的服务，混成一类会把涂鸦拒绝的登录
  /// 指向 APP 后端，排查方向正好反了。
  ///
  /// ⚠️ **只用在诊断行上，不进 toast**（2026-09-10 产品要求：toast 直接给内容）。
  /// 用户看到「接口-406」帮不上任何忙，而排查需要的来源信息仍然在
  /// `ActionResult.code` 里，以及设备列表页底部那行 `sessionDiagnostics`。
  static String _diagnostic(String source, Object code, String message) =>
      '$source-$code $message';

  /// 后端的 `retCode` 与 HTTP 状态码都是数字；APP 网络层自己抛的是
  /// `NETWORK_TIMEOUT` 这类大写字符串常量，据此区分 [ApiException] 的来源。
  static String _apiSource(Object code) => code is int ? '接口' : 'APP';

  Future<ActionResult> _guard(Future<ActionResult> Function() action) async {
    if (_busy) {
      return const ActionResult(false, '请等待当前操作完成', code: 'busy');
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

  /// 异常收口，不占用 [_busy]。
  ///
  Future<ActionResult> _run(Future<ActionResult> Function() action) async {
    final epoch = _sessionEpoch;
    try {
      return await action();
    } on AuthValidationException catch (error) {
      return ActionResult(
        false,
        error.message,
        code: 'invalid_input',
      );
    } on TuyaException catch (error) {
      return ActionResult(
        false,
        error.message,
        code: error.code,
      );
    } on ApiException catch (error) {
      if (error.isAuthError && epoch == _sessionEpoch) {
        _handleBackendSessionExpired(error);
      }
      return ActionResult(
        false,
        error.message,
        code: error.code.toString(),
      );
    } catch (error) {
      return ActionResult(
        false,
        '操作失败：$error',
        code: 'unexpected_error',
      );
    }
  }

  /// APP 后端会话失效（401 / 406）时的处置。
  ///
  /// **只清后端会话，不动涂鸦会话和设备列表。** 设备清单、DP 上报、配网、固件
  /// 全部走涂鸦，和 APP 后端的 token 没有任何关系；以前这里直接 `_clearLocalSession()`，
  /// 一次 406 就把用户整个踢回登录页——表现就是「用一会儿（后端 token 的有效期）
  /// 就掉登录」，而后端查自己的表又说 token 还在。真正需要后端的功能（图库、
  /// 植物目录、意见反馈）会各自报「APP 后端登录状态已失效，请重新登录」。
  void _handleBackendSessionExpired(ApiException error) {
    _backend.clearSession();
    _backendSessionError = _diagnostic(
      _apiSource(error.code),
      error.code,
      error.message,
    );
    debugPrint('[session] $_backendSessionError');
    notifyListeners();
  }

  /// 一次会话开始：换代、把上次记下的家庭钉给原生，再拉设备列表。
  ///
  /// 顺序不能反——家庭没钉住就拉列表，等于又让原生自己从家庭列表里挑一次。
  Future<void> _startSession() async {
    _sessionEpoch++;
    await _restoreBackendUserId();
    await _applyHomeTag();
    await _pinKnownHome();
    await _refreshDevicesForSession(ignoreErrors: true);
  }

  static String _homeKey(String key) => 'tuyaHome:$key';

  static String _accountKeyStore(String uid) => 'backendUserId:$uid';

  /// 本次会话已知的后端 `userId`，登录时拿到，会话恢复时从本地读回。
  String? _backendUserId;

  /// 家庭归属用的账号键：优先后端 `userId`，取不到退回涂鸦 uid（即 `userNo`）。
  ///
  /// 家庭 id 只能由涂鸦分配，这个键不是 id，而是"哪个家庭属于哪个账号"的依据：
  /// 家庭名标记和本地缓存都按它来。两者都跟账号走、不跟手机走，所以换手机登录
  /// 同一个账号，认到的仍是同一个家庭。
  String get _accountKey {
    final backendId = _backendUserId?.trim() ?? '';
    if (backendId.isNotEmpty) return backendId;
    return _user?.id ?? '';
  }

  /// 登录时拿到后端 `userId` 就记下来（按涂鸦 uid 存），下次会话恢复时接得上。
  Future<void> _rememberBackendUserId(String? userId) async {
    final id = userId?.trim() ?? '';
    final uid = _user?.id ?? '';
    if (id.isEmpty) return;
    _backendUserId = id;
    if (uid.isEmpty) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_accountKeyStore(uid), id);
    } catch (_) {
      // 记不住只是下次退回用涂鸦 uid 当键，家庭仍然稳定，只是键换了一次。
    }
  }

  Future<void> _restoreBackendUserId() async {
    if (_backendUserId != null) return;
    final uid = _user?.id ?? '';
    if (uid.isEmpty) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _backendUserId = preferences.getString(_accountKeyStore(uid));
    } catch (_) {
      // 读不到就用涂鸦 uid。
    }
  }

  /// 家庭名标记：`YS-<账号键>`，账号键优先用后端 `userId`，没有则用涂鸦 uid
  /// （即后端下发的 `userNo`）。
  ///
  /// 家庭 id 只能由涂鸦分配，这两个值都当不了 id（涂鸦查不到这个家庭，还可能撞上
  /// 别人的）；但家庭**名字**是我们能定的，所以用它承载「这个家庭属于哪个账号」
  /// 这件事：建家时用这个名字，认领时优先认名字。
  static String homeTagFor(String accountKey) => 'YS-$accountKey';

  Future<void> _applyHomeTag() async {
    final key = _accountKey;
    if (key.isEmpty) return;
    try {
      await _repository.useHomeTag(homeTagFor(key));
    } catch (_) {
      // 桥接不支持就退回原来的挑选规则。
    }
  }

  /// 把上次记下的家庭固定给原生。
  ///
  /// 家庭是涂鸦账号下的东西，既不依赖设备也不依赖 APP 后端：账号没变就该一直用
  /// 同一个家庭。每次登录都重新从 `queryHomeList` 里挑，是「重新登录后读不到已
  /// 绑定设备」的根源之一（列表顺序不保证一致，账号里又可能有第二个空家庭），
  /// 所以第一次解析到之后就按账号记在本地，之后每次会话开始先钉回去。
  Future<void> _pinKnownHome() async {
    // 后端刚在登录响应里给过家庭，那份优先，不要被本地缓存覆盖。
    if (_pinnedHome != null) return;
    final key = _accountKey;
    if (key.isEmpty) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(_homeKey(key)) ?? '';
      if (stored.isEmpty) return;
      await _repository.useHome(stored);
      _pinnedHome = stored;
      _lastHomeId = stored;
    } catch (_) {
      // 本地存储或桥接不支持时按「没有固定家庭」处理，退回原生自己解析。
    }
  }

  /// 后端在登录响应里带回来的家庭 id（`tuYaHomeId`）。
  ///
  /// 这一份最权威：家庭 id 是涂鸦云端分配的，后端按账号存一份，换手机、重装、
  /// 清数据之后仍然能用同一个家庭——本地缓存做不到。拿到就立刻钉给涂鸦，同时写
  /// 进本地缓存，之后即使某次登录后端没带也接得上。后端还没下发时什么都不做，
  /// 退回本地缓存 + 涂鸦家庭列表解析。
  Future<void> _applyBackendHome(String? homeId) async {
    final id = homeId?.trim() ?? '';
    if (id.isEmpty || id == '0') return;
    try {
      await _repository.useHome(id);
      _pinnedHome = id;
      _lastHomeId = id;
      await _rememberHome(id);
    } catch (_) {
      // 桥接不支持就退回本地缓存那条路。
    }
  }

  /// 丢掉本地钉住的家庭，让原生按涂鸦返回的列表重新解析一次。
  ///
  /// **涂鸦给的永远是准的**，本地这份只是让「每次登录选到同一个家庭」这件事稳定
  /// 下来的缓存。缓存一旦指向一个读不出设备的家庭（用户在涂鸦 App 里删了它、
  /// 换了账号、或者当初就记错了），必须立刻作废，不能让它把人锁死在 0 台上。
  Future<void> _dropPinnedHome() async {
    final key = _accountKey;
    _pinnedHome = null;
    try {
      await _repository.useHome('');
      if (key.isNotEmpty) {
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove(_homeKey(key));
      }
    } catch (_) {
      // 清不掉也不要紧：下一次成功读到设备时会用新的家庭覆盖掉。
    }
  }

  /// 记下这次真正用上的家庭，供下次会话固定使用。
  Future<void> _rememberHome(String homeId) async {
    final key = _accountKey;
    if (key.isEmpty || homeId.isEmpty || homeId == '?' || homeId == '0') return;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (preferences.getString(_homeKey(key)) == homeId) return;
      await preferences.setString(_homeKey(key), homeId);
    } catch (_) {
      // 记不住只是下次要重新解析，不影响这次。
    }
  }

  Future<void> _refreshDevicesForSession({required bool ignoreErrors}) async {
    final epoch = _sessionEpoch;
    try {
      var devices = await _repository.getDevices();
      if (epoch != _sessionEpoch) return;
      // 用缓存的家庭却一台设备都没读到：极可能这个家庭已经不是设备所在的那个
      // （用户在涂鸦 App 里删过家庭、或者当初记错了）。作废缓存，让涂鸦的家庭
      // 列表重新决定一次——以涂鸦返回的为准，本地那份只是缓存。
      if (devices.isEmpty && _pinnedHome != null) {
        await _dropPinnedHome();
        if (epoch != _sessionEpoch) return;
        devices = await _repository.getDevices();
        if (epoch != _sessionEpoch) return;
      }
      _deviceLoadError = null;
      // 设备清单是按家庭查的，把这次用的家庭一起记下来：上面那次 getDevices 已经
      // 把家庭解析并缓存在原生侧，这里只是把它读回来，不会再触发一次云端查询。
      final home = await _repository.currentHomeId().catchError((_) => '?');
      _lastHomeId = home;
      await _rememberHome(home);
      // 设备清单以涂鸦为准。登录后不再顺带拉 getUserInfo / getUserProductList /
      // getUserProductPlantList——主流程只允许 getProductPlantList 一个后端调用。
      _devices = devices.map(_withLocalOverrides).toList();
      if (_devices.isEmpty) {
        _selectedDeviceId = null;
      } else if (_devices.every((item) => item.id != _selectedDeviceId)) {
        _selectedDeviceId = _devices.first.id;
      }
      _logDevices();
      notifyListeners();
    } catch (error) {
      if (epoch != _sessionEpoch) return;
      // 失败不清空已有列表：断网重进时保留上一次拿到的设备，比直接白屏好。
      _deviceLoadError = _deviceLoadMessage(error);
      _logDevices();
      notifyListeners();
      if (!ignoreErrors) rethrow;
    }
  }

  /// 每次读设备列表都留一行日志（`adb logcat -s flutter` / Xcode 控制台可见）。
  /// 用户不再进联调页之后，这是现场唯一能翻到的记录，所以不按 debug 模式过滤。
  void _logDevices() => debugPrint('[devices] $sessionDiagnostics');

  static String _deviceLoadMessage(Object error) => switch (error) {
    TuyaException tuya => _diagnostic('涂鸦', tuya.code, tuya.message),
    ApiException api => _diagnostic(_apiSource(api.code), api.code, api.message),
    _ => _diagnostic('APP', 'device_list_failed', '设备列表读取失败：$error'),
  };

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

  /// 没有后端会话时按「登录失效」报错，图库上传和 [_ensureBackendDevice] 共用
  /// 这一句，避免无 token 的请求打出去再靠 401 兜回来。
  void _requireBackendSession() {
    if (_backend.enabled && _backend.hasSession) return;
    throw const ApiException(
      'BACKEND_SESSION_REQUIRED',
      'APP 后端登录状态已失效，请重新登录',
    );
  }

  Future<BackendUserProduct> _ensureBackendDevice(String deviceId) async {
    _requireBackendSession();
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

  Future<void> _refreshBackendImages(String deviceId) async {
    final images = await _backend.getImages(deviceId);
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
      final identifier = _plantKey(plant.tuyaIdentifier);
      if (identifier.isNotEmpty) _knownPlantsByIdentifier[identifier] = plant;
    }
  }

  /// 植物标识的归一化键。
  ///
  /// 新契约里 DP 116 与后台「涂鸦标识 ID」都是数字，但两边到手时的形态不一定
  /// 一样（设备可能报 `0`、`"0"` 甚至 `0.0`，后台字段是字符串）。能解析成整数就
  /// 一律按整数比，解析不出来才退回小写字符串——老固件报的 `tuYaRemark` 标识符
  /// 走的就是后面这条。
  static String _plantKey(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    final id = PlantVariety.parse(normalized);
    return id == null ? normalized : '$id';
  }

  PlantProfile? _plantForIdentifier(String identifier) {
    final normalized = _plantKey(identifier);
    if (normalized.isEmpty) return null;
    return _knownPlantsByIdentifier[normalized];
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
    _deviceLoadError = null;
    _pinnedHome = null;
    _backendSessionError = null;
    _plantedDevices.clear();
    _plantOverrides.clear();
    _settingsOverrides.clear();
    _backendDevices.clear();
    _backendAnimations.clear();
    _knownPlantsByIdentifier.clear();
    _unresolvedPlantIdentifiers.clear();
    _animations.clear();
    // `_memorials` deliberately survives a logout. It is the only record of
    // which DP 154 ids exist on a device — the device never reports the set
    // back — so dropping it would leave entries on the hardware that nothing
    // can name or delete. It is keyed by device id, which belongs to the
    // planter rather than to the account.
    _selectedDeviceId = null;
    _backendUserId = null;
    // The native token belongs to the account that fetched it.
    _activatorTokenAt = null;
    ImageCacheCleanup.clearAll();
  }

  String _normalizeAccount(String account, LoginRegion region) {
    final normalized = account.trim();
    return AuthValidator.account(normalized, region);
  }
}
