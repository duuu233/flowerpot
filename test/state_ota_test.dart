import 'support/plant_catalog.dart';
import 'support/mock_tuya_repository.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
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

  test('stage-only events keep the percent and never undo a result', () async {
    final repository = _OtaRepository();
    final state = await _state(repository);
    await state.upgradeFirmware('device-01', '1.1.0');
    expect(
      state.otaProgressFor('device-01')?.displayStage,
      OtaStage.preparing,
    );

    repository.pushOtaProgress(
      const OtaProgress(
        deviceId: 'device-01',
        status: OtaStatus.running,
        percent: 42,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    // 涂鸦只报阶段（6 固件已下载到设备）不带百分比：进度沿用 42，文案换成安装中。
    repository.pushOtaProgress(
      const OtaProgress(
        deviceId: 'device-01',
        status: OtaStatus.running,
        stage: OtaStage.installing,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(state.otaProgressFor('device-01')?.percent, 42);
    expect(
      state.otaProgressFor('device-01')?.displayStage,
      OtaStage.installing,
    );

    repository.pushOtaProgress(
      const OtaProgress(deviceId: 'device-01', status: OtaStatus.success),
    );
    await Future<void>.delayed(Duration.zero);
    // 迟到的进行中事件不能把「成功」改回去。
    repository.pushOtaProgress(
      const OtaProgress(
        deviceId: 'device-01',
        status: OtaStatus.running,
        stage: OtaStage.upgrading,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(state.otaProgressFor('device-01')?.status, OtaStatus.success);
    state.dispose();
  });

  test('display stage follows progress: 准备中 → 升级中 → 98% 起安装中', () {
    OtaStage stageOf({int? percent, OtaStage? stage}) => OtaProgress(
      deviceId: 'd',
      status: OtaStatus.running,
      percent: percent,
      stage: stage,
    ).displayStage;

    expect(stageOf(percent: 0), OtaStage.preparing);
    expect(stageOf(), OtaStage.preparing);
    // 涂鸦报了「升级中」但设备还没回进度：仍说准备中，不写 0%。
    expect(stageOf(percent: 0, stage: OtaStage.upgrading), OtaStage.preparing);
    expect(stageOf(percent: 0, stage: OtaStage.waitingWake), OtaStage.waitingWake);
    expect(stageOf(percent: 1), OtaStage.upgrading);
    expect(stageOf(percent: 97), OtaStage.upgrading);
    // 2026-09-17 产品：98% 起就算安装中——涂鸦在 98 停一大段等设备写固件、重启。
    expect(stageOf(percent: 98), OtaStage.installing);
    expect(stageOf(percent: 99), OtaStage.installing);
    expect(stageOf(percent: 100), OtaStage.installing);
    expect(stageOf(percent: 30, stage: OtaStage.installing), OtaStage.installing);

    expect(OtaStage.fromTuya(13), OtaStage.preparing);
    expect(OtaStage.fromTuya(14), OtaStage.preparing);
    expect(OtaStage.fromTuya(100), OtaStage.preparing);
    expect(OtaStage.fromTuya(2), OtaStage.upgrading);
    expect(OtaStage.fromTuya(5), OtaStage.waitingWake);
    expect(OtaStage.fromTuya(6), OtaStage.installing);
    expect(OtaStage.fromTuya(3), isNull);
    expect(OtaStage.fromTuya(null), isNull);
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

    final update = await state.checkFirmware('device-01');

    expect(update?.version, '1.1.0');
    expect(state.hasFirmwareUpdate('device-01'), isTrue);
    expect(state.availableFirmwareFor('device-01')?.version, '1.1.0');
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

  test('SDK 报的当前版本压过设备列表里的固件版本', () async {
    // 设备列表里是 1.0.0（Wi-Fi 模块），这次待升级的组件当前跑的是 2.0.0——
    // 两个版本号必须成对来自同一条 OTA 记录，否则弹窗上「当前版本」和「新版本」
    // 根本不是同一个东西。
    final state = await _state(
      _OtaRepository(firmware: '2.1.0', currentFirmware: '2.0.0'),
    );

    final update = await state.checkFirmware('device-01');

    expect(update?.version, '2.1.0');
    expect(update?.currentVersion, '2.0.0');
    expect(state.hasFirmwareUpdate('device-01'), isTrue);
    state.dispose();
  });

  test('SDK 把当前版本原样回来时不算新版本', () async {
    final state = await _state(
      _OtaRepository(firmware: '2.0.0', currentFirmware: '2.0.0'),
    );

    await state.checkFirmware('device-01');

    expect(state.hasFirmwareUpdate('device-01'), isFalse);
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

  group('OTA 兜底：安装中（≥98%）时版本号 DP 等于目标版本就算升级完成', () {
    // 2026-09-24 用户：花盆看 DP148、割草机看 DP112；目标版本是涂鸦检测升级返回的新版本；
    // 必须是 98% 以后（出现「固件安装中」）才判断；和涂鸦成功回调并存，任何一方满足就算。
    Future<void> report(
      _OtaRepository repository,
      String version,
      Set<int> dps, {
      String productId = 'product-01',
    }) async {
      repository.pushDeviceUpdate(
        DeviceUpdate.changed(
          _deviceOf(productId: productId).copyWith(firmwareVersion: version),
          changedDps: dps,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> progress(
      _OtaRepository repository, {
      int? percent,
      OtaStage? stage,
    }) async {
      repository.pushOtaProgress(
        OtaProgress(
          deviceId: 'device-01',
          status: OtaStatus.running,
          percent: percent,
          stage: stage,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    test('花盆：到 98% 后 DP148 报了目标版本 → 升级完成', () async {
      final repository = _OtaRepository();
      final state = await _state(repository);
      await state.refreshFirmwareUpdate('device-01');
      await state.upgradeFirmware('device-01', '1.1.0');
      await progress(repository, percent: 98);
      expect(
        state.otaProgressFor('device-01')?.displayStage,
        OtaStage.installing,
      );

      await report(repository, '1.1.0', <int>{148});

      expect(state.otaProgressFor('device-01')?.status, OtaStatus.success);
      expect(state.deviceById('device-01')?.firmwareVersion, '1.1.0');
      expect(state.hasFirmwareUpdate('device-01'), isFalse);
      state.dispose();
    });

    test('涂鸦报了阶段 6（固件已下载到设备）也算安装中', () async {
      final repository = _OtaRepository();
      final state = await _state(repository);
      await state.upgradeFirmware('device-01', '1.1.0');
      await progress(repository, percent: 60, stage: OtaStage.installing);

      await report(repository, 'V1.1.0', <int>{148});

      expect(state.otaProgressFor('device-01')?.status, OtaStatus.success);
      state.dispose();
    });

    test('割草机：到 98% 后 DP112 报了目标版本 → 升级完成', () async {
      final repository = _OtaRepository(productId: MowerDp.productId);
      final state = await _state(repository);
      await state.upgradeFirmware('device-01', '1.1.0');
      await progress(repository, percent: 98);

      await report(
        repository,
        '1.1.0',
        <int>{MowerDp.fwVersion},
        productId: MowerDp.productId,
      );

      expect(state.otaProgressFor('device-01')?.status, OtaStatus.success);
      state.dispose();
    });

    test('还没到 98%（准备中 / 升级中）：版本号对上也不判', () async {
      final repository = _OtaRepository();
      final state = await _state(repository);
      await state.upgradeFirmware('device-01', '1.1.0');

      await report(repository, '1.1.0', <int>{148});
      expect(state.otaProgressFor('device-01')?.status, OtaStatus.running);

      await progress(repository, percent: 97);
      await report(repository, '1.1.0', <int>{148});
      expect(state.otaProgressFor('device-01')?.status, OtaStatus.running);
      state.dispose();
    });

    test('割草机报 DP148 不算（那是花盆的版本号 DP）', () async {
      final repository = _OtaRepository(productId: MowerDp.productId);
      final state = await _state(repository);
      await state.upgradeFirmware('device-01', '1.1.0');
      await progress(repository, percent: 98);

      await report(
        repository,
        '1.1.0',
        <int>{148},
        productId: MowerDp.productId,
      );

      expect(state.otaProgressFor('device-01')?.status, OtaStatus.running);
      state.dispose();
    });

    test('报的不是目标版本：仍在安装中', () async {
      final repository = _OtaRepository();
      final state = await _state(repository);
      await state.upgradeFirmware('device-01', '1.1.0');
      await progress(repository, percent: 98);

      await report(repository, '1.0.0', <int>{148});

      expect(state.otaProgressFor('device-01')?.status, OtaStatus.running);
      state.dispose();
    });

    test('这条报文没带版本号 DP：不看快照里的版本', () async {
      final repository = _OtaRepository();
      final state = await _state(repository);
      await state.upgradeFirmware('device-01', '1.1.0');
      await progress(repository, percent: 98);

      await report(repository, '1.1.0', <int>{105});

      expect(state.otaProgressFor('device-01')?.status, OtaStatus.running);
      state.dispose();
    });

    test('涂鸦已经报了失败：版本号对上也不改判', () async {
      final repository = _OtaRepository();
      final state = await _state(repository);
      await state.upgradeFirmware('device-01', '1.1.0');
      await progress(repository, percent: 98);
      repository.pushOtaProgress(
        const OtaProgress(deviceId: 'device-01', status: OtaStatus.failed),
      );
      await Future<void>.delayed(Duration.zero);

      await report(repository, '1.1.0', <int>{148});

      expect(state.otaProgressFor('device-01')?.status, OtaStatus.failed);
      state.dispose();
    });

    test('和涂鸦成功回调并存：谁先到谁算，后到的不改结论', () async {
      final repository = _OtaRepository();
      final state = await _state(repository);

      // ① 版本号先到，回调后到。
      await state.upgradeFirmware('device-01', '1.1.0');
      await progress(repository, percent: 98);
      await report(repository, '1.1.0', <int>{148});
      expect(state.otaProgressFor('device-01')?.status, OtaStatus.success);
      repository.pushOtaProgress(
        const OtaProgress(deviceId: 'device-01', status: OtaStatus.success),
      );
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor('device-01')?.status, OtaStatus.success);
      expect(state.deviceById('device-01')?.firmwareVersion, '1.1.0');

      // ② 回调先到，版本号后到。
      await state.upgradeFirmware('device-01', '1.2.0');
      await progress(repository, percent: 98);
      repository.pushOtaProgress(
        const OtaProgress(deviceId: 'device-01', status: OtaStatus.success),
      );
      await Future<void>.delayed(Duration.zero);
      expect(state.otaProgressFor('device-01')?.status, OtaStatus.success);
      await report(repository, '1.2.0', <int>{148});
      expect(state.otaProgressFor('device-01')?.status, OtaStatus.success);
      expect(state.deviceById('device-01')?.firmwareVersion, '1.2.0');
      state.dispose();
    });

    test('App 里没发起过升级：不弹完成', () async {
      final repository = _OtaRepository();
      final state = await _state(repository);

      await report(repository, '1.1.0', <int>{148});

      expect(state.otaProgressFor('device-01'), isNull);
      state.dispose();
    });
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
  await state.initialize();
  await state.refreshDevices();
  return state;
}

SmartPlanterDevice get _device => _deviceOf();

SmartPlanterDevice _deviceOf({String productId = 'product-01'}) =>
    SmartPlanterDevice(
  id: 'device-01',
  productId: productId,
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
  _OtaRepository({
    this.firmware = '1.1.0',
    this.failsCheck = false,
    this.currentFirmware,
    this.productId = 'product-01',
  }) : super(latency: Duration.zero);

  /// 设备的产品 ID：传 [MowerDp.productId] 就是一台割草机。
  final String productId;

  /// 云端说可以装的版本，null 表示「没有新版本」。
  final String? firmware;

  /// 查询本身失败：设备离线，或者涂鸦后台没开通 OTA 能力。
  final bool failsCheck;

  /// 涂鸦在同一条 OTA 记录里报的当前版本；null 表示 SDK 没给，届时以设备列表
  /// 里的固件版本为准。
  final String? currentFirmware;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    _deviceOf(productId: productId),
  ];

  @override
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async {
    if (failsCheck) throw const TuyaException('sdk_error', '设备离线');
    final version = firmware;
    if (version == null) return null;
    return FirmwareUpdate(version: version, currentVersion: currentFirmware);
  }

  /// 真实桥接的 `startFirmwareUpgrade` 只是把升级发起出去就返回；Mock 的默认
  /// 实现要等一秒，测试里不需要那一秒。
  @override
  Future<void> startFirmwareUpgrade(String deviceId) async {}
}
