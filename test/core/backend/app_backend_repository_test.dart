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

  test('plant catalog maps tuYaRemark to the DP 116 identifier', () async {
    final session = ApiSession(storageKey: 'backend.plants.token')
      ..setToken('api-token');
    final repository = HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/Client/Product/getProductPlantList');
          expect(request.url.queryParameters['productId'], '9');
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

    final plants = await repository.getProductPlants(productId: 9);

    expect(plants, hasLength(1));
    expect(plants.single.productPlantId, 17);
    expect(plants.single.tuyaIdentifier, 'monstera_en');
    expect(plants.single.imageUrl, 'https://cdn.example.test/monstera.png');
    repository.close();
  });
}

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
