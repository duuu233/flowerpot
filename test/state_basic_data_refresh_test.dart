import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/core/network/network.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_tuya_repository.dart';

/// 后台基础数据（2026-09-21 产品：「我的」页意见反馈要读后台配置的邮箱）：
/// 默认拉到一次就复用；「我的」页进来带 `refresh: true`，后台改了邮箱不用重启 App。
void main() {
  test('默认复用已拉到的那份；refresh 重新拉，平台邮箱跟着后台变', () async {
    final backend = _BasicDataBackend(<String>['a@b.test', 'new@b.test']);
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
      backendRepository: backend,
    );
    addTearDown(state.dispose);

    await state.loadBasicData();
    await state.loadBasicData();
    expect(backend.calls, 1);
    expect(state.basicData.platformEmail, 'a@b.test');

    await state.loadBasicData(refresh: true);
    expect(backend.calls, 2);
    expect(state.basicData.platformEmail, 'new@b.test');
  });

  test('refresh 拉失败时保留旧的那份，邮箱不会被清掉', () async {
    final backend = _BasicDataBackend(<String>['a@b.test']);
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
      backendRepository: backend,
    );
    addTearDown(state.dispose);

    await state.loadBasicData();
    backend.fails = true;
    await state.loadBasicData(refresh: true);

    expect(backend.calls, 2);
    expect(state.basicData.platformEmail, 'a@b.test');
  });
}

class _BasicDataBackend extends DisabledAppBackendRepository {
  _BasicDataBackend(this.emails);

  /// 第 n 次调用返回第 n 个邮箱，超出就一直用最后一个。
  final List<String> emails;
  bool fails = false;
  int calls = 0;

  @override
  bool get enabled => true;

  @override
  bool get hasSession => true;

  @override
  Future<BackendBasicData> getBasicData() async {
    calls++;
    if (fails) throw const ApiException(500, '服务器错误');
    final email = emails[(calls - 1).clamp(0, emails.length - 1)];
    return BackendBasicData(<String, String>{'platformemail': email});
  }
}
