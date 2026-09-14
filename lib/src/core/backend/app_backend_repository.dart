import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../../tuya/tuya_models.dart';
import '../network/network.dart';
import 'backend_models.dart';

/// REST boundary for account, product, plant and device-image APIs.
///
/// UI pages never call this directly; [FlowerpotState] coordinates it with the
/// Tuya session and device DP writes.
abstract class AppBackendRepository {
  /// 帮助中心常见问题列表接口。
  static const String faqListPath = '/Client/Product/getProductFaqList';

  bool get enabled;
  bool get hasSession;

  /// [path] 最近一次请求的原样记录（地址、请求头、状态码、响应体），联调时画到页面上用。
  /// 没请求过、或没有 HTTP 客户端时为 null。
  ApiExchange? lastExchange(String path);

  Future<bool> initialize({required String languageCode});
  void setLanguage(String languageCode);
  void clearSession();
  void close();

  Future<void> sendSms({required String mobile, required int sendType});
  Future<BackendAuthAccount> loginWithPassword({
    required String mobile,
    required String password,
  });

  /// 手机验证码登录。登录页是登录注册一体的：手机号还没有后端账号时，实现要用
  /// 同一条验证码补一次注册再返回会话，[BackendAuthAccount.registered] 标出走的
  /// 是哪一条路。
  Future<BackendAuthAccount> loginWithCode({
    required String mobile,
    required String code,
  });
  Future<BackendAuthAccount> registerMobile({
    required String mobile,
    required String code,
    required String password,
  });

  Future<List<BackendProduct>> getProducts();
  Future<List<BackendUserProduct>> getUserProducts();
  Future<BackendUserProduct> getUserProductDetail(int userProductId);
  Future<BackendUserProduct> addUserProduct({
    required String deviceId,
    required BackendProduct product,
  });
  Future<void> deleteUserProduct(int userProductId);

  /// 产品下的植物列表。主流程（登录 → 配网 → 给设备加植物）只走这一个后端接口，
  /// 所以不再先查 `getProductList` 换 productId——不传就是后台配置的全部植物。
  Future<List<PlantProfile>> getProductPlants({String keyword = ''});

  /// 单株植物的**完整**资料。
  ///
  /// ⚠️ **必须单独拉一次，列表接口给不了。**（2026-09-12 按 swagger 核实）
  /// `/Client/Product/getProductPlantList` 的返回体 `ClientProductPlantApiOut` **只有五个
  /// 字段**：`productPlantId` / `plantName` / `plantImg` / `tuYaRemark` / `categoryType`
  /// ——**没有学名、没有别名**，也没有简介、温湿度、养护建议。那一整套在
  /// `/Client/UserProduct/getUserProductPlantDetail` 的 `ClientProductPlantDetailApiOut` 里。
  ///
  /// 植物详情页此前直接用列表传进来的对象、从不单独拉详情，所以「学名」「别名」永远是
  /// 空的——产品反馈的就是这个。
  ///
  /// 两个查询键**二选一，不能同时为空**（2026-09-12 后端加的 `tuYaRemark`）：
  ///
  /// - [tuyaRemark] → 接口参数 `tuYaRemark`，**涂鸦标识符**。优先用它：它才是设备
  ///   DP 116 报上来的那个值，而且后台保证不重复。
  /// - [productPlantId] → 接口参数 `id`，后端自增主键。只在拿不到标识符时兜底。
  ///
  /// 两个都给时只发 [tuyaRemark]；都为空直接抛，不发请求。
  Future<PlantProfile> getProductPlantDetail({
    int? productPlantId,
    String? tuyaRemark,
  });

  /// 设备图库按涂鸦 `deviceId` 走，不再先用 `getUserProductList` 换后端的
  /// `userProductId`：设备档案由涂鸦提供，看一眼图片不该先在后端建一条用户产品
  /// 记录，那条链路上任何一个接口不可用（例如 404）都会把图库整页顶掉。
  Future<List<BackendImage>> getImages(String deviceId);

  /// 上传一张设备图片，返回后端给的图片 URL（swagger `BaseUploadApiOut.url`）；
  /// 接口没回地址时为 null。
  ///
  /// 这个 URL 要原样经 DP 142 `dl_url` 发给设备去下载，所以不能只上传不取返回。
  Future<String?> uploadImage({
    required String deviceId,
    required String filePath,
  });
  Future<void> deleteImages(List<int> imageIds);

  // ── 用户资料 / 账号 ────────────────────────────────────────────────
  Future<BackendUserInfo> getUserInfo();
  Future<void> changeNickname(String nickname);
  Future<void> changeAvatar(String avatarUrl);

  /// 已登录用户的短信验证码，改密码/改绑手机用，不用再传手机号。
  Future<void> sendSmsToCurrentUser();
  Future<void> changePassword({
    required String verifyCode,
    required String password,
  });
  Future<void> resetPassword({
    required String mobile,
    required String verifyCode,
    required String password,
  });
  Future<void> logout();
  Future<void> deactivateAccount();

