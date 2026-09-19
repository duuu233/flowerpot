import 'package:flowerpot/src/core/config/debug_log_gate.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_tuya_repository.dart';

/// 联调日志总闸（2026-09-19：暂时屏蔽调试日志功能，代码不删）。
///
/// 锁两件事：
///   ① **生产默认是关的**——这正是本轮要交付的效果，改回 true 必须是有意为之；
///   ② 关着时 `_logInteraction` 那一路**一条都不记**（不是只藏浮层：只藏界面的话
///      日志还在后台攒，内存白占、`notifyListeners` 白发）。
void main() {
  // flutter_test_config 把它设成了 true（多数用例要验日志内容），这里自己来回切。
  tearDown(DebugLogGate.reset);

  test('生产默认关闭', () {
    DebugLogGate.reset();
    expect(DebugLogGate.interactionLog, isFalse);
  });

  test('关着时一条都不记，翻开就照常记', () {
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);

    DebugLogGate.interactionLog = false;
    state.logPageEntry('测试页');
    expect(state.interactionLog, isEmpty);

    DebugLogGate.interactionLog = true;
    state.logPageEntry('测试页');
    expect(state.interactionLog, hasLength(1));
    expect(state.interactionLog.single, contains('测试页'));
  });
}
