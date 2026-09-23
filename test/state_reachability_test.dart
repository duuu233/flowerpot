import 'package:flowerpot/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_tuya_repository.dart';

/// 被动离线的主动探测（2026-09-23）：路由器断电这类「设备来不及说话」的离线，云端要两个心跳周期
/// 才判（花盆实测约 5 分钟）。App 前台每 20 秒用涂鸦 `requestWifiSignal` 问一次设备，
/// 连续 2 次没回应就本地按离线；再回应就恢复。
void main() {
  testWidgets('设备连续两次没回应 → 按离线；再回应 → 恢复在线', (tester) async {
    final repository = MockTuyaRepository(latency: Duration.zero);
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await state.initialize();
    await state.refreshDevices();
    final id = state.devices.firstWhere((device) => device.online).id;

    // 路由器断了：设备不再回应探测，云端（SDK 缓存）还说在线。
    repository.unreachableDevices.add(id);
    await tester.pump(FlowerpotState.reachProbeInterval);
    await tester.pump();
    expect(state.deviceById(id)!.online, isTrue, reason: '一次没回应不判');

    await tester.pump(FlowerpotState.reachProbeInterval);
    await tester.pump();
    expect(state.deviceById(id)!.online, isFalse);
    expect(state.isUnreachableByProbe(id), isTrue);
    expect(
      state.interactionLog.any((line) => line.contains('按离线处理')),
      isTrue,
    );

    // 网络恢复：设备回应了。
    repository.unreachableDevices.remove(id);
    await tester.pump(FlowerpotState.reachProbeInterval);
    await tester.pump();
    expect(state.deviceById(id)!.online, isTrue);
    expect(state.isUnreachableByProbe(id), isFalse);

    state.pauseDeviceWatch();
  });
}
