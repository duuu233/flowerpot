import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/core/network/network.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('登录和选植物都不打多余的后端接口，只写 DP 116', () async {
    final events = <String>[];
    final tuya = _RecordingTuya(events);
    final backend = _RecordingBackend(events);
    final state = FlowerpotState(repository: tuya, backendRepository: backend);
    addTearDown(state.dispose);
    await state.login(
      account: 'demo@example.test',
      credential: 'demo',
      region: LoginRegion.overseas,
      verificationCode: false,
    );

    final result = await state.selectPlant(
      state.devices.single.id,
      _serverPlant,
    );

    expect(result.success, isTrue);
    expect(result.message, '已选择龟背竹并同步到设备');
    // 后端那几个接口只要被碰到就会往 events 里记一笔，这里必须只剩 DP 写入。
    expect(events, <String>['tuya:116=monstera_en']);
    expect(state.selectedDevice?.plant.tuyaIdentifier, 'monstera_en');
  });

  test('water calibration sends 0 through 3 and cancel 5, never 4', () async {
    final events = <String>[];
    final state = FlowerpotState(repository: _RecordingTuya(events));
    addTearDown(state.dispose);

    for (var step = 0; step < 4; step++) {
      expect(
        (await state.calibrateWaterLevel('device-1', step)).success,
        isTrue,
      );
    }
    expect(
      (await state.cancelWaterLevelCalibration('device-1')).success,
      isTrue,
    );

    expect(events, <String>[
      'tuya:140=step0',
      'tuya:140=step1',
      'tuya:140=step2',
      'tuya:140=step3',
      'tuya:140=step5',
    ]);
    expect(events, isNot(contains('tuya:140=step4')));
  });

  test('domestic login uses backend Tuya credentials and profile', () async {
    final tuya = _AuthRecordingTuya();
    final backend = _AuthBackend();
    final state = FlowerpotState(repository: tuya, backendRepository: backend);
    addTearDown(state.dispose);

    final result = await state.login(
      account: '13800138000',
      credential: '246810',
      region: LoginRegion.domestic,
      verificationCode: true,
    );

    expect(result.success, isTrue);
    expect(backend.mobile, '13800138000');
    expect(backend.code, '246810');
    expect(tuya.account, 'tuya-user-no');
    expect(tuya.credential, 'tuya-password');
    expect(tuya.verificationCode, isFalse);
    expect(state.user?.nickname, '后台昵称');
    expect(state.user?.account, '13800138000');
  });

  test('an auto-registered mobile is told the account was created', () async {
    final state = FlowerpotState(
      repository: _AuthRecordingTuya(),
      backendRepository: _AuthBackend(registered: true),
    );
    addTearDown(state.dispose);

    final result = await state.login(
      account: '13800138000',
      credential: '246810',
      region: LoginRegion.domestic,
      verificationCode: true,
    );

    expect(result.success, isTrue);
    expect(result.message, '已为你创建账号并登录');
  });

  test('device images load, upload and delete through the backend', () async {
    final backend = _ImageBackend(<String>[]);
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
      backendRepository: backend,
    );
    addTearDown(state.dispose);
    await state.login(
      account: 'demo@example.test',
      credential: 'demo',
      region: LoginRegion.overseas,
      verificationCode: false,
    );
    final deviceId = state.devices.single.id;

    await state.refreshAnimations(deviceId);
    expect(state.animations.map((item) => item.id), <String>['31']);

    final upload = await state.addAnimation(
      deviceId,
      name: 'new.gif',
      path: 'C:/tmp/new.gif',
    );
    expect(upload.success, isTrue);
    expect(state.animations.map((item) => item.id), <String>['31', '32']);

    final deletion = await state.deleteAnimation(deviceId, '31');
    expect(deletion.success, isTrue);
    expect(state.animations.map((item) => item.id), <String>['32']);
    expect(backend.events, <String>[
      'backend:upload:C:/tmp/new.gif',
      'backend:delete:31',
    ]);
  });

  test('a reported DP 116 identifier updates the active plant', () async {
    final tuya = MockTuyaRepository(latency: Duration.zero);
    final state = FlowerpotState(repository: tuya);
    addTearDown(state.dispose);
    await state.initialize();
    await state.login(
      account: 'demo@example.test',
      credential: 'demo',
      region: LoginRegion.overseas,
      verificationCode: false,
    );
    final device = state.devices.single;

    tuya.pushDeviceUpdate(
      DeviceUpdate.changed(device.copyWith(plantVariety: 'pothos')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(state.deviceById(device.id)?.plant.id, 'pothos');
    expect(state.hasPlant(device.id), isTrue);
  });
}

const _serverPlant = PlantProfile(
  id: 'server-monstera',
  name: '龟背竹',
  latinName: 'Monstera deliciosa',
  color: Color(0xFF2F7D5D),
  moistureTarget: 58,
  lightTarget: 140,
  tip: '明亮散射光',
  productPlantId: 17,
  tuyaIdentifier: 'monstera_en',
);

class _RecordingTuya extends MockTuyaRepository {
  _RecordingTuya(this.events) : super(latency: Duration.zero);

  final List<String> events;

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    for (final entry in dps.entries) {
      events.add('tuya:${entry.key}=${entry.value}');
    }
  }
}

