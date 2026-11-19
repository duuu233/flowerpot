import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/core/config/debug_log_gate.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/interaction_log_panel.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mock_tuya_repository.dart';

/// 联调日志排版与设备列表快照（2026-11-19）。
void main() {
  group('InteractionLogEntry.parse', () {
    test('多行日志：首行当标题，其余原样当明细（保留缩进）', () {
      final entry = InteractionLogEntry.parse(
        '10:20:30 设备列表快照 · 共 1 台\n  平台：iOS\n\n[1] 页面显示名称：「A」\n    产品 ID：x\n',
      );
      expect(entry.time, '10:20:30');
      expect(entry.title, '设备列表快照 · 共 1 台');
      expect(entry.details, <String>[
        '  平台：iOS',
        '',
        '[1] 页面显示名称：「A」',
        '    产品 ID：x',
      ]);
      expect(
        entry.copyText,
        '10:20:30 设备列表快照 · 共 1 台\n  平台：iOS\n\n[1] 页面显示名称：「A」\n    产品 ID：x',
      );
    });

    test('单行用「；」或「 · 」串起来的拆成一段一行', () {
      final entry = InteractionLogEntry.parse(
        '08:00:01 蓝牙 ✓ 已连上：uuid=1；尝试 1 次 · 来源 SDK',
      );
      expect(entry.title, '蓝牙 ✓ 已连上：uuid=1');
      expect(entry.details, <String>['  尝试 1 次', '  来源 SDK']);
    });

    test('普通单行不拆；没有时间前缀也能解析', () {
      final entry = InteractionLogEntry.parse('下发 → DP117 true');
      expect(entry.time, isEmpty);
      expect(entry.title, '下发 → DP117 true');
      expect(entry.details, isEmpty);
      expect(entry.copyText, '下发 → DP117 true');
    });
  });

  test('设备列表加载后打一份快照：显示名、名称来源、按产品 ID 查到的产品名、不一致标记', () async {
    final repository = MockTuyaRepository(latency: Duration.zero)
      ..productName = 'YUSEN-智能花盆';
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
    // 产品名是设备清单回来后异步现问的，问完才打快照。
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final snapshot = state.interactionLog.lastWhere(
      (line) => line.contains('设备列表快照'),
    );
    final device = state.devices.first;
    expect(snapshot, contains('共 ${state.devices.length} 台'));
    expect(snapshot, contains('手机系统语言：'));
    expect(snapshot, contains('[1] 页面显示名称：「${device.name}」'));
    expect(snapshot, contains('名称来源：涂鸦设备名'));
    expect(snapshot, contains('按产品 ID 查涂鸦产品名：「YUSEN-智能花盆」'));
    expect(snapshot, contains('设备 ID：${device.id}'));
    expect(snapshot, contains('⚠ 设备名与产品名不一致'));
  }, skip: !DebugLogGate.enabled);

  testWidgets('日志框一条一块，可单条复制、复制全部', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map<Object?, Object?>)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    state.logNote('第一条');
    state.logNote('第二条：甲；乙');

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: InteractionLogPanel())),
        ),
      ),
    );

    expect(find.textContaining('联调日志 · 2 条'), findsOneWidget);
    expect(find.text('第二条：甲'), findsOneWidget);
    expect(find.text('  乙'), findsOneWidget);
    expect(find.text('复制'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('interaction-log-copy-all')));
    await tester.pump();
    expect(copied.single, allOf(contains('第一条'), contains('第二条：甲\n  乙')));
    expect(find.byKey(const Key('interaction-log-copied')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('interaction-log-copied')), findsNothing);
  }, skip: !DebugLogGate.enabled);
}
