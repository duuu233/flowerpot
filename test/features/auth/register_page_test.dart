import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/auth/presentation/register_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('register page exposes the Figma content', (tester) async {
    await _pumpRegisterPage(tester, const Size(375, 812));

    expect(find.text('注册账号'), findsOneWidget);
    expect(find.text('请输入手机号'), findsOneWidget);
    expect(find.text('请输入验证码'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(find.text('请确认密码'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    expect(find.text('已有账户？'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.text('《用户协议》'), findsOneWidget);
    expect(find.text('《隐私政策》'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('register content remains scrollable at 320x568', (tester) async {
    await _pumpRegisterPage(tester, const Size(320, 568));

    final privacy = find.text('《隐私政策》');
    await tester.ensureVisible(privacy);
    await tester.pump();

    expect(privacy, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password fields have independent visibility controls', (
    tester,
  ) async {
    await _pumpRegisterPage(tester, const Size(375, 812));

    var fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[2].obscureText, isTrue);
    expect(fields[3].obscureText, isTrue);

    await tester.tap(find.byKey(const Key('register-password-visibility')));
    await tester.pump();

    fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[2].obscureText, isFalse);
    expect(fields[3].obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('register verification code uses the entered phone', (
    tester,
  ) async {
    await _pumpRegisterPage(tester, const Size(375, 812));

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();

    expect(find.text('验证码已发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('register validates matching passwords', (tester) async {
    await _pumpRegisterPage(tester, const Size(375, 812));
    final fields = find.byType(TextField);

    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), 'password456');
    await tester.tap(find.byType(Checkbox));
    final register = find.text('注册');
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pumpAndSettle();

    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpRegisterPage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(theme: buildAppTheme(), home: const RegisterPage()),
    ),
  );
  await tester.pump();
}
