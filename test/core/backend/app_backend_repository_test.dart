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

  test('基础数据：deviceIdList（字符串数组）单独解析出来，平台邮箱照常可取', () async {
    final session = ApiSession(storageKey: 'backend.basic.token')
      ..setToken('api-token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient(
          (_) async => _response(<String, Object?>{
            'deviceIdList': <String>['yciq4kssu1fv8umn', 'other-id'],
            'platformEmail': 'service@example.test',
          }),
        ),
      ),
    );

    final data = await repository.getBasicData();

    // 拍平只收标量，字符串数组以前整个被丢掉——帮助中心就拿不到产品 ID。
    expect(data.deviceIdList, <String>['yciq4kssu1fv8umn', 'other-id']);
    expect(data.values['platformemail'], 'service@example.test');
    // 「我的」页意见反馈读的就是这个（2026-09-21 以前只认 serviceEmail 等猜的键名，一直是空的）。
    expect(data.platformEmail, 'service@example.test');
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

  test('植物标识使用后端 tuYaRemark', () async {
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
    expect(plants.single.tuyaIdentifier, 'monstera_en');
    expect(plants.single.id, 'monstera_en');
    expect(plants.single.imageUrl, 'https://cdn.example.test/monstera.png');
    repository.close();
  });

  test('设备图库按涂鸦 deviceId 查，不再换 userProductId', () async {
    final session = ApiSession(storageKey: 'backend.images.token')
      ..setToken('api-token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/Client/UserProduct/getUserProductImgList');
          expect(
            request.url.queryParameters['deviceId'],
            'vdevo17235508413621',
          );
          // userProduct 那条前置链路已经删掉，这个参数不该再出现。
          expect(
            request.url.queryParameters.containsKey('userProductId'),
            isFalse,
          );
          return _response(<String, Object?>{
            'pageData': <Object?>[
              <String, Object?>{
                'uProductImgId': 31,
                'img': 'https://cdn.example.test/first.gif',
              },
            ],
          });
        }),
      ),
    );

    final images = await repository.getImages('vdevo17235508413621');

    expect(images, hasLength(1));
    expect(images.single.id, 31);
    expect(images.single.name, 'first.gif');
    expect(images.single.url, 'https://cdn.example.test/first.gif');
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
          expect(request.url.queryParameters['deviceId'], 'tuya-5');
          // 纪念日整组按涂鸦 deviceId 走，不能再出现后端的 userProductId。
          expect(
            request.url.queryParameters.containsKey('userProductId'),
            isFalse,
          );
          return _response(<String, Object?>{
            'pageData': <Object?>[
              <String, Object?>{
                'anniversaryId': 42,
                'deviceId': 'tuya-5',
                'title': '相识纪念日',
                'content': '第一次见面',
                'contentType': 0,
                'anniversaryDate': '2026-09-02',
                'isVerify': 1,
              },
              // swagger 的列表入参没有设备过滤，账号下别的花盆也会一起返回。
              <String, Object?>{
                'anniversaryId': 43,
                'deviceId': 'tuya-6',
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

    final rows = await repository.getAnniversaries('tuya-5');

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
      deviceId: 'tuya-5',
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
    // swagger `ClientProductAnniversaryAddApiIn`：设备按涂鸦 deviceId 关联。
    expect(body['deviceId'], 'tuya-5');
    expect(body.containsKey('userProductId'), isFalse);
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
                'deviceId': 'tuya-5',
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
      deviceId: 'tuya-5',
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

  test('editing an anniversary sends the id with the deviceId body', () async {
    late http.Request captured;
    final session = ApiSession(storageKey: 'backend.anniversary-edit.token')
      ..setToken('api-token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient((request) async {
          captured = request;
          return _response(true);
        }),
      ),
    );

    await repository.editAnniversary(
      anniversaryId: 42,
      deviceId: 'tuya-5',
      title: '相识纪念日',
      content: '第一次见面',
      imageContent: false,
      date: DateTime(2026, 9, 2),
    );
    final body = jsonDecode(captured.body) as Map<String, dynamic>;

    expect(
      captured.url.path,
      '/Client/UserProduct/editUserProductAnniversary',
    );
    expect(body['anniversaryId'], 42);
    expect(body['deviceId'], 'tuya-5');
    expect(body.containsKey('userProductId'), isFalse);
    expect(body['contentType'], 0);
    expect(body['anniversaryDate'], '2026-09-02');
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
