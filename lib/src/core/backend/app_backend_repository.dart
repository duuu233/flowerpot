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
  bool get enabled;
  bool get hasSession;

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

  Future<List<PlantProfile>> getProductPlants({
    required int productId,
    String keyword = '',
  });
  Future<PlantProfile> getPlantDetail(int productPlantId);
  Future<List<PlantProfile>> getUserPlants(int userProductId);
  Future<void> addUserPlant({
    required int userProductId,
    required int productPlantId,
  });
  Future<void> deleteUserPlant(int userProductPlantId);

  Future<List<BackendImage>> getImages(int userProductId);
  Future<void> uploadImage({
    required int userProductId,
    required String filePath,
  });
  Future<void> deleteImages(List<int> imageIds);
}

/// Used when no REST origin was supplied. This preserves the existing
/// Tuya-only and mock flows instead of constructing an invalid HTTP client.
class DisabledAppBackendRepository implements AppBackendRepository {
  const DisabledAppBackendRepository();

  @override
  bool get enabled => false;

  @override
  bool get hasSession => false;

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
  Future<List<PlantProfile>> getProductPlants({
    required int productId,
    String keyword = '',
  }) async => _disabled();

  @override
  Future<PlantProfile> getPlantDetail(int productPlantId) async => _disabled();

  @override
  Future<List<PlantProfile>> getUserPlants(int userProductId) async =>
      _disabled();

  @override
  Future<void> addUserPlant({
    required int userProductId,
    required int productPlantId,
  }) async => _disabled();

  @override
  Future<void> deleteUserPlant(int userProductPlantId) async => _disabled();

  @override
  Future<List<BackendImage>> getImages(int userProductId) async => _disabled();

  @override
  Future<void> uploadImage({
    required int userProductId,
    required String filePath,
  }) async => _disabled();

  @override
  Future<void> deleteImages(List<int> imageIds) async => _disabled();
}

class HttpAppBackendRepository implements AppBackendRepository {
  HttpAppBackendRepository({required ApiClient client})
    : _client = client,
      _session = client.session;

  factory HttpAppBackendRepository.fromEnvironment() =>
      HttpAppBackendRepository(client: ApiClient.fromEnvironment());

  final ApiClient _client;
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
        retryOnTimeout: false,
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
        retryOnTimeout: false,
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
      retryOnTimeout: false,
      body: <String, Object?>{'id': userProductId},
    );
  }

  @override
  Future<List<PlantProfile>> getProductPlants({
    required int productId,
    String keyword = '',
  }) async => extractApiRows(
    await _client.getJson(
      '/Client/Product/getProductPlantList',
      query: <String, Object?>{
        'pageIndex': 1,
        'pageSize': 500,
        'productId': productId,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    ),
  ).map(_plant).toList(growable: false);

  @override
  Future<PlantProfile> getPlantDetail(int productPlantId) async => _plant(
    _map(
      await _client.getJson(
        '/Client/UserProduct/getUserProductPlantDetail',
        query: <String, Object?>{'id': productPlantId},
      ),
    ),
  );

  @override
  Future<List<PlantProfile>> getUserPlants(int userProductId) async =>
      extractApiRows(
            await _client.getJson(
              '/Client/UserProduct/getUserProductPlantList',
              query: <String, Object?>{
                'pageIndex': 1,
                'pageSize': 100,
                'userProductId': userProductId,
              },
            ),
          )
          .where((row) => !_boolean(row['isDel']))
          .map(_plant)
          .toList(growable: false);

  @override
  Future<void> addUserPlant({
    required int userProductId,
    required int productPlantId,
  }) async {
    await _client.postJson(
      '/Client/UserProduct/addUserProductPlant',
      retryOnTimeout: false,
      body: <String, Object?>{
        'userProductId': userProductId,
        'productPlantId': productPlantId,
      },
    );
  }

  @override
  Future<void> deleteUserPlant(int userProductPlantId) async {
    await _client.postJson(
      '/Client/UserProduct/delUserProductPlant',
      retryOnTimeout: false,
      body: <String, Object?>{'id': userProductPlantId},
    );
  }

  @override
  Future<List<BackendImage>> getImages(int userProductId) async =>
      extractApiRows(
        await _client.getJson(
          '/Client/UserProduct/getUserProductImgList',
          query: <String, Object?>{
            'pageIndex': 1,
            'pageSize': 100,
            'userProductId': userProductId,
          },
        ),
      ).map(_image).where((item) => item.id > 0).toList(growable: false);

  @override
  Future<void> uploadImage({
    required int userProductId,
    required String filePath,
  }) async {
    await _client.upload(
      '/Client/Basic/setUserProductUpload',
      filePaths: <String>[filePath],
      query: <String, Object?>{'userProductId': userProductId},
    );
  }

  @override
  Future<void> deleteImages(List<int> imageIds) async {
    if (imageIds.isEmpty) return;
    await _client.postJson(
      '/Client/UserProduct/delUserProductImg',
      retryOnTimeout: false,
      body: <String, Object?>{'idList': imageIds},
    );
  }

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
    final identifier = _text(
      row,
      'tuYaRemark',
      fallback: _text(row, 'tuyaRemark'),
    );
    final name = _text(row, 'plantName', fallback: '未命名植物');
    final fallback =
        PlantCatalog.findByTuyaIdentifier(identifier) ??
        PlantCatalog.items.where((item) => item.name == name).firstOrNull;
    final scientificName = _text(
      row,
      'scientificName',
      fallback: fallback?.latinName ?? '',
    );
    final care = _text(row, 'careInstructions');
    final introduction = _text(row, 'introduction');
    return PlantProfile(
      id: identifier.isNotEmpty
          ? identifier
          : productPlantId > 0
          ? 'product_plant_$productPlantId'
          : name,
      name: name,
      latinName: scientificName,
      color: fallback?.color ?? const Color(0xFF4D8B55),
      moistureTarget: fallback?.moistureTarget ?? 60,
      lightTarget: fallback?.lightTarget ?? 150,
      tip: introduction.isNotEmpty
          ? introduction
          : care.isNotEmpty
          ? care
          : fallback?.tip ?? '请根据植物详情进行日常养护。',
      productPlantId: productPlantId > 0 ? productPlantId : null,
      userProductPlantId: _nullableInteger(row['userProductPlantId']),
      tuyaIdentifier: identifier,
      imageUrl: _nullableText(row['plantImg']),
      alias: _text(row, 'alias'),
      introduction: introduction,
      temperatureRequirement: _text(row, 'optimalTemperature'),
      humidityRequirement: _text(row, 'optimalHumidity'),
      lightingRequirement: _text(row, 'lightingRequirements'),
      wateringFrequency: _text(row, 'wateringFrequency'),
      growthCharacteristics: _text(row, 'growthCharacteristics'),
      careInstructions: care,
      difficultyMaintenance: _nullableInteger(row['difficultyMaintenance']),
    );
  }

  static BackendImage _image(Map<String, dynamic> row) {
    final url = _text(row, 'img');
    final uri = Uri.tryParse(url);
    final pathName = uri == null || uri.pathSegments.isEmpty
        ? ''
        : Uri.decodeComponent(uri.pathSegments.last);
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