  // ── 基础数据 ──────────────────────────────────────────────────────
  Future<BackendAppVersion?> getLastVersion(String appVersionNo);
  Future<BackendBasicData> getBasicData();
  /// [broadcastId] 是后台产品表那个字段（界面上 2026-09-12 起叫「涂鸦产品ID」），
  /// 用来把常见问题筛到本产品。传空就不带这个参数，行为和以前一样。
  Future<List<BackendFaq>> getFaqs({String keyword = '', String broadcastId = ''});
  Future<BackendFaq?> getFaqDetail(int faqId);

  /// 通用文件上传，返回可以直接写进 DP 帧或提交给后端的 URL。设备图库走的是
  /// [uploadImage]（会进设备图片列表），头像和纪念日图片走这一条。
  Future<String> uploadFile(String filePath);

  /// 编辑设备信息：改名，以及「一键清除设备图片」。
  Future<void> editUserProduct({
    required int userProductId,
    required String productName,
    int? productId,
    bool clearImages = false,
  });

  // ── 纪念日 ────────────────────────────────────────────────────────
  //
  // 整组按涂鸦 `deviceId` 走（swagger `ClientProductAnniversaryAddApiIn.deviceId`），
  // 不再先用 `getUserProductList` 换后端的 `userProductId`：那几个用户产品接口
  // 已经从 swagger 下线，打过去就是 404，纪念日保存会在第一步就失败。
  Future<List<BackendAnniversary>> getAnniversaries(String deviceId);
  Future<BackendAnniversary?> getAnniversaryDetail(int anniversaryId);

  /// 返回后端分配的 `anniversaryId`，它同时也是写进 DP 154 的帧 id。
  Future<int> addAnniversary({
    required String deviceId,
    required String title,
    required String content,
    required bool imageContent,
    required DateTime date,
  });
  Future<void> editAnniversary({
    required int anniversaryId,
    required String deviceId,
    required String title,
    required String content,
    required bool imageContent,
    required DateTime date,
  });
  Future<void> setAnniversaryEnabled(List<int> anniversaryIds, bool enabled);
  Future<void> deleteAnniversary(int anniversaryId);
}

/// Used when no REST origin was supplied. This preserves the existing
/// Tuya-only and mock flows instead of constructing an invalid HTTP client.
class DisabledAppBackendRepository implements AppBackendRepository {
  const DisabledAppBackendRepository();

  @override
  bool get enabled => false;

  @override
  bool get hasSession => false;

  @override
  ApiExchange? lastExchange(String path) => null;

  Never _disabled() => throw const ApiException(
    'API_NOT_CONFIGURED',
    '未配置 APP 后端地址，请通过 API_BASE_URL 提供服务地址',
  );

  @override
  Future<bool> initialize({required String languageCode}) async => false;

  @override
  void setLanguage(String languageCode) {}

  @override
  void clearSession() {}

  @override
  void close() {}

  @override
  Future<void> sendSms({required String mobile, required int sendType}) async =>
      _disabled();

  @override
  Future<BackendAuthAccount> loginWithPassword({
    required String mobile,
    required String password,
  }) async => _disabled();

  @override
  Future<BackendAuthAccount> loginWithCode({
    required String mobile,
    required String code,
  }) async => _disabled();

  @override
  Future<BackendAuthAccount> registerMobile({
    required String mobile,
    required String code,
    required String password,
  }) async => _disabled();

  @override
  Future<List<BackendProduct>> getProducts() async => _disabled();

  @override
  Future<List<BackendUserProduct>> getUserProducts() async => _disabled();

  @override
  Future<BackendUserProduct> getUserProductDetail(int userProductId) async =>
      _disabled();

  @override
  Future<BackendUserProduct> addUserProduct({
    required String deviceId,
    required BackendProduct product,
  }) async => _disabled();

  @override
  Future<void> deleteUserProduct(int userProductId) async => _disabled();

  @override
  Future<List<PlantProfile>> getProductPlants({String keyword = ''}) async =>
      _disabled();

  @override
  Future<PlantProfile> getProductPlantDetail({
    int? productPlantId,
    String? tuyaRemark,
  }) async => _disabled();

  @override
  Future<List<BackendImage>> getImages(String deviceId) async => _disabled();

  @override
  Future<String?> uploadImage({
    required String deviceId,
    required String filePath,
  }) async => _disabled();

  @override
  Future<void> deleteImages(List<int> imageIds) async => _disabled();

  @override
  Future<BackendUserInfo> getUserInfo() async => _disabled();

  @override
  Future<void> changeNickname(String nickname) async => _disabled();

  @override
  Future<void> changeAvatar(String avatarUrl) async => _disabled();

  @override
  Future<void> sendSmsToCurrentUser() async => _disabled();

  @override
  Future<void> changePassword({
    required String verifyCode,
    required String password,
  }) async => _disabled();

  @override
  Future<void> resetPassword({
    required String mobile,
    required String verifyCode,
    required String password,
  }) async => _disabled();

  @override
  Future<void> logout() async {}

  @override
  Future<void> deactivateAccount() async => _disabled();

