import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/auth/presentation/password_page.dart';
import 'package:flowerpot/src/features/profile/presentation/modify_password_page.dart';
import 'package:flowerpot/src/features/profile/presentation/widgets/account_password_form_card.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('modify password page matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpModifyPasswordPage(tester, const Size(375, 812));

    expect(find.text('修改密码'), findsOneWidget);
    expect(find.byKey(const Key('app-page-background-image')), findsOneWidget);
    expect(find.text('原密码'), findsOneWidget);
    expect(find.text('请输入原密码'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(find.text('确认密码'), findsOneWidget);
    expect(find.text('请确认密码'), findsOneWidget);
    expect(find.text('忘记密码?'), findsOneWidget);
    expect(find.text('确认修改'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    final formCard = find.byType(AccountPasswordFormCard);
    final confirmButton = find.byKey(const Key('confirm-modify-password'));
    expect(tester.getSize(formCard), const Size(339, 230));
    expect(tester.getTopLeft(formCard), const Offset(18, 65));
    expect(tester.getSize(confirmButton), const Size(339, 50));
    expect(tester.getTopLeft(confirmButton), const Offset(18, 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('modify password content remains scrollable at 320x568', (
    tester,
  ) async {
    await _pumpModifyPasswordPage(tester, const Size(320, 568));

    final confirm = find.byKey(const Key('confirm-modify-password'));
    await tester.ensureVisible(confirm);
    await tester.pump();

    expect(confirm, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('three password fields have independent visibility controls', (
    tester,
  ) async {
    await _pumpModifyPasswordPage(tester, const Size(375, 812));

    var fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.every((field) => field.obscureText), isTrue);

    await tester.tap(find.byKey(const Key('old-password-visibility')));
    await tester.pump();

    fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].obscureText, isFalse);
    expect(fields[1].obscureText, isTrue);
    expect(fields[2].obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirm requires the original password', (tester) async {
    await _pumpModifyPasswordPage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('confirm-modify-password')));
    await tester.pump();

    expect(find.text('请输入原密码'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirm validates matching passwords', (tester) async {
    await _pumpModifyPasswordPage(tester, const Size(375, 812));
    final fields = find.byType(TextField);

    await tester.enterText(fields.at(0), 'old-password');
    await tester.enterText(fields.at(1), 'password123');
    await tester.enterText(fields.at(2), 'password456');
    await tester.tap(find.byKey(const Key('confirm-modify-password')));
    await tester.pump();

    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot password opens the verification reset flow', (
    tester,
  ) async {
    PasswordArguments? arguments;
    await _pumpModifyPasswordPage(
      tester,
      const Size(375, 812),
      onPasswordArguments: (value) => arguments = value,
    );

    await tester.tap(find.byKey(const Key('modify-password-forgot')));
    await tester.pumpAndSettle();

    expect(find.text('password-target'), findsOneWidget);
    expect(arguments?.account, '13812345678');
    expect(arguments?.region, LoginRegion.domestic);
    expect(arguments?.title, '忘记密码');
    expect(arguments?.returnToLoginOnSuccess, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirm reports the unavailable repository capability', (
    tester,
  ) async {
    await _pumpModifyPasswordPage(tester, const Size(375, 812));
    final fields = find.byType(TextField);

    await tester.enterText(fields.at(0), 'old-password');
    await tester.enterText(fields.at(1), 'password123');
    await tester.enterText(fields.at(2), 'password123');
    await tester.tap(find.byKey(const Key('confirm-modify-password')));
    await tester.pump();

    expect(find.text('修改密码功能暂未开放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpModifyPasswordPage(
  WidgetTester tester,
  Size size, {
  ValueChanged<PasswordArguments>? onPasswordArguments,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: const ModifyPasswordPage(
        arguments: ModifyPasswordArguments(account: '13812345678'),
      ),
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.password) {
          onPasswordArguments?.call(settings.arguments! as PasswordArguments);
          return MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('password-target'))),
          );
        }
        return null;
      },
    ),
  );
  await tester.pump();
}
