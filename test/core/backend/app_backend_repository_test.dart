import 'dart:convert';

import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/core/network/network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('password login hashes the password and stores both sessions', () async {
    late http.Request captured;
    final session = ApiSession(storageKey: 'backend.login.token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient((request) async {
          captured = request;
          return _response(<String, Object?>{
            'userToken': 'api-token',
            'userNo': 'tuya-user',
            'tuYaPwd': 'tuya-password',
            'countryCode': '86',
            'nickName': '植物守护者',
            'userMobile': '13800138000',
          });
        }),
      ),
    );

    final account = await repository.loginWithPassword(
      mobile: '13800138000',
      password: 'password123',
    );
    final body = jsonDecode(captured.body) as Map<String, dynamic>;

    expect(captured.url.path, '/Client/User/userLoginPassword');
    expect(body['userMobile'], '13800138000');
    expect(body['password'], '482c811da5d5b4bc6d497ffa98491e38');
    expect(session.userToken, 'api-token');
    expect(account.tuyaAccount, 'tuya-user');
    expect(account.tuyaPassword, 'tuya-password');
    repository.close();
  });

  test('verification login registers an unknown mobile', () async {
    final requests = <http.Request>[];
    final session = ApiSession(storageKey: 'backend.code-login.token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/Client/User/userLoginVerifyCode') {
            // 后端把「账号不存在」压在 403 上，文案沿用的是海外邮箱那一套。
            return _failure(403, '邮箱不存在');
          }
          return _response(<String, Object?>{
            'userToken': 'api-token',
            'userNo': 'tuya-user',
            'tuYaPwd': 'tuya-password',
            'countryCode': '86',
            'nickName': '植物守护者',
            'userMobile': '13800138000',
          });
        }),
      ),
    );

    final account = await repository.loginWithCode(
      mobile: '13800138000',
      code: '123456',
    );
    final register = jsonDecode(requests.last.body) as Map<String, dynamic>;

    expect(
      requests.map((request) => request.url.path),
      <String>[
        '/Client/User/userLoginVerifyCode',
        '/Client/User/userRegisterMobile',
      ],
    );
    expect(register['userMobile'], '13800138000');
    expect(register['verifyCode'], '123456');
    expect(register['password'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(register['confirmPassword'], register['password']);
    expect(account.registered, isTrue);
    expect(account.tuyaAccount, 'tuya-user');
    expect(session.userToken, 'api-token');
    repository.close();
  });

  test('a wrong verification code is not a missing account', () async {
    final paths = <String>[];
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: ApiSession(storageKey: 'backend.code-error.token'),
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return _failure(403, '验证码错误');
        }),
      ),
    );

    await expectLater(
      repository.loginWithCode(mobile: '13800138000', code: '000000'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '验证码错误',
        ),
      ),
    );

    expect(paths, <String>['/Client/User/userLoginVerifyCode']);
    repository.close();
  });

  test('联调期植物标识写死成 17，行 id 仍按后端值区分', () async {
    final session = ApiSession(storageKey: 'backend.plants.token')
      ..setToken('api-token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/Client/Product/getProductPlantList');
          // 主流程不再先查 getProductList 换 productId，所以这个参数必须不出现。
          expect(request.url.queryParameters.containsKey('productId'), isFalse);
          return _response(<String, Object?>{
            'pageData': <Object?>[
              <String, Object?>{
                'productPlantId': 17,
                'plantName': '龟背竹',
                'scientificName': 'Monstera deliciosa',
                'plantImg': 'https://cdn.example.test/monstera.png',
                'tuYaRemark': 'monstera_en',
              },
            ],
          });
        }),
      ),
    );

    final plants = await repository.getProductPlants();

    expect(plants, hasLength(1));
    expect(plants.single.productPlantId, 17);
    // 后台补完 tuYaRemark、`_debugPlantIdentifier` 改回 null 之后，这里要改回
    // 断言 'monstera_en'。
    expect(plants.single.tuyaIdentifier, '17');
    expect(plants.single.id, 'monstera_en');
    expect(plants.single.imageUrl, 'https://cdn.example.test/monstera.png');
    repository.close();
  });

  test('anniversary list keeps only the requested device', () async {
    final session = ApiSession(storageKey: 'backend.anniversary.token')
      ..setToken('api-token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient((request) async {
          expect(
            request.url.path,
            '/Client/UserProduct/getProductAnniversaryList',
          );
          expect(request.url.queryParameters['userProductId'], '5');
          return _response(<String, Object?>{
            'pageData': <Object?>[
              <String, Object?>{
                'anniversaryId': 42,
                'userProductId': 5,
                'title': '相识纪念日',
                'content': '第一次见面',
                'contentType': 0,
                'anniversaryDate': '2026-09-02',
                'isVerify': 1,
              },
              // 过滤参数是后加的，旧版本会把别的设备也一起返回。
              <String, Object?>{
                'anniversaryId': 43,
                'userProductId': 6,
                'title': '别的设备',
                'content': '不该出现',
                'contentType': 0,
                'anniversaryDate': '2026-09-03',
                'isVerify': 0,
              },
            ],
          });
        }),
      ),
    );

    final rows = await repository.getAnniversaries(5);

    expect(rows, hasLength(1));
    expect(rows.single.anniversaryId, 42);
    expect(rows.single.title, '相识纪念日');
    expect(rows.single.imageContent, isFalse);
    expect(rows.single.date, DateTime(2026, 9, 2));
    expect(rows.single.enabled, isTrue);
    repository.close();
  });

  test('adding an anniversary sends the API shape and returns the id', () async {
    late http.Request captured;
    final session = ApiSession(storageKey: 'backend.anniversary-add.token')
      ..setToken('api-token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient((request) async {
          captured = request;
          return _response(<String, Object?>{'anniversaryId': 77});
        }),
      ),
    );

    final id = await repository.addAnniversary(
      userProductId: 5,
      title: '相识纪念日',
      content: 'https://cdn.example.test/day.png',
      imageContent: true,
      date: DateTime(2026, 9, 2),
    );
    final body = jsonDecode(captured.body) as Map<String, dynamic>;

    expect(
      captured.url.path,
      '/Client/UserProduct/addUserProductAnniversary',
    );
    expect(body['userProductId'], 5);
    expect(body['title'], '相识纪念日');
    // 后端的 contentType 是 0=文字/1=图片，和 DP 154 的 1/2 不是一套编码。
    expect(body['contentType'], 1);
    expect(body['anniversaryDate'], '2026-09-02');
    expect(id, 77);
    repository.close();
  });

  test('adding an anniversary recovers the id from the list', () async {
    final paths = <String>[];
    final session = ApiSession(storageKey: 'backend.anniversary-recover.token')
      ..setToken('api-token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('addUserProductAnniversary')) {
            // 新增接口没有 swagger 模型，返回体里不一定带 id。
            return _response(null);
          }
          return _response(<String, Object?>{
            'pageData': <Object?>[
              <String, Object?>{
                'anniversaryId': 91,
                'userProductId': 5,
                'title': '相识纪念日',
                'content': '第一次见面',
                'contentType': 0,
                'anniversaryDate': '2026-09-02',
              },
            ],
          });
        }),
      ),
    );

    final id = await repository.addAnniversary(
      userProductId: 5,
      title: '相识纪念日',
      content: '第一次见面',
      imageContent: false,
      date: DateTime(2026, 9, 2),
    );

    expect(id, 91);
    expect(paths, <String>[
      '/Client/UserProduct/addUserProductAnniversary',
      '/Client/UserProduct/getProductAnniversaryList',
    ]);
    repository.close();
  });

  test('anniversary enable/disable posts the comma separated ids', () async {
    late http.Request captured;
    final session = ApiSession(storageKey: 'backend.anniversary-verify.token')
      ..setToken('api-token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient((request) async {
          captured = request;
          return _response(null);
        }),
      ),
    );

    await repository.setAnniversaryEnabled(<int>[42, 43], false);
    final body = jsonDecode(captured.body) as Map<String, dynamic>;

    expect(
      captured.url.path,
      '/Client/UserProduct/setUserProductAnniversaryVerify',
    );
    expect(body['commonIds'], '42,43');
    expect(body['verify'], 0);
    repository.close();
  });
}

http.Response _failure(int code, String message) => http.Response(
  jsonEncode(<String, Object?>{
    'retCode': code,
    'retMsg': message,
    'retData': null,
  }),
  200,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

http.Response _response(Object? data) => http.Response(
  jsonEncode(<String, Object?>{
    'retCode': 200,
    'retMsg': 'ok',
    'retData': data,
  }),
  200,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);
