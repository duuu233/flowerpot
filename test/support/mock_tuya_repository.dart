import 'dart:async';
import 'dart:math' as math;
import 'package:flowerpot/src/tuya/tuya_config.dart';
import 'package:flowerpot/src/tuya/tuya_history_codec.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'plant_catalog.dart';

class MockTuyaRepository implements TuyaRepository {
  MockTuyaRepository({
    this.latency = const Duration(milliseconds: 260),
    this.seedDevice = true,
  });

  final Duration latency;

  final StreamController<DeviceUpdate> _updates =
      StreamController<DeviceUpdate>.broadcast();

  /// Silent unless a caller pushes: the mock backend has no device behind it,
  /// and inventing readings that drift on their own would make a demo look
  /// like a live planter.
  @override
  Stream<DeviceUpdate> get deviceUpdates => _updates.stream;

  final StreamController<OtaProgress> _otaUpdates =
      StreamController<OtaProgress>.broadcast();

  @override
  Stream<OtaProgress> get otaUpdates => _otaUpdates.stream;


  final StreamController<String> _pairingLogs =
      StreamController<String>.broadcast();

  @override
  Stream<String> get pairingLogs => _pairingLogs.stream;

  void emitPairingLog(String line) => _pairingLogs.add(line);

  final StreamController<BleDevice> _bleDevices =
      StreamController<BleDevice>.broadcast();

  @override
  Stream<BleDevice> get bleDevices => _bleDevices.stream;

  /// 让用例像真机那样逐台推 BLE 设备上来，不需要蓝牙硬件。
  void pushBleDevice(BleDevice device) => _bleDevices.add(device);

  final StreamController<String> _bleScanStops =
      StreamController<String>.broadcast();

  @override
  Stream<String> get bleScanStops => _bleScanStops.stream;

  /// 让用例模拟原生扫描**自己**结束（到时 / SDK 停了）。
  void endBleScan([String reason = 'timeout']) => _bleScanStops.add(reason);

  /// [ensureBlePermissions] 被调了几次；用例据此断言"授权在探测之前"。
  int blePermissionRequests = 0;
  int appSettingsOpens = 0;

  @override
  Future<void> ensureBlePermissions() async {
    await _wait();
    blePermissionRequests++;
  }

  @override
  Future<void> openAppSettings() async => appSettingsOpens++;

  /// 断开调用记录；用例据此断言"每条退出路径都断干净了"。
  final List<String> bleDisconnects = <String>[];

  @override
  Future<void> disconnectBleDevice({String uuid = ''}) async {
    bleDisconnects.add(uuid);
  }

  /// 云端产品信息的假数据：按 pid 给名字，用例可改。
  Map<String, BleProductInfo> productInfoByPid = <String, BleProductInfo>{
    'pid1': const BleProductInfo(name: '智能花盆'),
    // 真机上 BLE 广播里带的是 broadcastId，云端同样按它查得到产品。
    TuyaConfig.broadcastId: const BleProductInfo(name: '智能花盆'),
  };

  /// 查了几次；用例据此断言"去重 + 限量"真的生效。
  final List<String> productInfoQueries = <String>[];

  @override
  Future<BleProductInfo> queryDeviceProductInfo({
    required String productId,
    required String uuid,
    required String mac,
  }) async {
    await _wait();
    productInfoQueries.add(uuid);
    return productInfoByPid[productId] ?? const BleProductInfo();
  }

  /// 这一台 mock「手机」的 BLE 情况，用例按需改。默认可用——搜索页的主路径要能跑。
  BleAvailability bleAvailability = const BleAvailability(
    available: true,
    supported: true,
    enabled: true,
  );

  /// [startBleScan] / [stopBleScan] 各被调了几次；用例据此断言退出路径有没有停扫。
  int bleScanStarts = 0;
  int bleScanStopCalls = 0;

  /// [queryDeviceWifiList] 的返回。默认给两个网络，够页面画列表。
  List<DeviceWifiNetwork> deviceWifiList = const <DeviceWifiNetwork>[
    DeviceWifiNetwork(ssid: 'TP-LINK_2.4G', rssi: -48, sec: 3),
    DeviceWifiNetwork(ssid: 'Xiaomi_2.4G', rssi: -70, sec: 3),
  ];

