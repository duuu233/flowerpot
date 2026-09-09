import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/auth/presentation/auth_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextButton _sendCodeButton(WidgetTester tester) => tester.widget<TextButton>(
  find.ancestor(
    of: find.text('获取验证码'),
    matching: find.byType(TextButton),
  ),
);

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
    // Alipay quick login and password login are hidden until their platform
    // parameters exist.
    expect(
      find.byKey(
        const ValueKey<String>(
          'auth-social-icon:assets/images/alipay_login_icon.png',
        ),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('app-page-background-image')), findsOneWidget);
    expect(find.text('登录账号，连接和管理你的智能设备'), findsOneWidget);
    // Only one login mode is offered, so the tab strip is gone entirely.
    expect(find.text('验证码登录'), findsNothing);
    expect(find.text('密码登录'), findsNothing);
    expect(find.text('忘记密码?'), findsNothing);
    expect(find.text('请输入手机号'), findsOneWidget);
    expect(find.text('请输入验证码'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
    // Registration happens implicitly on first login.
    expect(find.text('没有账户？'), findsNothing);
    expect(find.text('去注册'), findsNothing);
    expect(find.text('输入验证码即登录，未注册手机将自动创建账户'), findsOneWidget);
    expect(find.text('其他登录方式'), findsOneWidget);
    expect(find.text('《用户协议》'), findsOneWidget);
    expect(find.text('《隐私政策》'), findsOneWidget);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.decoration?.prefixIconConstraints?.minWidth, 56);
    }
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    // Page margin is AppSpacing.pageMargin (18) on both sides of the 375pt
    // content column.
    final panelRect = tester.getRect(find.byKey(const Key('login-panel')));
    expect(panelRect.left, 18);
    expect(panelRect.right, 357);
    expect(panelRect.width, 339);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login content remains scrollable at 320x568', (tester) async {
    await _pumpAuthPage(tester, const Size(320, 568));

    final demo = find.text('《隐私政策》');
    await tester.ensureVisible(demo);
    await tester.pump();

    expect(demo, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password mode cannot be reached while it is hidden', (
    tester,
  ) async {
    await _pumpAuthPage(tester, const Size(375, 812), initialCodeLogin: false);

    expect(find.text('请输入验证码'), findsOneWidget);
    expect(find.text('请输入密码'), findsNothing);
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.byKey(const Key('forgot-password-link')), findsNothing);
    expect(find.byKey(const Key('password-visibility-toggle')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid phone and code use the injected repository', (tester) async {
    final state = await _pumpAuthPage(tester, const Size(375, 812));

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await _acceptAndSubmit(tester);

    expect(state.authenticated, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejected code stays signed out without a demo fallback', (tester) async {
    final state = await _pumpAuthPage(
      tester,
      const Size(375, 812),
      repository: _RejectingRepository(),
    );

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.enterText(find.byType(TextField).at(1), '000000');
    await _acceptAndSubmit(tester);

    expect(find.textContaining('验证码错误'), findsOneWidget);
    expect(state.authenticated, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty input is rejected before any call', (tester) async {
    final state = await _pumpAuthPage(tester, const Size(375, 812));

    await _acceptAndSubmit(tester);

    expect(find.text('请输入手机号和验证码'), findsOneWidget);
    expect(state.authenticated, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机号没填对时发不了验证码', (tester) async {
    await _pumpAuthPage(tester, const Size(375, 812));

    // 位数不够：按钮直接是禁用的，点不出一条短信。
    await tester.enterText(find.byType(TextField).first, '1380013');
    await tester.pump();
    expect(_sendCodeButton(tester).onPressed, isNull);

    // 补齐 11 位之后才可点。
    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.pump();
    expect(_sendCodeButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机号输入框只收 11 位数字', (tester) async {
    await _pumpAuthPage(tester, const Size(375, 812));

    // `TextInputType.phone` 的键盘上还有 + - ( )，粘贴也可能带进字母和空格。
    await tester.enterText(find.byType(TextField).first, '138-0013 8000abc9');
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, '13800138000');
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification code action uses the entered phone number', (
    tester,
  ) async {
    await _pumpAuthPage(tester, const Size(375, 812));

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.pump();
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();

    expect(find.text('验证码已发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login has no SDK console entry', (
    tester,
  ) async {
    await _pumpAuthPage(tester, const Size(375, 812));

    final entry = find.byKey(const Key('tuya-debug-entry'));
    expect(entry, findsNothing);
    expect(find.text('涂鸦 SDK 联调'), findsNothing);
    expect(find.text('体验模式'), findsNothing);
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

/// Ticks the agreement box and submits, which every sign-in path needs.
Future<void> _acceptAndSubmit(WidgetTester tester) async {
  final agreement = find.byType(Checkbox);
  await tester.ensureVisible(agreement);
  await tester.pumpAndSettle();
  await tester.tap(agreement);
  await tester.pumpAndSettle();

  final login = find.widgetWithText(FilledButton, '登录');
  await tester.ensureVisible(login);
  await tester.pumpAndSettle();
  await tester.tap(login);
  await tester.pumpAndSettle();
}

Future<FlowerpotState> _pumpAuthPage(
  WidgetTester tester,
  Size size, {
  bool initialCodeLogin = true,
  TuyaRepository? repository,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: repository ?? MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        routes: {'/shell': (_) => const Scaffold(body: Text('signed-in'))},
        home: AuthPage(initialCodeLogin: initialCodeLogin),
      ),
    ),
  );
  await tester.pump();
  return state;
}

/// Stands in for the native bridge refusing a code, so the demo fallback is
/// exercised instead of the mock backend's permissive login.
class _RejectingRepository extends MockTuyaRepository {
  _RejectingRepository() : super(latency: Duration.zero);

  @override
  Future<AppUser> login({
    required String account,
    required String credential,
    required LoginRegion region,
    required bool verificationCode,
  }) async {
    throw const TuyaException('USER_MOBILE_CODE_ERROR', '验证码错误');
  }
}