  @override
  Future<BackendAppVersion?> getLastVersion(String appVersionNo) async =>
      _disabled();

  @override
  Future<BackendBasicData> getBasicData() async => BackendBasicData.empty;

  @override
  Future<List<BackendFaq>> getFaqs({
    String keyword = '',
    String broadcastId = '',
  }) async => const <BackendFaq>[];

  @override
  Future<BackendFaq?> getFaqDetail(int faqId) async => null;

  @override
  Future<String> uploadFile(String filePath) async => _disabled();

  @override
  Future<void> editUserProduct({
    required int userProductId,
    required String productName,
    int? productId,
    bool clearImages = false,
  }) async => _disabled();

  @override
  Future<List<BackendAnniversary>> getAnniversaries(String deviceId) async =>
      const <BackendAnniversary>[];

  @override
  Future<BackendAnniversary?> getAnniversaryDetail(int anniversaryId) async =>
      null;

  @override
  Future<int> addAnniversary({
    required String deviceId,
    required String title,
    required String content,
    required bool imageContent,
    required DateTime date,
  }) async => _disabled();

  @override
  Future<void> editAnniversary({
    required int anniversaryId,
    required String deviceId,
    required String title,
    required String content,
    required bool imageContent,
    required DateTime date,
  }) async => _disabled();

  @override
  Future<void> setAnniversaryEnabled(
    List<int> anniversaryIds,
    bool enabled,
  ) async => _disabled();

  @override
  Future<void> deleteAnniversary(int anniversaryId) async => _disabled();
}

class HttpAppBackendRepository implements AppBackendRepository {
  HttpAppBackendRepository({required ApiClient client})
    : _client = client,
      _session = client.session;

  factory HttpAppBackendRepository.fromEnvironment() =>
      HttpAppBackendRepository(client: ApiClient.fromEnvironment());

  final ApiClient _client;

  @override
  ApiExchange? lastExchange(String path) => _client.lastExchange(path);
  final ApiSession _session;

  @override
  bool get enabled => true;

  @override
  bool get hasSession => _session.isLoggedIn;

  @override
  Future<bool> initialize({required String languageCode}) async {
    setLanguage(languageCode);
    return _session.restore();
  }

  @override
  void setLanguage(String languageCode) => _session.setLanguage(languageCode);

  @override
  void clearSession() => _session.clear();

  @override
  void close() => _client.close();

  @override
  Future<void> sendSms({required String mobile, required int sendType}) async {
    await _client.postJson(
      '/Client/Basic/smsSend',
      auth: false,
      body: <String, Object?>{'userMobile': mobile, 'sendType': sendType},
    );
  }

  @override
  Future<BackendAuthAccount> loginWithPassword({
    required String mobile,
    required String password,
  }) => _authenticate('/Client/User/userLoginPassword', <String, Object?>{
    'userMobile': mobile,
    'password': _md5(password),
  });

  @override
  Future<BackendAuthAccount> loginWithCode({
    required String mobile,
    required String code,
  }) async {
    try {
      return await _authenticate(
        '/Client/User/userLoginVerifyCode',
        <String, Object?>{'userMobile': mobile, 'verifyCode': code},
      );
    } on ApiException catch (error) {
      if (!_isAccountMissing(error)) rethrow;
      // 登录注册一体：验证码本身已经被登录接口判过一次，失败的只是账号查找，
      // 所以用同一条验证码补注册。注册接口返回的是同一套会话字段（userToken /
      // userNo / tuYaPwd），不需要再登录一次。
      return registerMobile(
        mobile: mobile,
        code: code,
        password: _generatedPassword(),
      );
    }
  }

  @override
  Future<BackendAuthAccount> registerMobile({
    required String mobile,
    required String code,
    required String password,
  }) {
    final digest = _md5(password);
    return _authenticate(
      '/Client/User/userRegisterMobile',
      <String, Object?>{
        'userMobile': mobile,
        'verifyCode': code,
        'password': digest,
        'confirmPassword': digest,
      },
      registered: true,
    );
  }

  Future<BackendAuthAccount> _authenticate(
    String path,
    Map<String, Object?> body, {
    bool registered = false,
  }) async {
    final data = _map(
      await _client.postJson(
        path,
        auth: false,
        retryTransportErrors: false,
        body: body,
      ),
    );
    final result = BackendAuthAccount(
      userToken: _text(data, 'userToken'),
      tuyaAccount: _text(data, 'userNo'),
      tuyaPassword: _text(data, 'tuYaPwd'),
      countryCode: _text(data, 'countryCode', fallback: '86'),
      nickname: _text(data, 'nickName', fallback: '植物守护者'),
      account: _text(data, 'userMobile'),
      avatarUrl: _nullableText(data['avatar']),
      // 字段名以 `tuYaHomeId` 为准（与 `tuYaPwd`、`tuYaRemark` 同一套写法），
      // 另外兼容两种常见拼法，免得为了大小写再发一版。
      tuyaHomeId:
          _nullableText(data['tuYaHomeId']) ??
          _nullableText(data['tuyaHomeId']) ??
          _nullableText(data['homeId']),
      userId: _nullableText(data['userId']) ?? _nullableText(data['id']),
      registered: registered,
    );
    if (result.userToken.isEmpty ||
        result.tuyaAccount.isEmpty ||
        result.tuyaPassword.isEmpty) {
      throw const ApiException('LOGIN_DATA_INVALID', '登录返回缺少用户或涂鸦会话信息');
    }
    _session.setToken(result.userToken);
    return result;
  }

