import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/auth/presentation/password_page.dart';
import 'package:flowerpot/src/features/profile/presentation/account_security_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('account security page matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpAccountSecurityPage(tester, const Size(375, 812));

    expect(find.text('账号与安全'), findsOneWidget);
    expect(find.text('手机号'), findsOneWidget);
    expect(find.text('138****5678'), findsOneWidget);
    expect(find.text('登录密码'), findsOneWidget);
    expect(find.text('已设置'), findsOneWidget);
    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('忘记密码'), findsOneWidget);
    expect(find.text('通过验证码重置'), findsOneWidget);
    expect(find.byKey(const Key('account-security-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('change password opens the existing reset flow in change mode', (
    tester,
  ) async {
    PasswordArguments? arguments;
    await _pumpAccountSecurityPage(
      tester,
      const Size(375, 812),
      onPasswordArguments: (value) => arguments = value,
    );

    await tester.tap(find.byKey(const Key('account-security-change-password')));
    await tester.pumpAndSettle();

    expect(find.text('password-target'), findsOneWidget);
    expect(arguments?.account, '13812345678');
    expect(arguments?.title, '修改密码');
    expect(arguments?.returnToLoginOnSuccess, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot password opens verification reset mode', (tester) async {
    PasswordArguments? arguments;
    await _pumpAccountSecurityPage(
      tester,
      const Size(375, 812),
      onPasswordArguments: (value) => arguments = value,
    );

    await tester.tap(find.byKey(const Key('account-security-forgot-password')));
    await tester.pumpAndSettle();

    expect(arguments?.title, '忘记密码');
    expect(arguments?.returnToLoginOnSuccess, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone action reports unavailable backend capability', (
    tester,
  ) async {
    await _pumpAccountSecurityPage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('account-security-phone')));
    await tester.pump();

    expect(find.text('手机号修改功能暂未开放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account security remains usable at 320x568', (tester) async {
    await _pumpAccountSecurityPage(tester, const Size(320, 568));

    final forgotPassword = find.byKey(
      const Key('account-security-forgot-password'),
    );
    await tester.ensureVisible(forgotPassword);
    await tester.pump();

    expect(forgotPassword, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<FlowerpotState> _pumpAccountSecurityPage(
  WidgetTester tester,
  Size size, {
  ValueChanged<PasswordArguments>? onPasswordArguments,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(repository: _AccountSecurityRepository());
  addTearDown(state.dispose);
  await state.login(
    account: '13812345678',
    credential: 'password',
    region: LoginRegion.domestic,
    verificationCode: false,
  );
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const AccountSecurityPage(),
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
    ),
  );
  await tester.pump();
  return state;
}

class _AccountSecurityRepository extends MockTuyaRepository {
  _AccountSecurityRepository() : super(latency: Duration.zero);

  @override
  Future<AppUser> login({
    required String account,
    required String credential,
    required LoginRegion region,
    required bool verificationCode,
  }) async {
    return const AppUser(
      id: 'J123456',
      nickname: '江江江',
      account: '13812345678',
    );
  }

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[];
}
