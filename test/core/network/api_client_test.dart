import 'dart:convert';

import 'package:flowerpot/src/core/network/network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('injects the session and unwraps a successful response', () async {
    late http.Request captured;
    final session = ApiSession(storageKey: 'test.api.token')
      ..setToken('secret-token')
      ..setLanguage('en');
    final client = ApiClient(
      baseUrl: 'https://example.test',
      session: session,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'retCode': 200,
            'retMsg': 'ok',
            'retData': <String, Object?>{'id': 7},
          }),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );

    final result = await client.getJson('/Client/User/profile');

    expect(result, <String, Object?>{'id': 7});
    expect(captured.headers['userToken'], 'secret-token');
    expect(captured.headers['authorization'], 'Bearer secret-token');
    expect(captured.url.queryParameters['userToken'], 'secret-token');
    expect(captured.url.queryParameters['language'], '1');
  });

  test('clears the token and reports an expired session', () async {
    var expired = false;
    final session = ApiSession(storageKey: 'test.expired.token')
      ..setToken('expired-token');
    final client = ApiClient(
      baseUrl: 'https://example.test',
      session: session,
      onSessionExpired: () => expired = true,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{'retCode': 406, 'retMsg': 'expired'}),
          200,
        ),
      ),
    );

    await expectLater(
      client.getJson('/Client/User/profile'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.isAuthError,
          'isAuthError',
          isTrue,
        ),
      ),
    );
    expect(session.userToken, isEmpty);
    expect(expired, isTrue);
  });

  test('does not retry a business error', () async {
    var requests = 0;
    final client = ApiClient(
      baseUrl: 'https://example.test',
      networkRetryDelay: Duration.zero,
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(
          jsonEncode(<String, Object?>{
            'retCode': 422,
            'retMsg': 'invalid input',
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.postJson('/Client/User/update'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'invalid input',
        ),
      ),
    );
    expect(requests, 1);
  });
}
