import 'dart:convert';
import 'dart:io';

import 'package:flowerpot/src/core/network/network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('only business 406 can be classified as login invalidation', () {
    expect(const ApiException(406, 'login invalid').isAuthError, isTrue);
    expect(
      const ApiException(406, 'HTTP error', authError: false).isAuthError,
      isFalse,
    );
    for (final code in <Object>[
      401,
      403,
      404,
      500,
      'SESSION_CHANGED',
      'BACKEND_SESSION_REQUIRED',
    ]) {
      expect(ApiException(code, 'error').isAuthError, isFalse);
      expect(ApiException(code, 'error', authError: true).isAuthError, isFalse);
    }
  });

  const cases = <({int status, int? code, bool invalidates})>[
    (status: 200, code: 401, invalidates: false),
    (status: 401, code: null, invalidates: false),
    (status: 401, code: 401, invalidates: false),
    (status: 406, code: 200, invalidates: false),
    (status: 406, code: 401, invalidates: false),
    (status: 200, code: 403, invalidates: false),
    (status: 200, code: 500, invalidates: false),
    (status: 200, code: 406, invalidates: true),
    (status: 401, code: 406, invalidates: true),
    (status: 406, code: 406, invalidates: true),
  ];
  for (final mode in <String>['GET', 'POST', 'upload']) {
    for (final scenario in cases) {
      test(
        '$mode HTTP ${scenario.status}/retCode ${scenario.code} invalidates=${scenario.invalidates}',
        () async {
          final session = ApiSession(storageKey: 'test.session-policy')
            ..setToken('fixture-token');
          var expired = 0;
          var requests = 0;
          final client = ApiClient(
            baseUrl: 'https://example.test',
            session: session,
            onSessionExpired: () => expired++,
            httpClient: MockClient((request) async {
              requests++;
              expect(request.headers['userToken'], 'fixture-token');
              expect(request.url.queryParameters['userToken'], 'fixture-token');
              return http.Response(
                jsonEncode(<String, Object?>{
                  if (scenario.code != null) 'retCode': scenario.code,
                  'retMsg': 'fixture rejection',
                }),
                scenario.status,
                request: request,
              );
            }),
          );
          late Future<Object?> pending;
          if (mode == 'upload') {
            final directory = await Directory.systemTemp.createTemp(
              'flowerpot_session_policy_',
            );
            final file = File('${directory.path}/fixture.jpg');
            await file.writeAsString('fixture image');
            addTearDown(() async {
              await file.delete();
              await directory.delete();
            });
            pending = client.upload(
              '/Client/Basic/setUserProductUpload',
              filePaths: <String>[file.path],
            );
          } else if (mode == 'POST') {
            pending = client.postJson('/Client/User/update');
          } else {
            pending = client.getJson('/Client/User/profile');
          }
          await expectLater(
            pending,
            throwsA(
              isA<ApiException>().having(
                (e) => e.isAuthError,
                'auth error',
                scenario.invalidates,
              ),
            ),
          );
          expect(requests, 1);
          expect(expired, scenario.invalidates ? 1 : 0);
          expect(
            session.userToken,
            scenario.invalidates ? '' : 'fixture-token',
          );
          await session.flush();
          final restored = ApiSession(storageKey: session.storageKey);
          expect(await restored.restore(), !scenario.invalidates);
          expect(
            restored.userToken,
            scenario.invalidates ? '' : 'fixture-token',
          );
        },
      );
    }
  }
}
