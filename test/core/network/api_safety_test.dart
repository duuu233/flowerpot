import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flowerpot/src/core/network/network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  for (final failure in <Exception>[
    TimeoutException('response lost'), http.ClientException('response lost'),
    const SocketException('response lost'),
  ]) {
    test('a committed POST is not repeated after ${failure.runtimeType}', () async {
      var mutations = 0;
      final client = ApiClient(baseUrl: 'https://example.test',
        networkRetryDelay: Duration.zero,
        httpClient: MockClient((_) async { mutations++; throw failure; }));
      await expectLater(client.postJson('/Client/User/update'), throwsA(isA<ApiException>()));
      expect(mutations, 1);
    });
  }
  test('GET still retries transient transport errors', () async {
    var calls = 0;
    final client = ApiClient(baseUrl: 'https://example.test',
      networkRetryDelay: Duration.zero,
      httpClient: MockClient((_) async {
        if (++calls < 3) throw http.ClientException('offline');
        return http.Response('{"retCode":200,"retData":7}', 200);
      }));
    expect(await client.getJson('/Client/User/profile'), 7);
    expect(calls, 3);
  });
  for (final responseCode in <int>[200, 401, 406]) {
    test('late $responseCode response cannot affect a replacement session', () async {
      final session = ApiSession()..setToken('old');
      final response = Completer<http.Response>();
      var expired = 0;
      final client = ApiClient(baseUrl: 'https://example.test', session: session,
        onSessionExpired: () => expired++, httpClient: MockClient((_) => response.future));
      final pending = expectLater(client.getJson('/Client/User/profile'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED')
          .having((e) => e.isAuthError, 'auth error', false)));
      session.setToken('new');
      response.complete(http.Response(jsonEncode({'retCode': responseCode}), 200));
      await pending;
      expect(session.userToken, 'new');
      expect(expired, 0);
    });
  }
  test('session changes stop GET retry before a second request', () async {
    final session = ApiSession()..setToken('old');
    var calls = 0;
    final client = ApiClient(baseUrl: 'https://example.test', session: session,
      networkRetryDelay: Duration.zero, httpClient: MockClient((request) async {
        calls++;
        expect(request.headers['userToken'], 'old');
        session.setToken('new');
        throw http.ClientException('lost');
      }));
    await expectLater(client.getJson('/Client/User/profile'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED')));
    expect(calls, 1);
  });
  test('only HTTPS API origins are accepted', () {
    expect(ApiConfig.baseUrl, 'https://api.yikaltd.com');
    expect(ApiConfig.validateBaseUrl(' https://example.test/ '), 'https://example.test');
    for (final invalid in ['', 'none', 'http://example.test',
      'https://example.test/swagger-ui.html#/', 'https://user:pass@example.test',
      'https://example.test?token=value']) {
      expect(() => ApiConfig.validateBaseUrl(invalid), throwsArgumentError);
    }
  });
}
