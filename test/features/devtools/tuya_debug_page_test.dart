import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devtools/presentation/tuya_debug_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the console states that the mock backend answers the calls', (
    tester,
  ) async {
    await _pumpDebugPage(tester);

    expect(find.text('涂鸦 SDK 联调'), findsOneWidget);
    expect(find.byKey(const Key('tuya-debug-mock-notice')), findsOneWidget);
    expect(find.text('当前调用不会到达涂鸦 SDK'), findsOneWidget);
    expect(
      find.text('flutter run --dart-define=TUYA_ENABLED=true'),
      findsOneWidget,
    );
    expect(find.text('未开启（默认 Mock）'), findsOneWidget);
    expect(find.text('未登录'), findsOneWidget);
    expect(_enterAppButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password login logs the call and unlocks the app entry', (
    tester,
  ) async {
    final state = await _pumpDebugPage(tester);

    await tester.enterText(
      find.byKey(const Key('tuya-debug-account')),
      '13800138000',
    );
    await tester.enterText(
      find.byKey(const Key('tuya-debug-password')),
      'flowerpot123',
    );
    await _tap(tester, const Key('tuya-debug-login-password'));

    expect(state.authenticated, isTrue);
    expect(find.textContaining('密码登录'), findsWidgets);
    expect(find.textContaining('登录成功'), findsWidgets);
    expect(find.textContaining('86/138****00'), findsOneWidget);
    expect(_enterAppButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejected call logs its failure code', (tester) async {
    await _pumpDebugPage(tester);

    await _tap(tester, const Key('tuya-debug-login-password'));

    expect(find.textContaining('[invalid_input] 请先填写账号'), findsOneWidget);
    expect(find.textContaining('86/未填写'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the log can be cleared once it holds an entry', (tester) async {
    await _pumpDebugPage(tester);

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('tuya-debug-clear-log')))
          .onPressed,
      isNull,
    );

    await _tap(tester, const Key('tuya-debug-probe-sdk'));

    expect(find.textContaining('SDK 初始化通过'), findsWidgets);

    await _tap(tester, const Key('tuya-debug-clear-log'));

    expect(find.textContaining('SDK 初始化通过'), findsNothing);
    expect(
      find.text('还没有调用记录。每次调用都会记录时间、结果、错误码和脱敏账号。'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

AppPrimaryButton _enterAppButton(WidgetTester tester) => tester
    .widget<AppPrimaryButton>(find.byKey(const Key('tuya-debug-enter-app')));

Future<void> _tap(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  // The result toast repeats the message; expire it so expectations only see
  // what the console itself renders.
  await tester.pump(const Duration(seconds: 7));
  await tester.pumpAndSettle();
}

Future<FlowerpotState> _pumpDebugPage(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(480, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(theme: buildAppTheme(), home: const TuyaDebugPage()),
    ),
  );
  await tester.pump();
  return state;
}