  @override
  Future<BleAvailability> bleProbe() async {
    await _wait();
    return bleAvailability;
  }

  @override
  Future<void> startBleScan({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    await _wait();
    bleScanStarts++;
  }

  @override
  Future<void> stopBleScan() async {
    bleScanStopCalls++;
  }

  @override
  Future<List<DeviceWifiNetwork>> queryDeviceWifiList(
    String uuid, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await _wait();
    return deviceWifiList;
  }

  /// 双模配网调用记录：`(uuid, ssid)`。用例据此断言走的是蓝牙那条、不是 AP。
  final List<(String, String)> blePairCalls = <(String, String)>[];

  @override
  Future<SmartPlanterDevice> pairBleDevice({
    required String uuid,
    required String ssid,
    required String password,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    await _wait();
    blePairCalls.add((uuid, ssid));
    return pair(PairingRequest(ssid: ssid, password: password));
  }

  /// 让测试和演示能驱动升级进度，无需真实设备。
  void pushOtaProgress(OtaProgress progress) => _otaUpdates.add(progress);

  /// Pushes a report the way a real planter would, for tests and for driving
  /// the live-update path without hardware.
  void pushDeviceUpdate(DeviceUpdate update) {
    final device = update.device;
    if (device != null) {
      final index = _devices.indexWhere((item) => item.id == device.id);
      if (index >= 0) _devices[index] = device;
    }
    final removedId = update.removedId;
    if (removedId != null) {
      _devices.removeWhere((item) => item.id == removedId);
    }
    _updates.add(update);
  }

  /// Whether the account already owns a planter before any pairing runs.
  final bool seedDevice;

  AppUser? _user;
  late final List<SmartPlanterDevice> _devices = <SmartPlanterDevice>[
    if (seedDevice) _demoDevice(),
  ];

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

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
  Future<AppUser> loginWithUid({
    required String uid,
    required String password,
    required String countryCode,
  }) => login(
    account: uid,
    credential: password,
    region: LoginRegion.domestic,
    verificationCode: false,
  );

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

  /// 连热点被调过几次。EZ 模式下应当**恒为 0**——那正是它零系统 UI 的原因。
  int hotspotJoins = 0;

  @override
  Future<bool> joinDeviceHotspot({String? ssid, String? prefix}) async {
    hotspotJoins++;
    await _wait();
    return true;
  }

  @override
  Future<void> leaveDeviceHotspot() => _wait();

  /// Mock 的配网是一段固定延时，没有可以中止的东西。
  @override
  Future<void> cancelPairing() => _wait();

  @override
  Future<void> useHome(String homeId) async {}

  @override
  Future<void> useHomeTag(String tag) async {}

  @override
  Future<String> currentHomeId() async {
    await _wait();
    return 'mock-home';
  }


  /// 手机此刻连着的网络名。
  ///
  /// 用例把它改成设备热点名（`SmartLife-…` / `smartlife_…` / `tuya_mdev_…`）就能模拟
  /// 「用户已经在系统 Wi-Fi 面板里连上了设备热点」——AP 配网要求手机先在热点上，
  /// Android 10+ 不允许应用静默连网，产品选了「用户自己连」而不是系统入网授权框。
  String currentSsid = 'TP-LINK_2.4G';

  @override
  Future<WifiScan> scanWifi({bool refresh = true}) async {
    await _wait();
    return WifiScan(
      current: currentSsid,
      currentFrequency: 2437,
      networks: const <WifiNetwork>[
        WifiNetwork(ssid: 'TP-LINK_2.4G', level: -46, frequency: 2437),
        WifiNetwork(ssid: 'SmartLife-A1B2', level: -58, frequency: 2412),
        WifiNetwork(ssid: 'TP-LINK_5G', level: -52, frequency: 5180),
        WifiNetwork(ssid: 'Xiaomi_2.4G', level: -71, frequency: 2462),
      ],
    );
  }

  /// 每次 [publishDps] 的 `(设备 ID, DP)`，按发生顺序。用例据此断言下发了什么。
  final List<(String, Map<int, Object>)> publishedDps =
      <(String, Map<int, Object>)>[];

  /// 非空时 [publishDps] 抛它（模拟设备拒绝 / 网络失败）。
  TuyaException? publishError;

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    await _wait();
    publishedDps.add((deviceId, Map<int, Object>.of(dps)));
    final error = publishError;
    if (error != null) throw error;
  }

  /// [publishDpsWithMode] 每次用的模式，按顺序（和 [publishedDps] 一一对应的那几条）。
  final List<String> publishedModes = <String>[];

  @override
  Future<void> publishDpsWithMode(
    String deviceId,
    Map<int, Object> dps, {
    required String mode,
  }) async {
    publishedModes.add(mode);
    await publishDps(deviceId, dps);
  }

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
  Future<Map<String, bool>> deviceOnlineStates(List<String> deviceIds) async {
    await _wait();
    return <String, bool>{
      for (final device in _devices)
        if (deviceIds.contains(device.id)) device.id: device.online,
    };
  }

  @override
  Future<Map<String, String>> historyDiagnostics(String deviceId) async {
    await _wait();
    return const <String, String>{'mock': '演示仓库直接造数据，没有原始历史 DP'};
  }

  /// 演示仓库的设备是直接造出来的，没有原始 DP 快照。
  @override
  Future<Map<String, Object?>?> reportedDps(
    String deviceId,
    List<String> identifiers,
  ) async => null;

  /// 设备快照里的原始 DP（按 DP 号），用例按需填。没填的设备返回 null（= 还没拉到快照）。
  final Map<String, Map<int, Object?>> rawDpsByDevice =
      <String, Map<int, Object?>>{};

  @override
  Future<Map<int, Object?>?> rawDps(String deviceId) async {
    final dps = rawDpsByDevice[deviceId];
    return dps == null ? null : Map<int, Object?>.of(dps);
  }

  @override
  Future<List<double>> getHistory(
    String deviceId,
    SensorMetric metric,
    ReportRange range, {
    DateTime? date,
  }) async {
    await _wait();
    // 演示数据每天都造得出来：报表左右切日期时曲线得跟着换一条，不然看不出切没切。
    // 往前第 N 天的相位挪一格，形状还是那一个。
    final daysAgo = date == null ? 0 : _daysAgo(date);
    if (daysAgo < 0 || daysAgo >= TuyaHistoryCodec.maxDailyWindow) {
      return const <double>[];
    }
    final count = switch (range) {
      ReportRange.day => 24,
      ReportRange.week => 7,
      ReportRange.month => 30,
    };
    if (metric == SensorMetric.dli) return _dliSeries(count);
    final device = _devices.firstWhere(
      (item) => item.id == deviceId,
      orElse: () => _devices.isEmpty ? _demoDevice() : _devices.first,
    );
    if (metric == SensorMetric.battery) return <double>[device.battery.toDouble()];
    final series = _shapeSeries(metric, count);
    if (daysAgo == 0 || series.isEmpty) return series;
    return <double>[
      for (var index = 0; index < series.length; index++)
        series[(index + daysAgo) % series.length],
    ];
  }

  /// [date] 距今几天（同一天 = 0）。只看年月日，不看时分。
  static int _daysAgo(DateTime date) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
  }