  @override
  Future<List<BackendProduct>> getProducts() async => extractApiRows(
    await _client.getJson(
      '/Client/Product/getProductList',
      query: const <String, Object?>{'pageIndex': 1, 'pageSize': 200},
    ),
  ).map(_product).where((item) => item.productId > 0).toList(growable: false);

  @override
  Future<List<BackendUserProduct>> getUserProducts() async => extractApiRows(
    await _client.getJson(
      '/Client/UserProduct/getUserProductList',
      query: const <String, Object?>{'pageIndex': 1, 'pageSize': 200},
    ),
  ).map(_userProduct).where((item) => !item.deleted).toList(growable: false);

  @override
  Future<BackendUserProduct> getUserProductDetail(int userProductId) async =>
      _userProduct(
        _map(
          await _client.getJson(
            '/Client/UserProduct/getUserProductDetail',
            query: <String, Object?>{'userProductId': userProductId},
          ),
        ),
      );

  @override
  Future<BackendUserProduct> addUserProduct({
    required String deviceId,
    required BackendProduct product,
  }) async => _userProduct(
    _map(
      await _client.postJson(
        '/Client/UserProduct/addUserProduct',
        retryTransportErrors: false,
        body: <String, Object?>{
          'deviceId': deviceId,
          'productId': product.productId,
          'productName': product.productName,
        },
      ),
    ),
  );

  @override
  Future<void> deleteUserProduct(int userProductId) async {
    await _client.postJson(
      '/Client/UserProduct/delUserProduct',
      retryTransportErrors: false,
      body: <String, Object?>{'id': userProductId},
    );
  }

  @override
  Future<List<PlantProfile>> getProductPlants({String keyword = ''}) async =>
      extractApiRows(
        await _client.getJson(
          '/Client/Product/getProductPlantList',
          query: <String, Object?>{
            'pageIndex': 1,
            'pageSize': 500,
            if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
          },
        ),
      ).map(_plant).toList(growable: false);

  @override
  Future<PlantProfile> getProductPlantDetail({
    int? productPlantId,
    String? tuyaRemark,
  }) async {
    // 二选一：有涂鸦标识就用它，没有才退回自增 id。**只发其中一个**——接口说的是
    // 「二选一」，同时发两个的行为没定义，别赌。
    final remark = tuyaRemark?.trim() ?? '';
    if (remark.isEmpty && productPlantId == null) {
      throw const ApiException(
        'PLANT_DETAIL_NO_KEY',
        '查植物详情要给 tuYaRemark 或 id，两个不能都为空',
      );
    }
    // [ApiClient.getJson] 已经拆过信封——`retCode` 不是 200 时它自己抛，成功时
    // 返回的就是 `retData` 本身，这里不能再取一次 `retData`。
    //
    // 这个接口的 retData 是**单个对象**，不是分页行，所以 `extractApiRows` 用不上；
    // 不是对象时 `_map` 会抛 PARSE_ERROR。
    final data = await _client.getJson(
      '/Client/UserProduct/getUserProductPlantDetail',
      query: remark.isNotEmpty
          ? <String, Object?>{'tuYaRemark': remark}
          : <String, Object?>{'id': productPlantId},
    );
    return _plant(_map(data));
  }

  @override
  Future<List<BackendImage>> getImages(String deviceId) async =>
      extractApiRows(
        await _client.getJson(
          '/Client/UserProduct/getUserProductImgList',
          query: <String, Object?>{
            'pageIndex': 1,
            'pageSize': 100,
            'deviceId': deviceId,
          },
        ),
      ).map(_image).where((item) => item.id > 0).toList(growable: false);

  @override
  Future<String?> uploadImage({
    required String deviceId,
    required String filePath,
  }) async => _uploadedUrl(
    await _client.upload(
      '/Client/Basic/setUserProductUpload',
      filePaths: <String>[filePath],
      query: <String, Object?>{'deviceId': deviceId},
    ),
  );

  @override
  Future<void> deleteImages(List<int> imageIds) async {
    if (imageIds.isEmpty) return;
    await _client.postJson(
      '/Client/UserProduct/delUserProductImg',
      retryTransportErrors: false,
      body: <String, Object?>{'idList': imageIds},
    );
  }


  @override
  Future<BackendUserInfo> getUserInfo() async =>
      _userInfo(_map(await _client.getJson('/Client/User/getUserInfo')));

  @override
  Future<void> changeNickname(String nickname) async {
    await _client.postJson(
      '/Client/User/changeNickName',
      retryTransportErrors: false,
      body: <String, Object?>{'nickName': nickname},
    );
  }

