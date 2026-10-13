import 'dart:convert';
import 'dart:io';

import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/core/network/network.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mock_tuya_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  const cases = <({int status, int code, bool invalidates})>[
    (status: 200, code: 401, invalidates: false),
    (status: 401, code: 401, invalidates: false),
    (status: 406, code: 200, invalidates: false),
    (status: 200, code: 403, invalidates: false),
    (status: 200, code: 500, invalidates: false),
    (status: 200, code: 406, invalidates: true),
    (status: 401, code: 406, invalidates: true),
  ];
  for (final scenario in cases) {
    test(
      'animation retry after HTTP ${scenario.status}/retCode ${scenario.code}',
      () async {
        final session = ApiSession(storageKey: 'test.animation-policy');
        var uploads = 0;
        var failed = true;
        final backend = HttpAppBackendRepository(
          client: ApiClient(
            baseUrl: 'https://example.test',
            session: session,
            httpClient: MockClient((request) async {
              final path = request.url.path;
              Object data = <String, Object>{'pageData': [], 'recordCount': 0};
              if (path.endsWith('/userLoginPassword')) {
                data = <String, Object>{
                  'userToken': 'fixture-token',
                  'userNo': 'fixture-user',
                  'tuYaPwd': 'fixture-password',
                  'userMobile': '13800138000',
                };
              } else if (path.endsWith('/setUserProductUpload')) {
                uploads++;
                expect(request.headers['userToken'], 'fixture-token');
                expect(
                  request.url.queryParameters['userToken'],
                  'fixture-token',
                );
                if (failed) {
                  return http.Response(
                    jsonEncode({
                      'retCode': scenario.code,
                      'retMsg': 'fixture rejection',
                    }),
                    scenario.status,
                    request: request,
                  );
                }
                data = <String, Object>{
                  'url': 'https://example.test/fixture.jpg',
                };
              }
              return http.Response(
                jsonEncode({'retCode': 200, 'retData': data}),
                200,
                request: request,
              );
            }),
          ),
        );
        final state = FlowerpotState(
          repository: MockTuyaRepository(latency: Duration.zero),
          backendRepository: backend,
        );
        addTearDown(state.dispose);
        await state.initialize();
        expect(
          (await state.login(
            account: '13800138000',
            credential: 'fixture-password',
            region: LoginRegion.domestic,
            verificationCode: false,
          )).success,
          isTrue,
        );
        final directory = await Directory.systemTemp.createTemp(
          'flowerpot_animation_policy_',
        );
        final file = File('${directory.path}/fixture.jpg');
        await file.writeAsString('fixture image');
        addTearDown(() async {
          await file.delete();
          await directory.delete();
        });
        final id = state.devices.single.id;
        final first = await state.addAnimation(
          id,
          name: 'fixture.jpg',
          path: file.path,
        );
        expect(first.success, isFalse);
        expect(backend.hasSession, !scenario.invalidates);
        expect(state.authenticated, isTrue, reason: '涂鸦会话不随 APP 业务错误清除');
        failed = false;
        final retry = await state.addAnimation(
          id,
          name: 'fixture.jpg',
          path: file.path,
        );
        if (scenario.invalidates) {
          expect(retry.code, 'BACKEND_SESSION_REQUIRED');
          expect(uploads, 1);
        } else {
          expect(retry.success, isTrue, reason: '普通错误后可以用原 Token 再次上传');
          expect(uploads, 2);
          expect(session.userToken, 'fixture-token');
        }
      },
    );
  }
}
