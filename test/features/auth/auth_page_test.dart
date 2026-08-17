import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/auth/presentation/auth_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('verification login exposes the Figma content', (tester) async {
    await _pumpAuthPage(tester, const Size(375, 812));

    expect(find.byKey(const Key('auth-app-logo')), findsOneWidget);
    expect(find.byKey(const Key('auth-wordmark')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('auth-asset-icon:assets/images/phone_icon.png'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'auth-asset-icon:assets/images/verification_code_icon.png',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'auth-social-icon:assets/images/wechat_login_icon.png',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'auth-social-icon:assets/images/alipay_login_icon.png',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('app-page-background-image')), findsOneWidget);
    expect(find.text('登录账号，连接和管理你的智能设备'), findsOneWidget);
    expect(find.text('验证码登录'), findsOneWidget);
    expect(find.text('密码登录'), findsOneWidget);
    expect(find.text('请输入手机号'), findsOneWidget);
    expect(find.text('请输入验证码'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.text('没有账户？'), findsOneWidget);
    expect(find.text('去注册'), findsOneWidget);
    expect(find.text('其他登录方式'), findsOneWidget);
    expect(find.text('《用户协议》'), findsOneWidget);
    expect(find.text('《隐私政策》'), findsOneWidget);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.decoration?.prefixIconConstraints?.minWidth, 56);
    }
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    final panelRect = tester.getRect(find.byKey(const Key('login-panel')));
    expect(panelRect.left, 20);
    expect(panelRect.right, 355);
    expect(panelRect.width, 335);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login content remains scrollable at 320x568', (tester) async {
    await _pumpAuthPage(tester, const Size(320, 568));

    final demo = find.text('体验模式');
    await tester.ensureVisible(demo);
    await tester.pump();

    expect(demo, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login tabs switch to the password field', (tester) async {
    await _pumpAuthPage(tester, const Size(375, 812));

    await tester.tap(find.text('密码登录'));
    await tester.pumpAndSettle();

    expect(find.text('请输入密码'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'auth-asset-icon:assets/images/password_icon.png',
        ),
      ),
      findsOneWidget,
    );
    final passwordIcon = tester.widget<Image>(
      find.byKey(
        const ValueKey<String>(
          'auth-asset-icon:assets/images/password_icon.png',
        ),
      ),
    );
    expect(passwordIcon.width, 20);
    expect(passwordIcon.height, 20);
    expect(find.text('获取验证码'), findsNothing);
    expect(find.text('忘记密码?'), findsOneWidget);
    expect(
      find.byKey(const Key('forgot-password-link')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const Key('password-visibility-toggle')), findsOneWidget);
    var fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.last.obscureText, isTrue);

    await tester.tap(find.byKey(const Key('password-visibility-toggle')));
    await tester.pump();

    fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.last.obscureText, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth page can initialize in password mode', (tester) async {
    await _pumpAuthPage(tester, const Size(375, 812), initialCodeLogin: false);

    expect(find.text('请输入密码'), findsOneWidget);
    expect(find.text('忘记密码?'), findsOneWidget);
    expect(
      find.byKey(const Key('forgot-password-link')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('获取验证码'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification code action uses the entered phone number', (
    tester,
  ) async {
    await _pumpAuthPage(tester, const Size(375, 812));

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();

    expect(find.text('验证码已发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the SDK console entry sits next to the demo shortcut', (
    tester,
  ) async {
    await _pumpAuthPage(tester, const Size(375, 812));

    final entry = find.byKey(const Key('tuya-debug-entry'));
    await tester.ensureVisible(entry);
    await tester.pump();

    expect(entry, findsOneWidget);
    expect(find.text('涂鸦 SDK 联调'), findsOneWidget);
    expect(find.text('体验模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login requires accepting the agreements', (tester) async {
    await _pumpAuthPage(tester, const Size(375, 812));

    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('请先阅读并同意用户协议与隐私政策'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAuthPage(
  WidgetTester tester,
  Size size, {
  bool initialCodeLogin = true,
}) async {
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
        home: AuthPage(initialCodeLogin: initialCodeLogin),
      ),
    ),
  );
  await tester.pump();
}
