import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/backend/backend.dart';
import 'core/cache/image_cache_cleanup.dart';
import 'core/network/api_exception.dart';
import 'features/auth/domain/auth_validator.dart';
import 'features/devices/pairing_gate.dart';
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

  /// **设备报了多少次「162 = true」**，每收到一条就 +1。
  ///
  /// 详情页靠它决定要不要再弹一次引导窗（2026-09-12 产品：「点了确认以后，再次
  /// 接收到 DP162 true 的时候，页面只要没有弹框了，就需要再次弹框，而不是只弹框
  /// 一次」）。
  ///
  /// ⚠️ **为什么不直接看 [plantGuidePending]**：162 在用户处置之前一直是 true，
  /// 而页面每次 `notifyListeners` 都会重建——按状态触发的话，点任何一个下发按钮都
  /// 会重新冒出这个弹窗（2026-09-12 修过的那个回归）。按「收到上报」触发就两头都
  /// 顾上了：重建不会误触发，设备再报一次就会再弹。
  int plantGuideSignal(String? deviceId) =>
      deviceId == null ? 0 : (_plantGuideSignals[deviceId] ?? 0);

  final Map<String, int> _plantGuideSignals = <String, int>{};

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

  // ════════════════ BLE 发现（双模设备的优化路径） ════════════════
  //
  // **和 Wi-Fi 扫描并行，不替换它。** 两条通道各有各的前提：
  //
  // | | 靠什么发现 | 快不快 | 前提 |
  // | --- | --- | --- | --- |
  // | Wi-Fi | 设备拉起的 AP 热点 | 慢（Android 每 2 分钟只给 4 次 `startScan`） | 设备进了 AP 模式 |
  // | BLE | 设备的 BLE 广播 | 快（不受那条配额约束，通常一两秒） | 设备是双模、手机蓝牙开着 |
  //
  // BLE 扫到之后还有第二步好处：[BleDevice.supportWifiList] 为 true（固件
  // TuyaOS ≥ 3.6.1）时，可以直接问设备要**它自己扫到的** Wi-Fi 列表
  // （[loadDeviceWifiList]），连手机的 Wi-Fi 扫描都省了——「搜索不及时」的根就此绕开。
  //
  // ⚠️ **配网本身没有改**：仍然是 AP 那一条唯一路径（[pairViaHotspot]）。BLE 这条
  // 目前只管「发现设备」和「拿 Wi-Fi 列表」。真机验完才谈要不要再往前走。

  BleAvailability _bleAvailability = BleAvailability.unknown;

  /// 本轮扫到的设备，按 uuid 存最后一次上报（信号强度一直在变）。
  final Map<String, BleDevice> _bleDevices = <String, BleDevice>{};

  StreamSubscription<BleDevice>? _bleSub;
  bool _bleScanning = false;

  /// 云端查回来的产品信息，按 uuid 存。查过的（含查空的）都留下，避免重复往返。
  final Map<String, BleProductInfo> _bleProductInfo = <String, BleProductInfo>{};

  /// 正在查的 uuid，防止同一台并发查两次。
  final Set<String> _productInfoInFlight = <String>{};

  /// SDK 的 `onResult` 本轮被回调了多少次（取上报序号的最大值）。
  ///
  /// **判断"SDK 到底有没有在回报"**：列表为空而这个数在涨，说明扫描是活的、只是没留住；
  /// 两者都是 0 才是真的一次回调都没有。
  int _bleCallbackCount = 0;
  int get bleCallbackCount => _bleCallbackCount;

  /// **一轮搜索里最多查几台**。
  ///
  /// 这是云端往返：不过滤扫描时附近可能有几十台设备，挨个查会把接口打满、也会拖慢页面。
  /// 按信号从强到弱查前 20 台——想找的那台就在手边，几乎必然在这 20 台里。
  static const int _productInfoBudget = 20;


  /// 最近一次 [loadDeviceWifiList] 拿回来的、**设备自己扫到的** Wi-Fi 列表。
  List<DeviceWifiNetwork> _deviceWifiNetworks = <DeviceWifiNetwork>[];

  BleAvailability get bleAvailability => _bleAvailability;


  bool get bleScanning => _bleScanning;

  /// 扫到的设备，信号强的在前。
  ///
  /// 正常口径是**已经绑过的不列**（[BleDevice.bound]）：那些是别人家的、或这个账号
  /// 里已有的，点进去只会得到一个配网失败。
  ///
  /// ⚠️ 但 [PairingGate.showUnfilteredBleScan] 打开时**一个都不剔**：这一轮要回答的是
  /// 「设备到底在不在广播」，被过滤掉的恰恰可能就是答案——花盆若因为某种原因被报成
  /// 已绑定，剔掉之后页面上就是「什么都没扫到」，结论正好反了。列出来并在行上标注，
  /// 比藏起来有用。
  List<BleDevice> get bleDevices {
    final items = _bleDevices.values
        .where((item) {
          if (PairingGate.showUnfilteredBleScan) return true;
          // 正常动线：**只列本产品、且还没被绑定的**。附近别人的涂鸦设备、已经绑走的，
          // 列出来只会让用户点到一个必然失败的东西。
          return !item.bound && _isOurProduct(item);
        })
        .toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    // **按信号强弱只取前 [bleListLimit] 台**（2026-09-11 产品要求：列出来我看看有没有）。
    //
    // 不过滤 + 扫描类型全开之后，附近的涂鸦设备可能不止一台（邻居的、办公室里的）；
    // 全画出来页面长到没法看、也没法截图。按信号排序之后，**想找的那台几乎必然在最前面**
    // ——它就在手边。总数另由 [bleTotal] 报，页面上要说清「一共几台、列了几台」。
    // **本产品置顶**（pid == `TuyaConfig.productId`，2026-09-11 产品给的 pid
    // `yciq4kssu1fv8umn`）。不过滤扫描时附近可能有一堆别的涂鸦设备，花盆混在中间要人
    // 一行行找；把它顶上来，页面一眼就能回答「有没有」。同组内仍按信号排。
    items.sort((a, b) {
      final mine = _isOurProduct(b) ? 1 : 0;
      final theirs = _isOurProduct(a) ? 1 : 0;
      if (mine != theirs) return mine - theirs;
      return b.rssi.compareTo(a.rssi);
    });
    final capped = items.length <= bleListLimit
        ? items
        : items.sublist(0, bleListLimit);
    return List<BleDevice>.unmodifiable(capped);
  }

  /// 这台 BLE 设备**就是本产品**（花盆）。
  ///
  /// ⚠️ **两个 id 都要比**：BLE 扫描回来的 `ScanDeviceBean.getProductId()` 拿到的是
  /// **广播包里那个标识**（`TuyaConfig.broadcastId`），不是平台上的产品 ID。只比
  /// `productId` 会永远认不出来——2026-09-11 真机上扫到 -32dBm 的花盆却没被标成
  /// 「本产品」，就是这个原因。两者的区别见 [TuyaConfig.broadcastId]。
  ///
  /// 广播里的名字常常是空的、mac 每台都不同，所以这是唯一可靠的判据。
  bool _isOurProduct(BleDevice device) {
    final id = device.productId.trim();
    if (id.isEmpty) return false;
    // ① 本地兜底：平台产品 ID 与广播 ID（`TuyaConfig`）。后台没拉到时也能认。
    if (id == TuyaConfig.productId || id == TuyaConfig.broadcastId) return true;
    // ② 后台产品清单里的值也认（2026-09-11 产品口径「根据后台的接口配对一下」）。
    //
    //    ⚠️ **2026-09-12 起这一条基本不顶用了**：后台把 `broadcastId` 字段改成存
    //    平台产品 ID（界面文案也改叫「涂鸦产品ID」），而 BLE 广播里带的仍然是广播
    //    标识 `ehbx83xdh9jkmxvz`，两者对不上。现在认出这款花盆靠的是上面 ① 的本地
    //    常量。留着这一条只是兜底——万一以后哪个产品在后台填的就是广播标识。
    //
    //    要让「后台新增产品、App 不发版就能认」重新成立，得让后端把广播标识单独
    //    存一个字段，App 这边再把它并进这个集合。
    return _backendBroadcastIds.contains(id);
  }

  /// 后台产品清单里的 `broadcastId` 集合。拉不到就是空的，只走上面的本地兜底。
  final Set<String> _backendBroadcastIds = <String>{};

  /// 拉一株植物的**完整**资料（`/Client/UserProduct/getUserProductPlantDetail`）。
  ///
  /// ⚠️ 详情页必须调它：列表接口 `getProductPlantList` 的返回体只有五个字段
  /// （id/名称/图片/涂鸦标识/分类），**学名、别名、简介、温湿度、养护建议都不在里面**
  /// （2026-09-12 按 swagger 核实）。产品口径「植物相关的信息都调这个接口拿」。
  ///
  /// 查询键二选一，**优先涂鸦标识**（[tuyaRemark]）：它是 DP 116 报上来的那个值，
  /// 后台也保证不重复；自增 id 只在拿不到标识符时兜底。
  ///
  /// 拉不到就返回 null，页面继续用列表那份——空着总比编一份假的强。
  Future<PlantProfile?> loadPlantDetail({
    int? productPlantId,
    String? tuyaRemark,
  }) async {
    try {
      final plant = await _backend.getProductPlantDetail(
        productPlantId: productPlantId,
        tuyaRemark: tuyaRemark,
      );
      // 详情里也带涂鸦标识，顺手并进目录：下次按 DP 116 匹配就不用再拉一次。
      _rememberPlants(<PlantProfile>[plant]);
      return plant;
    } catch (_) {
      return null;
    }
  }

  /// 拉一次后台产品清单，把 `broadcastId` 记下来给搜索页配对用。
  ///
  /// 尽力而为：拉不到不拦路——本地兜底那两个常量仍然认得出当前这款。
  Future<void> refreshProductCatalog() async {
    try {
      final products = await _backend.getProducts();
      final ids = products
          .map((item) => item.broadcastId.trim())
          .where((id) => id.isNotEmpty);
      if (ids.isEmpty) return;
      _backendBroadcastIds
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (_) {
      // 后端没配、没登录、网络不好都可能失败，不该拦住配网。
    }
  }

  /// 扫到的**本产品**台数。页面上单独报——这就是「到底有没有搜到花盆」的答案。
  int get bleOurProductCount =>
      _bleDevices.values.where(_isOurProduct).length;

  /// 列表是否只保留本产品。排查态（[PairingGate.showUnfilteredBleScan]）下不过滤。
  bool get _filterToOurProduct => !PairingGate.showUnfilteredBleScan;

  /// 涂鸦 SDK 扫到的设备在页面上最多画几台。
  static const int bleListLimit = 50;

  /// 涂鸦 SDK 扫到的总台数（按 uuid 去重、过滤规则之后、**未截断**）。
  int get bleTotal => _bleDevices.values
      .where(
        (item) => PairingGate.showUnfilteredBleScan
            ? true
            : (!item.bound && _isOurProduct(item)),
      )
      .length;

  /// 这台 BLE 设备的云端产品信息；还没查到就是 null。
  BleProductInfo? productInfoFor(String uuid) => _bleProductInfo[uuid];

  /// 给**信号最强的前 [_productInfoBudget] 台**补齐云端产品信息。
  ///
  /// BLE 广播里常常没有名字，只有 mac + pid；拿 pid 去云端换回产品名之后，列表才真的
  /// 能"看出有没有"。每台只查一次（查空也算查过），失败也记一条空的——**否则每次
  /// 扫描回调都会重试，几十台设备就是几十次往返**。
  Future<void> refreshBleProductInfo() async {
    final targets = bleDevices.take(_productInfoBudget).where((device) {
      if (device.uuid.isEmpty || device.productId.isEmpty) return false;
      return !_bleProductInfo.containsKey(device.uuid) &&
          !_productInfoInFlight.contains(device.uuid);
    }).toList(growable: false);
    if (targets.isEmpty) return;
    for (final device in targets) {
      _productInfoInFlight.add(device.uuid);
      try {
        _bleProductInfo[device.uuid] = await _repository.queryDeviceProductInfo(
          productId: device.productId,
          uuid: device.uuid,
          mac: device.mac,
        );
      } catch (_) {
        // 查不到也要占位：不占的话每次扫描回调都会重试同一台。
        _bleProductInfo[device.uuid] = const BleProductInfo();
      } finally {
        _productInfoInFlight.remove(device.uuid);
      }
    }
    notifyListeners();
  }

  List<DeviceWifiNetwork> get deviceWifiNetworks =>
      List<DeviceWifiNetwork>.unmodifiable(_deviceWifiNetworks);

  /// 探一次 BLE 能不能用，结果记在 [bleAvailability] 上。
  ///
  /// 不抛错：这条路不可用只是回落到 Wi-Fi 扫描，不该把搜索页整页打断。
  Future<BleAvailability> probeBle() async {
    try {
      _bleAvailability = await _repository.bleProbe();
    } catch (error) {
      _bleAvailability = BleAvailability(
        available: false,
        supported: false,
        enabled: false,
        reason: '探测蓝牙失败：$error',
      );
    }
    notifyListeners();
    return _bleAvailability;
  }

  /// 开一轮 BLE 扫描。扫到的设备逐台进 [bleDevices]。
  ///
  /// **不占 [_guard] 的 busy 锁**：它和 Wi-Fi 扫描并行跑在搜索页上，占锁会把用户
  /// 这期间的任何操作挡成「请等待当前操作完成」——`probeWifi` 早就因为同样的理由
  /// 不占锁了。
  ///
  /// 返回 false 表示这条路没开起来（BLE 不可用、或原生拒绝），调用方照常走 Wi-Fi。
  Future<bool> startBleDiscovery({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_bleScanning) return true;
    // ⚠️ **顺序是这条路的命门**：必须先把授权框弹掉、等用户答完，再去探测。
    //
    // 2026-09-11 真机踩的就是这个：搜索页把 BLE 那条 `unawaited` 出去、紧接着才调
    // `probeWifi`，而**权限框是 `probeWifi` 触发的**。于是 BLE 探测抢在授权框被回答
    // 之前跑完，`checkSelfPermission` 报"未授予" ⇒ 不扫描、也没人再探一次，页面上
    // 就一直写着「缺少定位权限」——而用户去系统设置一看，权限明明给了。
    // 表现出来就是「第二次进 App 才正常」。
    //
    // 授权失败不在这里下结论：照常往下探测，由 `bleProbe` 的实测结果说话。
    try {
      await _repository.ensureBlePermissions();
    } catch (_) {
      // 用户拒了、或系统不再弹框。探测会把"缺哪一项"如实报出来。
    }
    final availability = await probeBle();
    if (!availability.usable) return false;
    _bleSub ??= _repository.bleDevices.listen((device) {
      // 按稳定键去重（uuid → mac → address → id）：广播里未必带 uuid，
      // 只按 uuid 会让所有没 uuid 的挤成一条。
      if (device.seq > _bleCallbackCount) _bleCallbackCount = device.seq;
      _bleDevices[device.key] = device;
      notifyListeners();
      // 顺手把云端产品信息补上（内部去重 + 限量，不会每条回调都往返）。
      unawaited(refreshBleProductInfo());
    });
    _bleCallbackCount = 0;
    try {
      await _repository.startBleScan(timeout: timeout);
    } catch (error) {
      _bleAvailability = BleAvailability(
        available: availability.available,
        supported: availability.supported,
        enabled: availability.enabled,
        reason: '开启 BLE 扫描失败：$error',
      );
      notifyListeners();
      return false;
    }
    _bleScanning = true;
    notifyListeners();
    return true;
  }

  /// 把用户送去本应用的系统设置页。
  ///
  /// 权限被点成「拒绝」之后系统不再弹框，这是唯一的出路。
  Future<void> openAppSettings() async {
    try {
      await _repository.openAppSettings();
    } catch (_) {
      // 打不开设置页不值得打断页面；用户还可以自己去系统设置。
    }
  }

  /// 停掉 BLE 扫描并断开订阅。
  ///
  /// **每条离开搜索页的路径都要调**：扫描回调在原生侧握着 Activity，而且在真的耗电。
  /// 没在扫时调用也安全。
  Future<void> stopBleDiscovery() async {
    await _bleSub?.cancel();
    _bleSub = null;
    _productInfoInFlight.clear();
    if (!_bleScanning) return;
    _bleScanning = false;
    try {
      await _repository.stopBleScan();
    } catch (_) {
      // 停不掉不该盖过调用方要做的事；最坏情况是多扫一会儿。
    }
    // ⚠️ **把 BLE 链路也断掉。** 设备只有在**没有连接**时才会广播；配网中途失败留下的
    // 那条连接会让它从此扫不到（2026-09-11 真机：之前搜得到、配网失败之后就搜不到了）。
    // 放在停扫之后、不抛错：它的职责就是"无论如何把设备放回广播状态"。
    try {
      await _repository.disconnectBleDevice();
    } catch (_) {
      // 断不掉也不该打断调用方；下一次进页面还会再断一次。
    }
    notifyListeners();
  }

  /// 走 BLE 问一台设备要**它自己扫到的** Wi-Fi 列表。
  ///
  /// ⚠️ 调用方必须先看 [BleDevice.supportWifiList]：老固件（TuyaOS < 3.6.1）不认这条
  /// 命令，调下去只会让用户干等一次超时——那比直接用手机扫到的列表还慢。
  Future<ActionResult> loadDeviceWifiList(BleDevice device) => _run(() async {
    if (!device.supportWifiList) {
      throw const TuyaException(
        'ble_wifi_list_unsupported',
        '这台设备的固件不支持回报 Wi-Fi 列表（需 TuyaOS 3.6.1 及以上）',
      );
    }
    final networks = await _repository.queryDeviceWifiList(device.uuid);
    _deviceWifiNetworks = networks;
    notifyListeners();
    return ActionResult(true, '设备扫到 ${networks.length} 个网络');
  });

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

  /// Dart 侧兜底的等待上限。原生各自有超时（系统弹框 60 秒、activator 120 秒），
  /// 这里只防原生永远不回话的情况——那会让 [_guard] 的 busy 锁永远不放，整个
  /// App 都点不动。到点后主动 [cancelPairing]，让原生把资源放掉。
  static const Duration hotspotJoinDeadline = Duration(seconds: 90);
  static const Duration pairingDeadline = Duration(seconds: 150);

  /// 配网前的准备：先把家庭确认下来、再取令牌，这两步都要走云端，必须在手机
  /// 还连着路由器时完成。
  ///
  /// 连上设备热点之后手机就没有外网，那时再查家庭轻则失败、重则拿到一份空列表
  /// 被当成「这个账号还没有家庭」而新建一个——账号里从此多一个空家庭，下次登录
  /// 就可能读到它、一台设备都没有。所以**搜索页进页面就先跑这一步**（`_prepared`），
  /// 点「连接」时先 await 它，成了才去连热点。
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

  // ══════════════ 联调日志（临时，流程验通后去掉） ══════════════
  //
  // 2026-09-12 产品要求：「和涂鸦、和设备有数据交互的，都在页面最下面打印一下每次
  // 操作的数据」，用于和涂鸦 / 固件联调。**这是临时设施**，跑通后连同页面上的日志框
  // 一起去掉（`PairingGate` 那种开关式收口同理）。
  //
  // 只记两类：**下发**（App → 设备的 DP 写）与**上报**（设备 → App 的 DP 变化）。
  // 两者就是"和设备的数据交互"的全部；云端接口另有 `ApiClient` 的日志，不混进来。

  /// 最近若干条交互日志，新的在最后。
  List<String> get interactionLog => List<String>.unmodifiable(_interactionLog);
  final List<String> _interactionLog = <String>[];

  /// 只留最近这些条：页面上放不下更多，而联调看的就是最后几条。
  static const int _interactionLogLimit = 60;

  /// 记一条交互日志。带时分秒——联调时要对着设备那边的时间看。
  void _logInteraction(String line) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    _interactionLog.add(
      '${two(now.hour)}:${two(now.minute)}:${two(now.second)} $line',
    );
    if (_interactionLog.length > _interactionLogLimit) {
      _interactionLog.removeAt(0);
    }
    notifyListeners();
  }

  /// 清空日志框。
  void clearInteractionLog() {
    _interactionLog.clear();
    notifyListeners();
  }

  /// 设备是否在线。**全站唯一的在线判断入口**。
  ///
  /// 产品口径（2026-09-12）：设备列表页、设备详情页能点进去的相关页面，以及所有
  /// 下发 DP 的动作，都要先过这一道。页面侧用 `ensureDeviceOnline(context, id)`
  /// 包一层提示和跳转，下发那一路在 [_publishDps] 里直接拦。
  ///
  /// 不认识的设备 id 一律当不在线：既然连设备都没有，就更谈不上能操作。
  bool isDeviceOnline(String id) => deviceById(id)?.online ?? false;

  /// 进到某个页面时记一条。
  void logPageEntry(String page) => _logInteraction('进入 ← [$page]');

  /// 进页面时把这一页的功能点连同当前取到的值一起记下来。
  ///
  /// 产品要的是「刚进来的时候就要读取功能设置对应的 DPID 是什么、接收到的值是
  /// 什么」，所以一行里把四样东西摆齐：App 的设置键 → 涂鸦标识符 → DP 号 → 页面
  /// 此刻用的值，联调时能直接对着功能点表看。
  ///
  /// ⚠️ 值是**页面当前取到的值**：设备还没上报过这条 DP 时，它就是 App 的默认值。
  /// 想区分「设备报的」和「App 默认的」，得等固件把全量 DP 报上来再说。
  void logSettingsSnapshot(String deviceId, String page, List<String> keys) {
    final device = deviceById(deviceId);
    if (device == null) {
      _logInteraction('读取 ← [$page] 未找到设备 $deviceId');
      return;
    }
    final entries = <String>[
      for (final key in keys) _settingLogEntry(device.settings, key),
    ];
    _logInteraction('读取 ← [$page] ${entries.join('，')}');
  }

  String _settingLogEntry(DeviceControlSettings settings, String key) {
    final value = _settingLogValue(settings, key);
    if (key == 'napPeriod') {
      return _periodLogEntry('nap_start_time', 'nap_end_time', value);
    }
    if (key == 'nightPeriod') {
      return _periodLogEntry(
        'night_sleep_start_time',
        'night_sleep_end_time',
        value,
      );
    }
    final identifier = TuyaConfig.setting[key];
    if (identifier == null) return '$key=未接功能点';
    final dpId = TuyaConfig.dp[identifier];
    if (dpId == null) return '$identifier=未接功能点';
    return 'DP$dpId $identifier=$value';
  }

  /// 作息那两项各占一头一尾两条 DP，页面上是一个区间，所以合起来记。
  String _periodLogEntry(
    String startIdentifier,
    String endIdentifier,
    Object? value,
  ) {
    final start = TuyaConfig.dp[startIdentifier];
    final end = TuyaConfig.dp[endIdentifier];
    return 'DP$start+DP$end $startIdentifier/$endIdentifier=$value';
  }

  Object? _settingLogValue(DeviceControlSettings settings, String key) =>
      switch (key) {
        'autoBrightness' || 'led' => settings.autoBrightness,
        'soundInteraction' => settings.soundInteraction,
        'soundSensitivity' => settings.soundSensitivity,
        'touchInteraction' => settings.touchInteraction,
        'touchSensitivity' => settings.touchSensitivity,
        'vibration' => settings.vibration,
        'touchKeyVibration' => settings.touchKeyVibration,
        'touchPlantVibration' => settings.touchPlantVibration,
        'napEnabled' => settings.napEnabled,
        'napPeriod' => settings.napPeriod,
        'nightEnabled' => settings.nightEnabled,
        'nightPeriod' => settings.nightPeriod,
        'temperatureUnit' => settings.temperatureUnit,
        'clockFormat' => settings.clockFormat,
        'standby' => settings.standbyEnabled,
        'standbyDelay' => settings.standbyDelayMinutes,
        'deviceLanguage' => settings.deviceLanguage,
        'plantDetection' => settings.plantDetection,
        _ => null,
      };

  /// 统一的 DP 下发入口：**所有写 DP 的地方都走它**，这样日志不会漏。
  ///
  /// 直接调 `_repository.publishDps` 的话，新增一处下发就少记一条，日志就不可信了。
  Future<void> _publishDps(String deviceId, Map<int, Object> dps) async {
    // 离线设备不下发：指令到不了设备，还会让页面以为改成功了。只拦「认识而且
    // 确实离线」的设备——刚配网完还没进列表的设备 [deviceById] 查不到，那种情况
    // 照常发，不然会把配网收尾的写操作一起拦掉。
    final known = deviceById(deviceId);
    if (known != null && !known.online) {
      _logInteraction('下发被拦 ✗ 设备已离线 $dps');
      throw const TuyaException('device_offline', '设备已离线');
    }
    _logInteraction('下发 → $dps');
    try {
      await _repository.publishDps(deviceId, dps);
    } catch (error) {
      _logInteraction('下发失败 ✗ $error');
      rethrow;
    }
  }

  /// 配网过程中的原生日志，**给页面直接显示用**。
  ///
  /// 产品不看 logcat（「你把日志直接打印到页面上，我截图给你」），所以这些行要能画在
  /// 界面上、能被截图。每次发起连接/配网时清空，之后原样追加。
  ///
  /// 只留最近 [_pairingLogLimit] 行——页面放不下更多，而定位问题看的就是最后那几行。
  List<String> get pairingLog => List<String>.unmodifiable(_pairingLog);
  final List<String> _pairingLog = <String>[];
  static const int _pairingLogLimit = 20;

  StreamSubscription<String>? _pairingLogSub;

  /// 开始一次连接/配网前调：清空旧日志并开始收。
  void _startPairingLog() {
    _pairingLog.clear();
    _pairingLogSub?.cancel();
    _pairingLogSub = _repository.pairingLogs.listen((line) {
      _pairingLog.add(line);
      if (_pairingLog.length > _pairingLogLimit) _pairingLog.removeAt(0);
      notifyListeners();
    });
  }

  Future<void> _stopPairingLog() async {
    await _pairingLogSub?.cancel();
    _pairingLogSub = null;
  }


  /// 连设备失败时的诊断串：原文 + 用时 + 手机当时连在哪个网络。
  ///
  /// 这三样比任何猜测都有用：**用时**看得出是不是跑满了超时（跑满 ⇒ SDK 一直没能和设备
  /// 说上话）；**手机当时连的网络**看得出 SDK 到底有没有把手机切到设备热点上（还显示路由器
  /// 名 ⇒ 它根本没切过去）。同时打一行到 logcat。
  String _connectDiagnostic(String reason, Stopwatch watch) {
    final now = _wifiScan?.current;
    final where = now == null || now.isEmpty
        ? '手机网络未知'
        : '手机在「$now」'
              '${(_wifiScan?.currentIsDeviceHotspot ?? false) ? '(设备热点)' : '(不是设备热点)'}';
    final detail = '$reason｜用时 ${watch.elapsedMilliseconds}ms · $where';
    debugPrint('[pairing] 连设备热点失败：$detail');
    return detail;
  }

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
  /// 连接，系统可能在用户选 Wi-Fi、输密码那段时间里把它掉掉。所以 [pairViaHotspot] 第②步
  /// 照常保留——已连就原地跳过（不会再弹框），掉了就重连。
  Future<ActionResult> connectDeviceHotspot({String? hotspotSsid}) =>
      _guard(() async {
        // 连热点这一步的原生日志也要留在页面上：失败原因（比如
        // `WifiManager.connect` 不可用）就在这几行里。
        _startPairingLog();
        final target =
            hotspotSsid ??
            _wifiScan?.deviceHotspots.map((item) => item.ssid).firstOrNull;
        _setPairingStage(PairingStage.connectingDevice);
        final watch = Stopwatch()..start();
        try {
          final joinedByApp = await _joinHotspotForPairing(
            target: target,
            joinedManually: false,
          );
          return ActionResult(
            true,
            joinedByApp ? '已连接设备热点' : '手机已经在设备热点上',
          );
        } on TuyaException catch (error) {
          // 事实在前、建议在后（`PRODUCT_RULES` §4.1）：原文 + 用时 + 手机当时连在哪。
          throw TuyaException(
            error.code,
            _connectDiagnostic(error.message, watch),
          );
        } finally {
          await _stopPairingLog();
          _setPairingStage(PairingStage.idle);
        }
      });




  /// 取消配网动线：把手机的 Wi-Fi 还回去，进度卡收起来。
  ///
  /// 「无论怎么退出都要把网络还回去」是硬性要求（`PRODUCT_RULES` §1.4.1）：用户点了
  /// 「取消」、退出页面、甚至杀掉 App，手机都不能被留在那条没有外网的设备热点上。
  Future<void> stopDevicePairing() async {
    await releaseDeviceHotspot();
    _setPairingStage(PairingStage.idle);
  }


  /// **AP 热点配网——全项目唯一的一条配网路径。**
  ///
  /// 2026-09-11 定稿。此前试过、已经删掉的三条：
  ///
  /// | 删掉的 | 为什么 |
  /// | --- | --- |
  /// | EZ / SmartConfig | 真机实测设备不支持 |
  /// | 涂鸦「热点配网新流程」（`queryDeviceConfigState` + `startActivator`） | 指望 SDK 自己连热点；涂鸦书面确认那句话**说的是设备端**，手机侧不会连 |
  /// | 扩展 SDK `ThingActivatorCoreKit` | 同上，也要手机先连热点，没有额外好处 |
  ///
  /// 实现要找回去看 git（`docs/history/2026-09/` 有索引）。**不要再接回来。**
  ///
  /// ## 三步
  ///
  /// 1. 取配网令牌（走云端，所以必须在手机还连着路由器时做）；
  /// 2. 把手机连到设备热点上——Android 10+ 这里**必弹一次系统入网授权框**，关不掉、
  ///    不能代点（涂鸦 2026-09-11 书面确认无绕过方案，见 `PRODUCT_RULES` §4.0）。
  ///    正常动线下搜索页那颗「连接」按钮已经连好了，这一步原地跳过、不会再弹；
  /// 3. 下发路由器 SSID/密码，等设备连上路由器并注册到云端。
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
        () => _repository.pair(
          PairingRequest(ssid: ssid, password: password),
        ),
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

  /// **双模配网：凭据经蓝牙交给设备，全程不碰 Wi-Fi 热点。**
  ///
  /// 这是 BLE 发现那条路的终点，也是它真正的收益所在——和 [pairViaHotspot] 比，少掉的
  /// 不只是几步：
  ///
  /// | | AP（[pairViaHotspot]） | 双模（这条） |
  /// | --- | --- | --- |
  /// | 系统入网授权框 | **必弹一次**（`WifiNetworkSpecifier` 唯一的公开路） | **没有** |
  /// | 要先知道热点确切 SSID | 要（Android 不接受前缀） | 不要 |
  /// | 手机要不要离开路由器 | 要（那段没有外网） | 不要 |
  /// | 发现速度 | 受 Wi-Fi 扫描配额（2 分钟 4 次） | 只受 BLE 广播 |
  ///
  /// 两步：
  ///
  /// 1. 取配网令牌——**照旧要在还连着路由器时取**，它走云端。双模下手机本来就没离开
  ///    路由器，所以这一步比 AP 那条更稳；
  /// 2. `pairBleDevice`：原生 `IMultiModeActivator.startActivator`，蓝牙段把 SSID/密码/
  ///    令牌交给设备，之后设备自己连路由器并注册到云端。
  ///
  /// 失败时**不释放热点**（压根没连过），只作废令牌：它可能已经被设备用掉了。
  Future<ActionResult> pairViaBle({
    required String uuid,
    required String ssid,
    required String password,
  }) => _guard(() async {
    final steps = <String>[];
    final watch = Stopwatch()..start();
    void mark(String name) {
      steps.add('$name ${watch.elapsedMilliseconds}ms');
      watch.reset();
    }

    String withSteps(String message) => '$message｜${steps.join(' · ')}';

    var pairingStarted = false;
    _setPairingStage(PairingStage.connectingDevice);
    try {
      if (activatorTokenReady) {
        mark('令牌(复用)');
      } else {
        await _repository.prepareActivatorToken();
        _activatorTokenAt = DateTime.now();
        mark('令牌');
      }
      pairingStarted = true;
      _setPairingStage(PairingStage.sendingWifi);
      final result = await _pairInternal(
        () => _repository.pairBleDevice(
          uuid: uuid,
          ssid: ssid,
          password: password,
        ),
      );
      mark('配网');
      return ActionResult(
        result.success,
        withSteps(result.message),
        code: result.code,
      );
    } on TuyaException catch (error) {
      mark('失败');
      // 没连过热点，所以只有令牌要收；配网已经发出去时它可能已被设备用掉。
      await _abandonPairingAttempt(
        releaseHotspot: false,
        invalidateToken: pairingStarted,
      );
      throw TuyaException(error.code, withSteps(error.message));
    } on ApiException catch (error) {
      mark('失败');
      await _abandonPairingAttempt(
        releaseHotspot: false,
        invalidateToken: pairingStarted,
      );
      throw ApiException(error.code, withSteps(error.message), data: error.data);
    } catch (_) {
      await _abandonPairingAttempt(
        releaseHotspot: false,
        invalidateToken: pairingStarted,
      );
      rethrow;
    } finally {
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

  /// [send] 是"真正把凭据发出去"的那一下：AP 走 `pair()`，双模走 `pairBleDevice()`。
  /// 两条路的收尾（置第三步、作废令牌、把设备并进列表、选中它）完全一样，所以只在
  /// 这一个参数上分叉——复制一份最容易在其中一份上漏掉作废令牌。
  Future<ActionResult> _pairInternal(
    Future<SmartPlanterDevice> Function() send,
  ) async {
    final device = await _pairOrRecover(send);
    // 走到这里 SDK 已经回了 onActiveSuccess——设备**已经**连上路由器并注册到云端了。
    // 第三步「连接云端」在这一刻置位、随即在 finally 里归 idle，界面上不会单独停留。
    //
    // 2026-09-11 晚删掉了这里原来那段 1–2 秒的随机 `Future.delayed`：它只是为了让第三步
    // 在进度卡上"亮一会儿"，纯装的（产品要"最简洁、最高效"）。成功页本身就是"云端完成"
    // 的信号，用户不会因为少看到一格转圈而困惑。
    _setPairingStage(PairingStage.connectingCloud);
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
  Future<SmartPlanterDevice> _pairOrRecover(
    Future<SmartPlanterDevice> Function() send,
  ) async {
    final knownIds = _devices.map((item) => item.id).toSet();
    try {
      return await send().timeout(
        pairingDeadline,
        onTimeout: _abortStalledPairing,
      );
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
    // 产品要求「点确定也在日志中看到下发的植物ID」。下面的 `_publishDps` 本来就会
    // 打出整个 DP map，但那一行读起来是 `{116: xxx, 161: y}`，不够直白；这里先单独
    // 写一条，说清这次确认下发的是哪一株。
    _logInteraction(
      '确认植物 → DP116=$reported'
      '${plant == null ? '（目录里没有这一株，只下发 116）' : '，${plant.name}'}',
    );
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
    await _publishDps(id, dps);
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

  /// 把历史 DP 的到货情况打进联调日志框。
  ///
  /// 产品 2026-09-12 反馈「需水状态页没有历史记录，同一台设备在智能生活 APP 上有」。
  /// 两边的数据源不是一回事：
  ///
  /// - 智能生活 APP 走的是**涂鸦云端统计服务**，云端自己按天/周/月聚合。
  /// - 本 App 走的是**设备自己上报的 131–139 九条 raw DP**——当初改成这样，就是因为
  ///   云端统计要付费订阅，这个账号没有。
  ///
  /// 所以"那边有、这边没有"完全可能同时成立：设备没把历史 DP 报上来，云端却有。
  /// 这个方法不修数据，只是把每条历史 DP 的原始长度和解出的点数打到页面上，
  /// 好分清是**设备没报**还是**报了解不出来**。
  Future<void> logHistoryDiagnostics(String deviceId, String page) async {
    try {
      final report = await _repository.historyDiagnostics(deviceId);
      if (report.isEmpty) {
        _logInteraction('读取 ← [$page] 历史 DP：一条都没有');
        return;
      }
      report.forEach((metricKey, line) {
        _logInteraction('读取 ← [$page] 历史 $metricKey：$line');
      });
    } catch (error) {
      _logInteraction('读取 ← [$page] 历史 DP 体检失败 ✗ $error');
    }
  }

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
        await _publishDps(deviceId, <int, Object>{dpId: true});
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
    await _publishDps(deviceId, <int, Object>{
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
      await _publishDps(id, <int, Object>{dpId: true});
    } on TuyaException {
      // Unreachable device: unbinding locally is still what was asked for.
    }
  }

  Future<void> _publishCalibration(String id, String step) async {
    final dpId = TuyaConfig.dp['water_level_calib'];
    if (dpId == null) {
      throw const TuyaException('unsupported_dp', '当前产品未提供水位校准功能点');
    }
    await _publishDps(id, <int, Object>{dpId: step});
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
    await _publishDps(id, dps);
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

  /// 帮助中心的常见问题。拉不到就返回空，页面画空态。
  ///
  /// 2026-09-12 接口加了 `broadcastId` 筛选（后台产品表那个字段，界面上现在叫
  /// 「涂鸦产品ID」）。App 这边用 [faqBroadcastId] 解析出来的值带上去，让常见问题
  /// 只出本产品的那几条。
  Future<List<BackendFaq>> loadFaqs() async {
    if (!_backend.enabled || !_backend.hasSession) return const <BackendFaq>[];
    try {
      return await _backend.getFaqs(broadcastId: faqBroadcastId);
    } catch (_) {
      return const <BackendFaq>[];
    }
  }

  /// 常见问题筛选用的产品标识。
  ///
  /// 取值顺序：当前选中设备的涂鸦产品 ID（SDK 给的，最准）→ 任意一台已绑定设备的
  /// → [TuyaConfig.productId]（还没绑设备时的兜底，本 App 只有这一款产品）。
  ///
  /// ⚠️ 这里要的是**涂鸦平台产品 ID**，不是 BLE 广播里那个标识
  /// （[TuyaConfig.broadcastId]）。后台那个字段名虽然还叫 `broadcastId`，2026-09-12
  /// 起存的是平台产品 ID，界面文案也改成了「涂鸦产品ID」。
  String get faqBroadcastId {
    final selected = selectedDevice?.productId.trim() ?? '';
    if (selected.isNotEmpty) return selected;
    for (final device in devices) {
      final id = device.productId.trim();
      if (id.isNotEmpty) return id;
    }
    return TuyaConfig.productId;
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
    _deviceUpdates = _repository.deviceUpdates.listen((update) {
      final device = update.device;
      if (device != null) {
        _logInteraction(
          '上报 ← 116=${device.plantVariety.isEmpty ? '-' : device.plantVariety}'
          ' 162=${device.plantConfirmRaw.isEmpty ? '-' : device.plantConfirmRaw}'
          ' 电量=${device.battery}%'
          ' 在线=${device.online ? '是' : '否'}',
        );
      } else if (update.removedId != null) {
        _logInteraction('上报 ← 设备被解绑 ${update.removedId}');
      }
      _applyDeviceUpdate(update);
      // ⚠️ **必须放在 [_applyDeviceUpdate] 之后**：计数一变页面就会重建并去读
      // `plantGuidePending`，而那个读的是合并后的设备快照。先记数的话，页面会拿
      // 着**上一版**状态判定「不用弹」，把这次上报白白消耗掉。
      if (device != null) _notePlantGuideReport(device, update.changedDps);
    });
    _otaUpdates?.cancel();
    _otaUpdates = _repository.otaUpdates.listen(_applyOtaProgress);
  }

  /// 这条上报里如果真的带了 162 且值为 true，就把计数 +1。
  ///
  /// **必须看 [DeviceUpdate.changedDps]**：设备快照是历史 DP 合并后的样子，只看
  /// `device.plantConfirm` 的话，温度、电量那些无关上报也会被当成"162 又报了一次"。
  void _notePlantGuideReport(SmartPlanterDevice device, Set<int> changedDps) {
    final dpId = TuyaConfig.dp['plant_present'];
    final previous = _lastPlantConfirm[device.id];
    _lastPlantConfirm[device.id] = device.plantConfirm;
    if (device.plantConfirm != PlantConfirmState.prompt) return;

    // 「设备又要求弹一次」有两条到货路径，都要认：
    //
    // ① 这条报文里确实带了 162——`onDpUpdate` 那条路，`dps` 里能看到 DP 号。
    // ② 162 由别的值翻成 prompt——`onDevInfoUpdate` 那条路整包快照下来，事件里
    //    没有逐条 DP，`changedDps` 是空的，只能靠前后值对比看出来。
    //
    // 反过来，**整包快照里 162 本来就是 true** 的情况不算（例如设备列表刚拉回来）：
    // 那不是一次新的上报，进页面那次检查已经负责弹了。
    final carried = dpId != null && changedDps.contains(dpId);
    final flipped = previous != null && previous != PlantConfirmState.prompt;
    if (!carried && !flipped) return;

    final count = (_plantGuideSignals[device.id] ?? 0) + 1;
    _plantGuideSignals[device.id] = count;
    _logInteraction(
      '上报 ← DP${dpId ?? 162} 植物确认=true（第 $count 次，'
      '${carried ? '报文带了该 DP' : '整包快照翻转'}）',
    );
  }

  /// 上一次看到的 162 值，用来认出「整包快照里 162 翻成了 true」。
  final Map<String, PlantConfirmState> _lastPlantConfirm =
      <String, PlantConfirmState>{};

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
    _onlinePoll?.cancel();
    _onlinePoll = null;
    _deviceUpdates?.cancel();
    _otaUpdates?.cancel();
    // BLE 扫描在原生侧握着 Activity、还在耗电，状态对象没了更没人去停它。
    //
    // ⚠️ **这里不能调 `stopBleDiscovery()`**：它 `await` 之后还要 `notifyListeners()`，
    // 而那一刻 `super.dispose()` 已经跑完，`ChangeNotifier` 会抛「used after being
    // disposed」。所以拆开手写，只做释放、不通知——已经没人在听了。
    unawaited(_bleSub?.cancel() ?? Future<void>.value());
    _bleSub = null;
    if (_bleScanning) {
      _bleScanning = false;
      unawaited(_repository.stopBleScan().catchError((Object _) {}));
    }
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

  // ══════════════ 在线状态：心跳推送 + 前台轮询兜底 ══════════════
  //
  // 在线/离线的**第一来源是涂鸦 SDK 的 MQTT 心跳**：设备掉线 → 云端按心跳超时判定
  // → 推给 SDK → SDK 更新 `DeviceBean` 并回调 `IDevListener.onStatusChanged`，原生侧
  // 的 `devListenerProxy` 把它转成 `{deviceId, online}` 事件送上来。这条路本身没问题。
  //
  // ⚠️ **但它会漏**（2026-09-12 产品反馈「设备关机了，App 还显示在线」）：
  //
  // 1. App 切到后台、或 MQTT 断开重连期间发生的状态变化**不会补发**，重连之后
  //    SDK 只是把 bean 更新到最新，不会再回放一次 `onStatusChanged`。
  // 2. 在这次改动之前，App **没有任何主动刷新**——设备清单只有下拉刷新会重拉。
  //    所以只要漏掉那一次回调，页面就一直停在「在线」。
  //
  // 云端判定本身的延迟（心跳超时，通常几十秒）是设备和云侧的事，App 改不了；
  // 能改的是别再漏。所以前台每 [onlinePollInterval] 读一次 SDK 的设备缓存
  // （[TuyaRepository.deviceOnlineStates]，**不发网络请求**），发现和本地不一致就更正。

  /// 前台轮询在线状态的间隔。读的是 SDK 本地缓存，没有网络开销。
  static const Duration onlinePollInterval = Duration(seconds: 8);

  Timer? _onlinePoll;

  /// App 回到前台：立刻对一次在线状态，再把设备清单整体刷一遍，然后开始轮询。
  void resumeDeviceWatch() {
    if (!authenticated) return;
    unawaited(_pollOnlineStates());
    unawaited(_refreshDevicesForSession(ignoreErrors: true));
    _ensureOnlinePolling();
  }

  /// App 进后台：停轮询。后台读缓存没意义，回前台时会立刻补一次。
  void pauseDeviceWatch() {
    _onlinePoll?.cancel();
    _onlinePoll = null;
  }

  void _ensureOnlinePolling() {
    if (_onlinePoll != null || !authenticated) return;
    _onlinePoll = Timer.periodic(onlinePollInterval, (timer) {
      if (!authenticated) {
        timer.cancel();
        _onlinePoll = null;
        return;
      }
      unawaited(_pollOnlineStates());
    });
  }

  /// 把 SDK 缓存里的在线标志对一遍，不一致就更正并记一条日志。
  Future<void> _pollOnlineStates() async {
    if (!authenticated || _devices.isEmpty) return;
    final ids = _devices.map((device) => device.id).toList(growable: false);
    Map<String, bool> states;
    try {
      states = await _repository.deviceOnlineStates(ids);
    } catch (_) {
      // 读不到就算了，下一轮再说——这只是兜底，不该把任何东西拦下来。
      return;
    }
    if (states.isEmpty) return;
    var changed = false;
    final next = <SmartPlanterDevice>[];
    for (final device in _devices) {
      final online = states[device.id];
      if (online == null || online == device.online) {
        next.add(device);
        continue;
      }
      changed = true;
      _logInteraction('心跳 ← ${device.name} 变为${online ? '在线' : '离线'}');
      next.add(device.copyWith(online: online));
    }
    if (!changed) return;
    _devices = next;
    notifyListeners();
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
      _ensureOnlinePolling();
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
