import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/auth/presentation/password_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('forgot password page exposes the Figma content', (tester) async {
    await _pumpPasswordPage(tester, const Size(375, 812));

    expect(find.text('忘记密码'), findsOneWidget);
    expect(find.text('请输入手机号'), findsOneWidget);
    expect(find.text('请输入验证码'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(find.text('请确认密码'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot password content remains scrollable at 320x568', (
    tester,
  ) async {
    await _pumpPasswordPage(tester, const Size(320, 568));

    final confirm = find.text('确认');
    await tester.ensureVisible(confirm);
    await tester.pump();

    expect(confirm, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset password fields have independent visibility controls', (
    tester,
  ) async {
    await _pumpPasswordPage(tester, const Size(375, 812));

    var fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[2].obscureText, isTrue);
    expect(fields[3].obscureText, isTrue);

    await tester.tap(find.byKey(const Key('reset-password-visibility')));
    await tester.pump();

    fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[2].obscureText, isFalse);
    expect(fields[3].obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset verification code uses the entered phone', (tester) async {
    await _pumpPasswordPage(tester, const Size(375, 812));

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();

    expect(find.text('验证码已发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset password validates matching passwords', (tester) async {
    await _pumpPasswordPage(tester, const Size(375, 812));
    final fields = find.byType(TextField);

    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), 'password456');
    final confirm = find.text('确认');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPasswordPage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const PasswordPage(arguments: PasswordArguments()),
      ),
    ),
  );
  await tester.pump();
}
