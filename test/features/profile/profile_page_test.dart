import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/profile/presentation/profile_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('personal information page matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpProfilePage(tester, const Size(375, 812));

    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('头像'), findsOneWidget);
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('江江江'), findsOneWidget);
    expect(find.text('手机号'), findsOneWidget);
    expect(find.text('138****5678'), findsOneWidget);
    expect(find.text('账号ID'), findsOneWidget);
    expect(find.text('J123456'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.byKey(const Key('personal-info-card')), findsOneWidget);
    expect(findAssetImage(AppAssets.profileAvatarIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nickname can be edited and persisted', (tester) async {
    final state = await _pumpProfilePage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('personal-info-nickname')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nickname-edit-dialog')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('nickname-edit-field')),
      '新的昵称',
    );
    await tester.tap(find.byKey(const Key('confirm-nickname-edit')));
    await tester.pumpAndSettle();

    expect(state.user?.nickname, '新的昵称');
    expect(find.text('新的昵称'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logout confirms and returns to the auth route', (tester) async {
    await _pumpProfilePage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('personal-info-logout')));
    await tester.pumpAndSettle();
    expect(find.text('确定退出当前账号吗？'), findsOneWidget);

    await tester.tap(find.text('退出登录').last);
    await tester.pumpAndSettle();

    expect(find.text('auth-target'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal information remains usable at 320x568', (tester) async {
    await _pumpProfilePage(tester, const Size(320, 568));

    final logout = find.byKey(const Key('personal-info-logout'));
    await tester.ensureVisible(logout);
    await tester.pump();

    expect(logout, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<FlowerpotState> _pumpProfilePage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(repository: _ProfileRepository());
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
        home: const ProfilePage(),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.auth) {
            return MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Center(child: Text('auth-target'))),
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

class _ProfileRepository extends MockTuyaRepository {
  _ProfileRepository() : super(latency: Duration.zero);

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
