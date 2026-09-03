import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_config.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OTA is not a function point; only the version reports are', () {
    // 2026-09-03 的功能点表里和固件相关的只有两个只读版本号，升级本身没有 DP：
    // 走的是涂鸦 SDK 的 OTA 接口（Android newOTAInstance/getOtaInfo/startOta，
    // iOS getFirmwareUpgradeInfo/upgradeFirmware），由原生桥接封装。
    expect(TuyaConfig.dp['firmware_version'], 148);
    expect(TuyaConfig.dp['hardware_version'], 149);
    expect(
      TuyaConfig.dp.keys.where(
        (key) => key.contains('ota') || key.contains('upgrade'),
      ),
      isEmpty,
    );
    // 版本号是只上报的，写它没有意义，所以也不在可写设置表里。
    expect(TuyaConfig.settingDps('firmwareVersion', '1.1.0'), isNull);
  });

  test('starting an upgrade only reports that it started', () async {
    final state = await _state();

    final result = await state.upgradeFirmware('device-01', '1.1.0');

    expect(result.success, isTrue);
    // 版本号此时**不能**变：startOta 返回只代表升级发起了，设备还在下载。
    expect(state.deviceById('device-01')?.firmwareVersion, '1.0.0');
    expect(state.otaProgressFor('device-01')?.status, OtaStatus.running);
    expect(state.otaProgressFor('device-01')?.percent, 0);
    state.dispose();
  });

  test('progress events drive the row, success adopts the version', () async {
    final repository = _OtaRepository();
    final state = await _state(repository);
    await state.upgradeFirmware('device-01', '1.1.0');

    repository.pushOtaProgress(
      const OtaProgress(
        deviceId: 'device-01',
        status: OtaStatus.running,
        percent: 42,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(state.otaProgressFor('device-01')?.percent, 42);
    expect(state.deviceById('device-01')?.firmwareVersion, '1.0.0');

    repository.pushOtaProgress(
      const OtaProgress(deviceId: 'device-01', status: OtaStatus.success),
    );
    await Future<void>.delayed(Duration.zero);

    expect(state.otaProgressFor('device-01')?.status, OtaStatus.success);
    expect(state.deviceById('device-01')?.firmwareVersion, '1.1.0');
    state.dispose();
  });

  test('a failure keeps the old version and carries the reason', () async {
    final repository = _OtaRepository();
    final state = await _state(repository);
    await state.upgradeFirmware('device-01', '1.1.0');

    repository.pushOtaProgress(
      const OtaProgress(
        deviceId: 'device-01',
        status: OtaStatus.failed,
        message: '设备离线',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(state.otaProgressFor('device-01')?.status, OtaStatus.failed);
    expect(state.otaProgressFor('device-01')?.message, '设备离线');
    expect(state.deviceById('device-01')?.firmwareVersion, '1.0.0');
    state.dispose();
  });

  test('an upgrade that stops reporting can be cleared and retried', () async {
    final state = await _state();
    await state.upgradeFirmware('device-01', '1.1.0');

    // 刚发起，不算卡住。
    expect(state.otaStalled('device-01'), isFalse);

    state.clearOtaProgress('device-01');

    // 清掉之后界面回到「可以重新检查」，设备那头是不是还在升级只有它自己知道。
    expect(state.otaProgressFor('device-01'), isNull);
    expect(state.otaStalled('device-01'), isFalse);
    state.dispose();
  });

  test('a version the device does not run yet lights the red dot', () async {
    final state = await _state(_OtaRepository(firmware: '1.1.0'));

    // 没查过就没有结论，界面上不点红点。
    expect(state.hasFirmwareUpdate('device-01'), isFalse);

    final version = await state.checkFirmware('device-01');

    expect(version, '1.1.0');
    expect(state.hasFirmwareUpdate('device-01'), isTrue);
    expect(state.availableFirmwareFor('device-01'), '1.1.0');
    state.dispose();
  });

  test('the version the device already runs is not an update', () async {
    // 涂鸦在设备已是最新时可能把当前版本原样回来，那不是「有新版本」。
    final state = await _state(_OtaRepository(firmware: '1.0.0'));

    await state.checkFirmware('device-01');

    expect(state.hasFirmwareUpdate('device-01'), isFalse);
    expect(state.availableFirmwareFor('device-01'), isNull);
    state.dispose();
  });

  test('a silent check that fails keeps the page quiet', () async {
    // 进页面时的静默检查失败不该惊动用户（设备离线、后台没开通 OTA 能力都会
    // 报错），但用户主动点「固件版本更新」时仍要能拿到失败原因。
    final state = await _state(_OtaRepository(failsCheck: true));

    await state.refreshFirmwareUpdate('device-01');

    expect(state.hasFirmwareUpdate('device-01'), isFalse);
    await expectLater(
      state.checkFirmware('device-01'),
      throwsA(isA<TuyaException>()),
    );
    state.dispose();
  });

  test('the red dot goes out only once the device reports success', () async {
    final repository = _OtaRepository();
    final state = await _state(repository);
    await state.checkFirmware('device-01');
    await state.upgradeFirmware('device-01', '1.1.0');

    // 还在下载烧录，新版本仍然是「待装」。
    expect(state.hasFirmwareUpdate('device-01'), isTrue);

    repository.pushOtaProgress(
      const OtaProgress(deviceId: 'device-01', status: OtaStatus.success),
    );
    await Future<void>.delayed(Duration.zero);

    expect(state.hasFirmwareUpdate('device-01'), isFalse);
    expect(state.deviceById('device-01')?.firmwareVersion, '1.1.0');
    state.dispose();
  });

  test('a device that never started an upgrade is never stalled', () async {
    final state = await _state();

    expect(state.otaProgressFor('device-01'), isNull);
    expect(state.otaStalled('device-01'), isFalse);
    // 没有进度可清时不发通知，也不报错。
    state.clearOtaProgress('device-01');
    expect(state.otaProgressFor('device-01'), isNull);
    state.dispose();
  });
}

Future<FlowerpotState> _state([_OtaRepository? repository]) async {
  final state = FlowerpotState(repository: repository ?? _OtaRepository());
  await state.refreshDevices();
  return state;
}

SmartPlanterDevice get _device => SmartPlanterDevice(
  id: 'device-01',
  productId: 'product-01',
  name: 'YSplanter-01',
  online: true,
  signal: 86,
  battery: 94,
  charging: false,
  boundAt: DateTime.now().subtract(const Duration(days: 51)),
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
  firmwareVersion: '1.0.0',
  macAddress: 'D8:85:AC:A2:B9:B4',
);

class _OtaRepository extends MockTuyaRepository {
  _OtaRepository({this.firmware = '1.1.0', this.failsCheck = false})
    : super(latency: Duration.zero);

  /// 云端说可以装的版本，null 表示「没有新版本」。
  final String? firmware;

  /// 查询本身失败：设备离线，或者涂鸦后台没开通 OTA 能力。
  final bool failsCheck;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    _device,
  ];

  @override
  Future<String?> checkFirmware(String deviceId) async {
    if (failsCheck) throw const TuyaException('sdk_error', '设备离线');
    return firmware;
  }

  /// 真实桥接的 `startFirmwareUpgrade` 只是把升级发起出去就返回；Mock 的默认
  /// 实现要等一秒，测试里不需要那一秒。
  @override
  Future<void> startFirmwareUpgrade(String deviceId) async {}
}