  /// Each metric gets its own shape. A single rescaled waveform made every
  /// status page look like a copy of the previous one.
  static List<double> _shapeSeries(SensorMetric metric, int count) =>
      switch (metric) {
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
        SensorMetric.dli => _dliSeries(count),
      };

  /// 演示设备自带的历史包：状态页的曲线 2026-09-15 起直接读设备快照里的历史（和顶部
  /// 读数一样现读，涂鸦推送就跟着动），不再调 [getHistory]。形状和 [getHistory] 一致。
  static DeviceHistory _demoHistory() => DeviceHistory(<String, List<double>>{
    for (final metric in const <SensorMetric>[
      SensorMetric.waterLevel,
      SensorMetric.soilMoisture,
      SensorMetric.light,
      SensorMetric.temperature,
      SensorMetric.humidity,
    ])
      for (final range in ReportRange.values)
        DeviceHistory.key(metric, range): _shapeSeries(metric, switch (range) {
          ReportRange.day => 24,
          ReportRange.week => 7,
          ReportRange.month => 30,
        }),
  });

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
  Future<Map<String, Object?>> deviceMessages({
    required String deviceId,
    String msgType = 'MSG_REPORT',
    int offset = 0,
    int limit = 50,
  }) async => <String, Object?>{
    'ok': false,
    'msgSrcId': deviceId,
    'msgType': msgType,
    'diagnostic': <String>['Mock 仓库没有涂鸦消息中心，只有真机能答这个问题'],
  };