  @override
  Future<void> changeAvatar(String avatarUrl) async {
    await _client.postJson(
      '/Client/User/changeAvatar',
      retryTransportErrors: false,
      body: <String, Object?>{'avatar': avatarUrl},
    );
  }

  @override
  Future<void> sendSmsToCurrentUser() async {
    await _client.postJson('/Client/Basic/smsUser', retryTransportErrors: false);
  }

  @override
  Future<void> changePassword({
    required String verifyCode,
    required String password,
  }) async {
    final digest = _md5(password);
    await _client.postJson(
      '/Client/User/changePassword',
      retryTransportErrors: false,
      body: <String, Object?>{
        'verifyCode': verifyCode,
        'password': digest,
        'confirmPassword': digest,
      },
    );
  }

  @override
  Future<void> resetPassword({
    required String mobile,
    required String verifyCode,
    required String password,
  }) async {
    final digest = _md5(password);
    await _client.postJson(
      '/Client/User/resetPassword',
      auth: false,
      retryTransportErrors: false,
      body: <String, Object?>{
        'userMobile': mobile,
        'verifyCode': verifyCode,
        'password': digest,
        'confirmPassword': digest,
      },
    );
  }

  @override
  Future<void> logout() async {
    try {
      await _client.postJson('/Client/User/loginOut', retryTransportErrors: false);
    } finally {
      // 服务端退不掉也要把本地令牌丢掉，否则下一次启动会拿着一条已经没用的
      // 令牌去恢复会话。
      _session.clear();
    }
  }

  @override
  Future<void> deactivateAccount() async {
    await _client.postJson('/Client/User/userOff', retryTransportErrors: false);
    _session.clear();
  }

  @override
  Future<BackendAppVersion?> getLastVersion(String appVersionNo) async {
    final data = await _client.getJson(
      '/Client/Basic/getLastVersion',
      query: <String, Object?>{'appVersionNo': appVersionNo},
    );
    if (data is! Map) return null;
    final row = _map(data);
    final latest = _text(
      row,
      'appVersionNo',
      fallback: _text(row, 'versionNo', fallback: _text(row, 'version')),
    );
    if (latest.isEmpty) return null;
    final flag =
        row['isUpdate'] ?? row['hasUpdate'] ?? row['needUpdate'] ?? row['isNew'];
    // 2026-09-08 按 swagger 的 `AppVersionConApiOutput` 对齐字段：
    // `appVersionNo` / `isUpdate`(1=是) / `compulsory`(1=强制 2=强提示 3=弱提示
    // 4=不提示) / `downloadPath` / `upgradeTips`。旧的 isForce、downloadUrl、
    // updateContent 都是字段名未定时的猜测，留作兜底。
    final compulsory = _nullableInteger(
      row['compulsory'] ?? row['upgradeType'],
    );
    return BackendAppVersion(
      versionNo: latest,
      // 后端没给判定标记时按版本号比对兜底，而不是默认「有更新」——那会让
      // 关于页天天弹红点。
      hasUpdate: flag == null ? latest != appVersionNo.trim() : _boolean(flag),
      forceUpdate: compulsory == null
          ? _boolean(row['isForce'] ?? row['forceUpdate'] ?? row['isCoerce'])
          : compulsory == 1,
      downloadUrl: _text(
        row,
        'downloadPath',
        fallback: _text(
          row,
          'downloadUrl',
          fallback: _text(row, 'downUrl', fallback: _text(row, 'url')),
        ),
      ),
      releaseNotes: _lines(
        _text(
          row,
          'upgradeTips',
          fallback: _text(
            row,
            'updateContent',
            fallback: _text(row, 'content', fallback: _text(row, 'remark')),
          ),
        ),
      ),
    );
  }

  @override
  Future<BackendBasicData> getBasicData() async {
    // 这个接口没有 swagger 模型，后台配了什么字段就返回什么。把整棵树拍平成
    // 小写键值对，再由 [BackendBasicData] 去认协议、隐私政策这些常见命名。
    final flattened = <String, String>{};
    void register(String key, String? value) {
      if (key.isEmpty || value == null || value.isEmpty) return;
      flattened.putIfAbsent(key.toLowerCase(), () => value);
    }

    void walk(Object? value) {
      if (value is Map) {
        // 配置也可能是 `[{configKey: 'userAgreement', configValue: '...'}]`
        // 这种键值对行。那种形状下字面字段名是 configKey/configValue，直接按
        // 字段名收集是认不出协议正文的，所以先把这一对还原成一条配置。
        register(
          _nullableText(
                value['configKey'] ??
                    value['keyName'] ??
                    value['code'] ??
                    value['name'],
              ) ??
              '',
          _nullableText(
            value['configValue'] ??
                value['keyValue'] ??
                value['value'] ??
                value['content'],
          ),
        );
        value.forEach((key, item) {
          if (item is Map || item is List) {
            walk(item);
          } else {
            register(key.toString(), _nullableText(item));
          }
        });
      } else if (value is List) {
        for (final item in value) {
          walk(item);
        }
      }
    }

    walk(await _client.getJson('/Client/Basic/getBasicData'));
    return BackendBasicData(flattened);
  }

