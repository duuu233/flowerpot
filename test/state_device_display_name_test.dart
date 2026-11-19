import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_tuya_repository.dart';

/// 设备显示名（2026-11-19 产品：按手机系统语言动态显示）：本机改过名显示自定义名，
/// 否则按产品 ID 现查的涂鸦产品名，查不到才用涂鸦设备名。
void main() {
  Future<FlowerpotState> login(MockTuyaRepository repository) async {
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await state.initialize();
    final result = await state.login(
      account: '13800000000',
      credential: '8888',
      region: LoginRegion.domestic,
      verificationCode: true,
    );
    expect(result.success, isTrue);
    state.pauseDeviceWatch();
    // 产品名是设备清单回来后异步现问的。
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return state;
  }

  test('没改过名：显示按产品 ID 现查的涂鸦产品名，不用激活时存下的设备名', () async {
    final repository = MockTuyaRepository(latency: Duration.zero)
      ..productName = '花盆test';
    final state = await login(repository);
    final device = state.devices.first;

    expect(device.name, isNot('花盆test'));
    expect(state.deviceDisplayName(device), '花盆test');
    expect(state.deviceDisplayNameOf(device.id), '花盆test');
  });

  test('产品名查不到：退回涂鸦设备名', () async {
    final repository = MockTuyaRepository(latency: Duration.zero)
      ..productName = '';
    final state = await login(repository);
    final device = state.devices.first;

    expect(state.deviceDisplayName(device), device.name);
  });

  test('本机改过名：显示自定义名，重新登录后仍认得', () async {
    final repository = MockTuyaRepository(latency: Duration.zero)
      ..productName = '花盆test';
    final state = await login(repository);
    final id = state.devices.first.id;

    final result = await state.renameDevice(id, '阳台花盆');
    expect(result.success, isTrue);
    expect(state.deviceDisplayNameOf(id), '阳台花盆');

    // 同一账号重新进来：本机记录读回，涂鸦设备名也还是改后的名字。
    await Future<void>.delayed(Duration.zero);
    final again = await login(repository);
    expect(again.deviceDisplayNameOf(id), '阳台花盆');
  });
}
