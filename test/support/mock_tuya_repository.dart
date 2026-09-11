import 'dart:async';
import 'dart:math' as math;
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

  /// 这一台 mock「手机」的 BLE 情况，用例按需改。默认可用——搜索页的主路径要能跑。
  BleAvailability bleAvailability = const BleAvailability(
    available: true,
    supported: true,
    enabled: true,
  );

  /// [startBleScan] / [stopBleScan] 各被调了几次；用例据此断言退出路径有没有停扫。
  int bleScanStarts = 0;
  int bleScanStops = 0;

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
    bleScanStops++;
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
    if (metric == SensorMetric.battery) return <double>[device.battery.toDouble()];
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
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async {
    await _wait();
    return const FirmwareUpdate(version: '1.1.0', currentVersion: '1.0.8');
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
  );
}