  @override
  Future<List<BackendFaq>> getFaqs({
    String keyword = '',
    String broadcastId = '',
  }) async =>
      extractApiRows(
            await _client.getJson(
              AppBackendRepository.faqListPath,
              query: <String, Object?>{
                'pageIndex': 1,
                'pageSize': 50,
                if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
                if (broadcastId.trim().isNotEmpty)
                  'broadcastId': broadcastId.trim(),
              },
            ),
          )
          .map(_faq)
          .where((item) => item.question.isNotEmpty)
          .toList(growable: false);

  @override
  Future<BackendFaq?> getFaqDetail(int faqId) async {
    final data = await _client.getJson(
      '/Client/Product/getProductFaqDetail',
      query: <String, Object?>{'faqId': faqId},
    );
    if (data is! Map) return null;
    final faq = _faq(_map(data));
    return faq.question.isEmpty && faq.answer.isEmpty ? null : faq;
  }

  @override
  Future<String> uploadFile(String filePath) async {
    final url = _uploadedUrl(
      await _client.upload(
        '/Client/Basic/setFileUpload',
        filePaths: <String>[filePath],
      ),
    );
    if (url == null) {
      throw const ApiException('UPLOAD_URL_MISSING', '文件已上传，但接口没有返回访问地址');
    }
    return url;
  }

  @override
  Future<void> editUserProduct({
    required int userProductId,
    required String productName,
    int? productId,
    bool clearImages = false,
  }) async {
    await _client.postJson(
      '/Client/UserProduct/editUserProduct',
      retryTransportErrors: false,
      body: <String, Object?>{
        'userProductId': userProductId,
        'productName': productName,
        'productId': ?productId,
        'isClearImg': clearImages ? 1 : 0,
      },
    );
  }

  @override
  Future<List<BackendAnniversary>> getAnniversaries(String deviceId) async =>
      extractApiRows(
            await _client.getJson(
              '/Client/UserProduct/getProductAnniversaryList',
              query: <String, Object?>{
                'pageIndex': 1,
                'pageSize': 100,
                'deviceId': deviceId,
              },
            ),
          )
          .map(_anniversary)
          .where(
            (item) =>
                item.anniversaryId > 0 &&
                // swagger 的列表入参里没有设备过滤（只有分页、关键词、日期），
                // 返回行却带 deviceId：账号下几台花盆的纪念日会一起回来，所以
                // `deviceId` 照带、这里再按返回行滤一次。返回体没带这个字段时
                // 按「就是这台设备的」处理，否则会把整份列表滤空。
                (item.deviceId.isEmpty || item.deviceId == deviceId),
          )
          .toList(growable: false);

  @override
  Future<BackendAnniversary?> getAnniversaryDetail(int anniversaryId) async {
    final data = await _client.getJson(
      '/Client/UserProduct/getProductAnniversaryDetail',
      query: <String, Object?>{'id': anniversaryId},
    );
    if (data is! Map) return null;
    final entry = _anniversary(_map(data));
    return entry.anniversaryId > 0 ? entry : null;
  }

  @override
  Future<int> addAnniversary({
    required String deviceId,
    required String title,
    required String content,
    required bool imageContent,
    required DateTime date,
  }) async {
    final id = _newAnniversaryId(
      await _client.postJson(
        '/Client/UserProduct/addUserProductAnniversary',
        retryTransportErrors: false,
        body: _anniversaryBody(
          deviceId: deviceId,
          title: title,
          content: content,
          imageContent: imageContent,
          date: date,
        ),
      ),
    );
    if (id > 0) return id;
    // 新增接口没有 swagger 模型，返回体里不一定带 id。DP 154 的帧必须带 id，
    // 拿不到就回列表里按标题 + 日期找回刚写进去的那条，取 id 最大的一条。
    final candidates = (await getAnniversaries(deviceId))
        .where(
          (row) => row.title == title && _isoDate(row.date) == _isoDate(date),
        )
        .map((row) => row.anniversaryId)
        .toList(growable: false);
    if (candidates.isEmpty) {
      throw const ApiException('ANNIVERSARY_ID_MISSING', '纪念日已保存，但接口没有返回记录 id');
    }
    return candidates.reduce(max);
  }

  @override
  Future<void> editAnniversary({
    required int anniversaryId,
    required String deviceId,
    required String title,
    required String content,
    required bool imageContent,
    required DateTime date,
  }) async {
    await _client.postJson(
      '/Client/UserProduct/editUserProductAnniversary',
      retryTransportErrors: false,
      body: <String, Object?>{
        'anniversaryId': anniversaryId,
        ..._anniversaryBody(
          deviceId: deviceId,
          title: title,
          content: content,
          imageContent: imageContent,
          date: date,
        ),
      },
    );
  }

  @override
  Future<void> setAnniversaryEnabled(
    List<int> anniversaryIds,
    bool enabled,
  ) async {
    if (anniversaryIds.isEmpty) return;
    await _client.postJson(
      '/Client/UserProduct/setUserProductAnniversaryVerify',
      retryTransportErrors: false,
      body: <String, Object?>{
        'commonIds': anniversaryIds.join(','),
        'verify': enabled ? 1 : 0,
      },
    );
  }