  @override
  Future<Map<String, Object?>> deviceOperateLogs({
    required String deviceId,
    String dpIds = '',
    int offset = 0,
    int limit = 20,
    String startTime = '',
    String endTime = '',
    String sort = '',
  }) async => <String, Object?>{
    'ok': false,
    'diagnostic': <String>['Mock 仓库没有涂鸦设备日志，只有真机能答这个问题'],
  };

  /// 蓝牙三件套的 Mock 状态：用例按需改（默认 = 两个通道都连着、信号 -40）。
  bool bleLinked = true;
  bool wifiLinked = true;
  bool bleConnectSucceeds = true;
  int bleRssi = -40;
  int bleConnectCalls = 0;

  @override
  Future<Map<String, Object?>> deviceLinkState(String deviceId) async =>
      <String, Object?>{'ble': bleLinked, 'wifi': wifiLinked};

  @override
  Future<Map<String, Object?>> connectDeviceBle(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    bleConnectCalls++;
    if (bleConnectSucceeds) bleLinked = true;
    return <String, Object?>{'connected': bleConnectSucceeds};
  }

  /// 涂鸦产品名称（更多设备信息「设备型号」）。
  String productName = 'YS 智能花盆';

  @override
  Future<Map<String, Object?>> deviceProductName(String deviceId) async =>
      <String, Object?>{'name': productName};

  /// 探测（requestWifiSignal）：列在这里的设备「没回应」（模拟路由器断了）。
  final Set<String> unreachableDevices = <String>{};
  int wifiSignalProbes = 0;

  @override
  Future<Map<String, Object?>> requestWifiSignal(
    String deviceId, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    wifiSignalProbes++;
    return unreachableDevices.contains(deviceId)
        ? <String, Object?>{'ok': false, 'code': 'timeout'}
        : <String, Object?>{'ok': true, 'signal': '-50'};
  }

  @override
  Future<Map<String, Object?>> readDeviceBleRssi(String deviceId) async =>
      <String, Object?>{'ok': bleLinked, 'rssi': bleLinked ? bleRssi : null};

  final StreamController<Map<String, Object?>> _pushMessages =
      StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<Map<String, Object?>> get pushMessages => _pushMessages.stream;

  /// 让用例模拟涂鸦推来一条告警。
  void emitPushMessage(Map<String, Object?> message) =>
      _pushMessages.add(message);

  @override
  Future<Map<String, Object?>> startPushListen() async => <String, Object?>{
    'ok': true,
    'registered': <String>['mock'],
    'diagnostic': <String>['Mock 仓库：推送由用例 emitPushMessage 模拟'],
  };

  @override
  Future<Map<String, Object?>> messagesByTime({
    required int startTime,
    required int endTime,
    String deviceId = '',
    int offset = 0,
    int limit = 50,
  }) async => <String, Object?>{
    'ok': false,
    'diagnostic': <String>['Mock 仓库没有涂鸦消息中心，只有真机能答这个问题'],
  };

  @override
  Future<String> createShareLink(String deviceId) async {
    await _wait();
    return 'https://app.flowerpot.example/share/$deviceId?code=PLANT88';
  }

  @override
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async {
    await _wait();
    return const FirmwareUpdate(version: '1.1.0', currentVersion: '1.0.8');
  }

  @override
  Future<void> startFirmwareUpgrade(
    String deviceId, {
    String? targetVersion,
    int? componentType,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  @override
  Future<void> uploadAnimation(String deviceId, AnimationAsset asset) =>
      _wait();

  /// Readings are picked to land in the "healthy" band of every status page:
  /// soil at 97 read as 偏湿 on the home card while the water page called the
  /// same value 适宜, and it clamped above the 0–100 chart axis.
  static SmartPlanterDevice get fixtureDevice => _demoDevice();

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
      waterLevel: 80,
      soilMoisture: 97,
      illuminance: 305,
      ppfd: 5.642,
      airTemperature: 26.9,
      relativeHumidity: 52,
    ),
    settings: const DeviceControlSettings(),
    firmwareVersion: '1.0.8',
    macAddress: 'A4:C1:38:7B:2D:10',
    hardwareVersion: '26',
    history: _demoHistory(),
  );
}

