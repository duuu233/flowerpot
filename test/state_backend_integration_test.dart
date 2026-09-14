import 'support/fixture_backend.dart';
import 'dart:async';
import 'support/mock_tuya_repository.dart';
import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/core/network/network.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_gallery_codec.dart';
import 'package:flowerpot/src/tuya/tuya_memorial_codec.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a profile response arriving after logout cannot restore the old user', () async {
    final backend = _DelayedProfileBackend();
    final state = FlowerpotState(repository: _AuthRecordingTuya(), backendRepository: backend);
    addTearDown(state.dispose);
    await state.login(account: '13800138000', credential: '123456',
      region: LoginRegion.domestic, verificationCode: true);
    final pending = state.refreshUserInfo();
    await state.logout();
    backend.profile.complete(const BackendUserInfo(nickname: 'old user', account: '13800138000'));
    await pending;
    expect(state.authenticated, isFalse);
    expect(state.user, isNull);
  });

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
    // 后端那几个接口只要被碰到就会往 events 里记一笔，这里必须只剩 DP 写入；
    // 116 植物品种和 161 植物分类要在同一条 publishDps 里一起发出去。
    expect(events, <String>['tuya:116=monstera_en', 'tuya:161=2']);
    expect(state.selectedDevice?.plant.tuyaIdentifier, 'monstera_en');
  });

  test('后台没配植物分类时只下发 116，并在结果里说明', () async {
    final events = <String>[];
    final state = FlowerpotState(
      repository: _RecordingTuya(events),
      backendRepository: _RecordingBackend(events),
    );
    addTearDown(state.dispose);
    await state.login(
      account: 'demo@example.test',
      credential: 'demo',
      region: LoginRegion.overseas,
      verificationCode: false,
    );
    events.clear();

    final result = await state.selectPlant(
      state.devices.single.id,
      _uncategorizedPlant,
    );

    expect(result.success, isTrue);
    expect(result.message, '已选择薄荷并同步到设备；该植物在后台没有配置分类（categoryType），未下发 161');
    // 分类猜不得：宁可少发一条，也不给设备一个错的养护策略。
    expect(events, <String>['tuya:116=mint_en']);
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

  test('116 报 -1 就是没有植物，缓存里的那一株也要清掉', () async {
    final tuya = MockTuyaRepository(latency: Duration.zero);
    final state = FlowerpotState(
      repository: tuya,
      backendRepository: FixtureBackend(),
    );
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
    expect(state.hasPlant(device.id), isTrue);
    expect(state.plantMissing(device.id), isFalse);

    // 用户把植物拔了：设备报 -1。
    tuya.pushDeviceUpdate(
      DeviceUpdate.changed(device.copyWith(plantVariety: '-1')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(state.plantMissing(device.id), isTrue);
    expect(state.hasPlant(device.id), isFalse, reason: '本地缓存不能再说有植物');
  });

  test('后端会话失效只清后端，不动涂鸦会话和设备列表', () async {
    // 设备清单、DP、配网全部走涂鸦，跟 APP 后端的 token 无关。以前后端回一次 406
    // 就 `_clearLocalSession()`，用户被整个踢回登录页——表现就是「用一个小时（后端
    // token 的有效期）就掉登录」，而后端查自己的表说 token 还在。
    final tuya = _AuthRecordingTuya();
    final state = FlowerpotState(
      repository: tuya,
      backendRepository: _ExpiringBackend(),
    );
    addTearDown(state.dispose);
    await state.login(
      account: '13800138000',
      credential: '246810',
      region: LoginRegion.domestic,
      verificationCode: true,
    );
    expect(state.authenticated, isTrue);

    final result = await state.updateProfile(nickname: '新昵称');

    expect(result.success, isFalse);
    expect(result.code, '406');
    // 关键：涂鸦会话还在，用户不该被踢回登录页。
    expect(state.authenticated, isTrue);
    expect(state.user, isNotNull);
    // 失效原因留在现场信息里，排查时看得到是哪一层断的。
    expect(state.sessionDiagnostics, contains('后端会话'));
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
    final events = <String>[];
    final backend = _ImageBackend(events);
    final state = FlowerpotState(
      repository: _RecordingTuya(events),
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
    expect(backend.lastListDeviceId, deviceId);

    final upload = await state.addAnimation(
      deviceId,
      name: 'new.gif',
      path: 'C:/tmp/new.gif',
    );
    expect(upload.success, isTrue);
    expect(backend.lastUploadDeviceId, deviceId);
    expect(state.animations.map((item) => item.id), <String>['31', '32']);

    final deletion = await state.deleteAnimation(deviceId, '31');
    expect(deletion.success, isTrue);
    expect(state.animations.map((item) => item.id), <String>['32']);
    // ⚠️ 上传之后必须紧跟一条 DP 142 `dl_url`（2026-09-14：之前只传后端、一条 DP 都没发，
    // 设备根本不知道有新图）。帧里的文件名要和列表里那张（删除 155 / 置顶 157 用的）一致。
    final frame = TuyaMemorialCodec.encodeRaw(
      TuyaGalleryCodec.downloadFrame(
        url: 'https://cdn.example.test/new.gif',
        name: 'new.gif',
      ),
    );
    expect(state.animations.last.name, 'new.gif');
    expect(backend.events, <String>[
      'backend:upload:C:/tmp/new.gif',
      'tuya:142=$frame',
      'backend:delete:31',
    ]);
    expect(
      state.interactionLog.any(
        (line) => line.contains('DP142 dl_url：name=new.gif'),
      ),
      isTrue,
    );
  });

  test('a reported DP 116 identifier updates the active plant', () async {
    final tuya = MockTuyaRepository(latency: Duration.zero);
    final state = FlowerpotState(repository: tuya, backendRepository: FixtureBackend());
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
  plantType: 2,
);

/// 后台「植物管理」还没填分类的那一类行。
const _uncategorizedPlant = PlantProfile(
  id: 'server-mint',
  name: '薄荷',
  latinName: 'Mentha',
  color: Color(0xFF2F7D5D),
  moistureTarget: 60,
  lightTarget: 150,
  tip: '通风充足',
  productPlantId: 18,
  tuyaIdentifier: 'mint_en',
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

/// 登录正常，之后每次业务调用都以 406「请重新登录」失败：后端 token 过期的现场。
class _ExpiringBackend extends _AuthBackend {
  @override
  Future<void> changeNickname(String nickname) async {
    throw const ApiException(406, '请重新登录！');
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

  /// 图库只认涂鸦 `deviceId`：userProduct 那几个接口在 `_RecordingBackend` 里仍是
  /// `_forbidden`，图库流程一旦又去换 `userProductId` 就会让用例失败。下面两个字段
  /// 记下实际传给后端的设备号。
  String? lastListDeviceId;
  String? lastUploadDeviceId;

  @override
  Future<List<BackendImage>> getImages(String deviceId) async {
    lastListDeviceId = deviceId;
    return List<BackendImage>.of(images);
  }

  @override
  Future<String?> uploadImage({
    required String deviceId,
    required String filePath,
  }) async {
    lastUploadDeviceId = deviceId;
    events.add('backend:upload:$filePath');
    images.add(
      const BackendImage(
        id: 32,
        userProductId: 5,
        name: 'new.gif',
        url: 'https://cdn.example.test/new.gif',
      ),
    );
    // swagger `BaseUploadApiOut.url`：上传接口回的就是这张图的地址。
    return 'https://cdn.example.test/new.gif';
  }

  @override
  Future<void> deleteImages(List<int> imageIds) async {
    events.add('backend:delete:${imageIds.join(',')}');
    images.removeWhere((image) => imageIds.contains(image.id));
  }
}

class _DelayedProfileBackend extends _AuthBackend {
  final profile = Completer<BackendUserInfo>();
  @override
  Future<BackendUserInfo> getUserInfo() => profile.future;
}