  @override
  Future<void> deleteAnniversary(int anniversaryId) async {
    await _client.postJson(
      '/Client/UserProduct/deleteUserProductAnniversary',
      retryTransportErrors: false,
      body: <String, Object?>{'id': anniversaryId},
    );
  }

  /// 新增与编辑共用 `ClientProductAnniversaryAddApiIn`；编辑时调用方再补
  /// `anniversaryId`。`terminal` / `language` / `userToken` 由 [ApiClient] 走
  /// headers 与公共 query 带上，不进 body（`device` 手机机型全站都没传）。
  static Map<String, Object?> _anniversaryBody({
    required String deviceId,
    required String title,
    required String content,
    required bool imageContent,
    required DateTime date,
  }) => <String, Object?>{
    'deviceId': deviceId,
    'title': title,
    'content': content,
    'contentType': imageContent ? 1 : 0,
    'anniversaryDate': _isoDate(date),
  };

  static BackendUserInfo _userInfo(Map<String, dynamic> row) => BackendUserInfo(
    nickname: _text(row, 'nickName', fallback: _text(row, 'nickname')),
    account: _text(
      row,
      'userMobile',
      fallback: _text(row, 'mobile', fallback: _text(row, 'userEmail')),
    ),
    avatarUrl: _nullableText(
      row['avatar'] ?? row['avatarUrl'] ?? row['headImg'],
    ),
    email: _text(row, 'userEmail', fallback: _text(row, 'email')),
    userNo: _text(row, 'userNo'),
  );

  static BackendFaq _faq(Map<String, dynamic> row) => BackendFaq(
    faqId: _integer(row['faqId'] ?? row['productFaqId'] ?? row['id']),
    question: _text(
      row,
      'title',
      fallback: _text(row, 'question', fallback: _text(row, 'faqTitle')),
    ),
    answer: _text(
      row,
      'content',
      fallback: _text(row, 'answer', fallback: _text(row, 'faqContent')),
    ),
  );

  static BackendAnniversary _anniversary(Map<String, dynamic> row) {
    final verify =
        row['isVerify'] ?? row['verify'] ?? row['isEnable'] ?? row['status'];
    return BackendAnniversary(
      anniversaryId: _integer(
        row['anniversaryId'] ?? row['userProductAnniversaryId'] ?? row['id'],
      ),
      deviceId: _text(row, 'deviceId'),
      title: _text(row, 'title'),
      content: _text(row, 'content'),
      imageContent: _integer(row['contentType']) == 1,
      date: _date(_text(row, 'anniversaryDate')),
      // 字段缺失按启用处理：禁用是用户的显式操作，认不出来时不该把设备上正在
      // 显示的一条画成「已停用」。
      enabled: verify == null ? true : _boolean(verify),
    );
  }

  static int _newAnniversaryId(Object? data) {
    if (data is num) return data.round();
    if (data is String) return int.tryParse(data.trim()) ?? 0;
    if (data is Map) {
      final row = data.map((key, value) => MapEntry(key.toString(), value));
      return _integer(
        row['anniversaryId'] ??
            row['userProductAnniversaryId'] ??
            row['id'] ??
            row['commonId'],
      );
    }
    return 0;
  }

  static String? _uploadedUrl(Object? data) {
    if (data is String) return _nullableText(data);
    if (data is List) {
      for (final item in data) {
        final url = _uploadedUrl(item);
        if (url != null) return url;
      }
      return null;
    }
    if (data is Map) {
      final row = data.map((key, value) => MapEntry(key.toString(), value));
      for (final key in const <String>[
        'url',
        'fileUrl',
        'filePath',
        'imgUrl',
        'img',
        'fullPath',
        'path',
        'avatar',
      ]) {
        final value = _nullableText(row[key]);
        if (value != null) return value;
      }
      for (final item in extractApiRows(row)) {
        final url = _uploadedUrl(item);
        if (url != null) return url;
      }
    }
    return null;
  }

