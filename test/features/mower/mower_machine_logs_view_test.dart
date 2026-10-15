import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/features/mower/presentation/mower_machine_logs_view.dart';
import 'package:flowerpot/src/features/messages/message_category_tabs.dart';
import 'package:flowerpot/src/features/mower/mower_ui.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';

void main() {
  testWidgets('三类真实DP事件分栏查询，切换选中态、日期各自保存，卡片可查看', (tester) async {
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    final log = await state.mowerMachineLog('mower', seedSnapshot: false);
    log.apply({5: 0, 118: true, 117: 0});
    log.apply({5: 1});
    log.apply({118: false});
    log.apply({111: '{"device":1,"error":0,"function":0,"circularize":0}'});
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: const MaterialApp(
          home: Scaffold(body: MowerMachineLogsView(deviceId: 'mower')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('开始割草'), findsOneWidget);
    expect(find.text('机器盖子被打开'), findsNothing);
    expect(find.text('电池异常，机器已停机'), findsNothing);
    await tester.tap(find.byKey(const Key('mower-messages-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').last);
    await tester.pumpAndSettle();
    for (final category in [1, 2, 0, 2, 1]) {
      await tester.tap(find.byKey(Key('mower-messages-tab-$category')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MessageCategoryTabs>(find.byType(MessageCategoryTabs))
            .current,
        category,
      );
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const Key('mower-messages-date')),
            )
            .value,
        category == 0 ? 1 : 0,
      );
      final expected = ['开始割草', '机器盖子被打开', '电池异常，机器已停机'][category];
      expect(find.text(expected), findsOneWidget);
      final visible = find.byKey(
        ValueKey(
          'mower-machine-log-${log.entries.firstWhere((entry) => entry.level == category + 1).id}',
        ),
      );
      await tester.tap(visible);
      await tester.pumpAndSettle();
      expect(find.textContaining('APP接收时间'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
    }
    final date = tester.widget<DropdownButton<int>>(
      find.byKey(const Key('mower-messages-date')),
    );
    expect(date.style?.color, MowerColors.inkSecondary);
    expect(find.textContaining('当前等级'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('机器日志实时告警弹窗与红点；清位静默恢复到日志；日期可选可复位', (tester) async {
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    final log = await state.mowerMachineLog('mower', seedSnapshot: false);
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: const MaterialApp(
          home: Scaffold(body: MowerMachineLogsView(deviceId: 'mower')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    log.apply({111: '{"device":1,"error":0,"function":0,"circularize":0}'});
    await tester.pumpAndSettle();
    expect(find.text('设备告警'), findsOneWidget);
    expect(find.text('我已处理'), findsOneWidget);
    expect(find.textContaining('电池异常'), findsOneWidget);
    await tester.tap(find.text('我已处理'));
    await tester.pumpAndSettle();
    expect(find.text('有新的机器告警，请检查现场'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-messages-tab-2')));
    await tester.pumpAndSettle();
    expect(log.unreadCritical, 0);
    expect(find.text('电池异常，机器已停机'), findsOneWidget);
    log.apply({111: '{"device":0,"error":0,"function":0,"circularize":0}'});
    await tester.pumpAndSettle();
    expect(find.text('设备告警'), findsNothing);
    expect(find.text('暂无告警'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-messages-tab-0')));
    await tester.pumpAndSettle();
    expect(find.text('电池异常已恢复'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-messages-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择日期').last);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    await tester.tap(find.byKey(const Key('mower-messages-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部日期').last);
    await tester.pumpAndSettle();
    expect(find.text('电池异常已恢复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
