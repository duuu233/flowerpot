import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/profile/presentation/login_password_page.dart';
import 'package:flowerpot/src/features/profile/presentation/widgets/account_password_form_card.dart';
import 'package:flowerpot/src/features/profile/presentation/widgets/login_password_account_card.dart';
import 'package:flowerpot/src/features/profile/presentation/widgets/login_password_advice_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login password page matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpLoginPasswordPage(tester, const Size(375, 812));

    expect(find.text('登录密码'), findsOneWidget);
    expect(find.byKey(const Key('app-page-background-image')), findsOneWidget);
    expect(find.text('设置登录密码后，可使用“手机号+密码”\n登录YSplanter账号'), findsOneWidget);
    expect(find.text('当前账号： 138****5678'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(find.text('确认密码'), findsOneWidget);
    expect(find.text('请确认密码'), findsOneWidget);
    expect(find.text('密码设置建议'), findsOneWidget);
    expect(find.text('1. 密码长度为8-20位字符'), findsOneWidget);
    expect(find.text('2. 建议包含字母和数字的组合'), findsOneWidget);
    expect(find.text('保存密码'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    final accountCard = find.byType(LoginPasswordAccountCard);
    final saveButton = find.byKey(const Key('save-login-password'));
    expect(tester.getSize(accountCard), const Size(339, 90));
    expect(tester.getTopLeft(accountCard), const Offset(18, 65));
    expect(
      tester.getSize(find.byType(AccountPasswordFormCard)),
      const Size(339, 153),
    );
    expect(tester.getSize(find.byType(LoginPasswordAdviceCard)).width, 323);
    expect(tester.getSize(saveButton), const Size(339, 50));
    expect(tester.getTopLeft(saveButton), const Offset(18, 501));
    expect(tester.takeException(), isNull);
  });

  testWidgets('login password content remains scrollable at 320x568', (
    tester,
  ) async {
    await _pumpLoginPasswordPage(tester, const Size(320, 568));

    final save = find.byKey(const Key('save-login-password'));
    await tester.ensureVisible(save);
    await tester.pump();

    expect(save, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password fields have independent visibility controls', (
    tester,
  ) async {
    await _pumpLoginPasswordPage(tester, const Size(375, 812));

    var fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].obscureText, isTrue);
    expect(fields[1].obscureText, isTrue);

    await tester.tap(find.byKey(const Key('login-password-visibility')));
    await tester.pump();

    fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].obscureText, isFalse);
    expect(fields[1].obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save validates the Figma password length rule', (tester) async {
    await _pumpLoginPasswordPage(tester, const Size(375, 812));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'short');
    await tester.enterText(fields.at(1), 'short');
    await tester.tap(find.byKey(const Key('save-login-password')));
    await tester.pump();

    expect(find.text('密码长度需为8-20位字符'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save validates matching passwords', (tester) async {
    await _pumpLoginPasswordPage(tester, const Size(375, 812));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'password123');
    await tester.enterText(fields.at(1), 'password456');
    await tester.tap(find.byKey(const Key('save-login-password')));
    await tester.pump();

    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save reports the unavailable repository capability', (
    tester,
  ) async {
    await _pumpLoginPasswordPage(tester, const Size(375, 812));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'password123');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.byKey(const Key('save-login-password')));
    await tester.pump();

    expect(find.text('登录密码设置功能暂未开放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpLoginPasswordPage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: const LoginPasswordPage(
        arguments: LoginPasswordArguments(account: '13812345678'),
      ),
    ),
  );
  await tester.pump();
}