  static String _isoDate(DateTime? date) {
    if (date == null) return '';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static DateTime? _date(String value) {
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value.trim().replaceFirst(' ', 'T'));
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static List<String> _lines(String value) => value
      .split(RegExp(r'[\r\n;；]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  /// 后端把「验证码错误」和「账号不存在」都压在 `retCode` 403 上，只有文案能区分；
  /// 而且未注册手机号目前返回的是海外邮箱那套「邮箱不存在」。所以这里只认 403，
  /// 并把文案匹配放宽到「不存在 / 未注册」；后端换了文案，验证码登录会退回直接
  /// 报错，而不是把「验证码错误」误判成未注册去重复注册。
  static bool _isAccountMissing(ApiException error) =>
      error.code == 403 && _accountMissingPattern.hasMatch(error.message);

  static final RegExp _accountMissingPattern = RegExp(
    '不存在|未注册|not exist|not registered',
    caseSensitive: false,
  );

  /// 验证码登录没有让用户设密码这一步，但注册接口要求密码，所以自动注册时生成
  /// 一条随机密码占位。用户之后要用密码登录，得走「忘记密码」重设。
  static String _generatedPassword() {
    const alphabet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static String _md5(String input) =>
      md5.convert(utf8.encode(input)).toString();

  static BackendProduct _product(Map<String, dynamic> row) => BackendProduct(
    productId: _integer(row['productId']),
    productName: _text(row, 'productName', fallback: '智能花盆'),
    broadcastId: _text(row, 'broadcastId'),
  );

  static BackendUserProduct _userProduct(Map<String, dynamic> row) =>
      BackendUserProduct(
        userProductId: _integer(row['userProductId']),
        productId: _nullableInteger(row['productId']),
        deviceId: _text(row, 'deviceId'),
        productName: _text(row, 'productName', fallback: '智能花盆'),
        deleted: _boolean(row['isDel']),
      );

  static PlantProfile _plant(Map<String, dynamic> row) {
    final productPlantId = _integer(row['productPlantId']);
    final reported = _text(
      row,
      'tuYaRemark',
      fallback: _text(row, 'tuyaRemark'),
    );
    final identifier = reported;
    final name = _text(row, 'plantName', fallback: '未命名植物');
    final scientificName = _text(
      row,
      'scientificName',
      fallback: '',
    );
    final care = _text(row, 'careInstructions');
    final introduction = _text(row, 'introduction');
    return PlantProfile(
      id: reported.isNotEmpty
          ? reported
          : productPlantId > 0
          ? 'product_plant_$productPlantId'
          : name,
      name: name,
      latinName: scientificName,
      color: const Color(0xFF4D8B55),
      moistureTarget: 0,
      lightTarget: 0,
      tip: introduction.isNotEmpty
          ? introduction
          : care.isNotEmpty
          ? care
          : '',
      productPlantId: productPlantId > 0 ? productPlantId : null,
      userProductPlantId: _nullableInteger(row['userProductPlantId']),
      tuyaIdentifier: identifier,
      imageUrl: _nullableText(row['plantImg']),
      alias: _text(row, 'alias'),
      introduction: introduction,
      temperatureRequirement: _text(row, 'optimalTemperature'),
      humidityRequirement: _text(row, 'optimalHumidity'),
      // ⚠️ **优先取 `…Msg`**（2026-09-11 真实返回体确认）：后端这一项是**枚举数字**
      // （`lightingRequirements: 1`），人话在配套的 `lightingRequirementsMsg`
      // （`"全日照"`）里。改之前直接 `_text` 取数字字段，界面上画出来就是个「1」。
      // 没有 Msg 时才退回原值，老接口仍然能用。
      lightingRequirement: _text(
        row,
        'lightingRequirementsMsg',
        fallback: _text(row, 'lightingRequirements'),
      ),
      wateringFrequency: _text(row, 'wateringFrequency'),
      growthCharacteristics: _text(row, 'growthCharacteristics'),
      careInstructions: care,
      lightingSuggestion: _text(row, 'lightingSuggestions'),
      waterSuggestion: _text(row, 'waterSuggestion'),
      temperatureSuggestion: _text(row, 'temperatureSuggestion'),
      humiditySuggestion: _text(row, 'humiditySuggestion'),
      difficultyMaintenance: _nullableInteger(row['difficultyMaintenance']),
      // 2026-09-08 后端确认植物分类的字段名是 `categoryType`（1 水培 / 2 适中 /
      // 3 耐旱），此前那串 plantType/plantTypeId/plantCategory/categoryId 都是
      // 字段名未定时的猜测，已删。取不到就只下发 DP 116、不猜分类，见
      // `FlowerpotState._publishPlantSelection`。
      plantType: _nullableInteger(row['categoryType']),
    );
  }

  static BackendImage _image(Map<String, dynamic> row) {
    final url = _text(row, 'img');
    // 和 DP 142 下发时带的文件名同一种取法，删除（155）/ 置顶（157）才对得上。
    final pathName = BackendImage.fileNameOf(url);
    return BackendImage(
      id: _integer(row['uProductImgId'] ?? row['uproductImgId']),
      userProductId: _integer(row['userProductId']),
      name: pathName.isNotEmpty
          ? pathName
          : _text(row, 'productName', fallback: '设备图片'),
      url: url,
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const ApiException('PARSE_ERROR', '服务器返回的数据格式不正确');
    }
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static String _text(
    Map<String, dynamic> row,
    String key, {
    String fallback = '',
  }) {
    final value = row[key]?.toString().trim();
    return value == null || value.isEmpty || value == 'null' ? fallback : value;
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'null' ? null : text;
  }

  static int _integer(Object? value) => _nullableInteger(value) ?? 0;

  static int? _nullableInteger(Object? value) => switch (value) {
    int number => number,
    num number => number.round(),
    String text => int.tryParse(text),
    _ => null,
  };

  static bool _boolean(Object? value) => switch (value) {
    true || 1 || '1' || 'true' => true,
    _ => false,
  };
}