/// 主流程（登录 → 配网 → 给设备加植物）只允许 `getProductPlantList` 一个后端
/// 调用。这里把它以外、以前被这条链路用到的接口都改成「记一笔再抛错」，谁再把
/// 它们接回主流程，测试就会红。
class _RecordingBackend extends DisabledAppBackendRepository {
  _RecordingBackend(this.events);

  final List<String> events;

  @override
  bool get enabled => true;

  @override
  bool get hasSession => true;

  Never _forbidden(String name) {
    events.add('backend:$name');
    throw const ApiException(500, '主流程不该调用这个接口');
  }

  @override
  Future<List<BackendProduct>> getProducts() async => _forbidden('getProducts');

  @override
  Future<List<BackendUserProduct>> getUserProducts() async =>
      _forbidden('getUserProducts');

  @override
  Future<BackendUserProduct> getUserProductDetail(int userProductId) async =>
      _forbidden('getUserProductDetail');

  @override
  Future<BackendUserProduct> addUserProduct({
    required String deviceId,
    required BackendProduct product,
  }) async => _forbidden('addUserProduct');

  @override
  Future<BackendUserInfo> getUserInfo() async => _forbidden('getUserInfo');
}

class _AuthRecordingTuya extends MockTuyaRepository {
  _AuthRecordingTuya() : super(latency: Duration.zero);

  String? account;
  String? credential;
  bool? verificationCode;

  @override
  Future<AppUser> login({
    required String account,
    required String credential,
    required LoginRegion region,
    required bool verificationCode,
  }) async {
    this.account = account;
    this.credential = credential;
    this.verificationCode = verificationCode;
    return super.login(
      account: account,
      credential: credential,
      region: region,
      verificationCode: verificationCode,
    );
  }
}

class _AuthBackend extends DisabledAppBackendRepository {
  _AuthBackend({this.registered = false});

  /// 后端仓库补注册后返回的会话，用来验证登录页提示会跟着换。
  final bool registered;
  String? mobile;
  String? code;

  @override
  bool get enabled => true;

  @override
  bool get hasSession => true;

  @override
  Future<BackendAuthAccount> loginWithCode({
    required String mobile,
    required String code,
  }) async {
    this.mobile = mobile;
    this.code = code;
    return BackendAuthAccount(
      userToken: 'api-token',
      tuyaAccount: 'tuya-user-no',
      tuyaPassword: 'tuya-password',
      countryCode: '86',
      nickname: '后台昵称',
      account: '13800138000',
      registered: registered,
    );
  }
}

class _ImageBackend extends _RecordingBackend {
  _ImageBackend(super.events);

  final List<BackendImage> images = <BackendImage>[
    const BackendImage(
      id: 31,
      userProductId: 5,
      name: 'first.gif',
      url: 'https://cdn.example.test/first.gif',
    ),
  ];

  /// 设备图库不在主流程上，它仍旧要靠 userProduct 记录拿 `userProductId`。
  @override
  Future<List<BackendUserProduct>> getUserProducts() async =>
      const <BackendUserProduct>[
        BackendUserProduct(
          userProductId: 5,
          productId: 9,
          deviceId: 'vdevo17235508413621',
          productName: '智能花盆',
        ),
      ];

  @override
  Future<List<BackendImage>> getImages(int userProductId) async =>
      List<BackendImage>.of(images);

  @override
  Future<void> uploadImage({
    required int userProductId,
    required String filePath,
  }) async {
    events.add('backend:upload:$filePath');
    images.add(
      const BackendImage(
        id: 32,
        userProductId: 5,
        name: 'new.gif',
        url: 'https://cdn.example.test/new.gif',
      ),
    );
  }

  @override
  Future<void> deleteImages(List<int> imageIds) async {
    events.add('backend:delete:${imageIds.join(',')}');
    images.removeWhere((image) => imageIds.contains(image.id));
  }
}
