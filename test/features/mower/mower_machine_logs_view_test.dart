import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/features/mower/presentation/mower_machine_logs_view.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';

void main() {
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
