import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the app opens on the login page without a tab bar', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(375, 812));

    expect(find.text('登录账号，连接和管理你的智能设备'), findsOneWidget);
    expect(find.text('验证码登录'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('any phone number and code sign in to the empty-device home', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(375, 812));
    await _signIn(tester);

    expect(find.text('暂无设备'), findsOneWidget);
    expect(find.byKey(const Key('add-device-button')), findsOneWidget);
    // The home screen carries no bottom tab bar.
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the header avatar opens the profile page', (tester) async {
    await _pumpApp(tester, const Size(375, 812), seedDevice: true);
    await _signIn(tester);

    await tester.tap(find.byKey(const Key('device-list-profile-button')));
    await tester.pumpAndSettle();

    expect(find.text('个人信息'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // The profile page is a pushed route now, so it can be popped back.
    await tester.tap(find.byType(AppBackButton).first);
    await tester.pumpAndSettle();

    expect(find.text('设备列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pairing runs search → selection → Wi-Fi → success', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(375, 812));
    await _signIn(tester);

    await tester.tap(find.byKey(const Key('add-device-button')));
    await tester.pumpAndSettle();
    expect(find.text('搜索附近设备…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('请选择需要连接的设备'), findsOneWidget);

    await tester.tap(find.byKey(const Key('connect-device-0')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('连接Wi-Fi'), findsOneWidget);
    expect(find.byKey(const Key('pairing-connected-device')), findsOneWidget);

    // Credentials are no longer prefilled with placeholder values.
    await tester.enterText(
      find.byKey(const Key('pairing-ssid-field')),
      'TP-LINK_2.4G',
    );
    await tester.enterText(
      find.byKey(const Key('pairing-password-field')),
      'wifi-password',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('start-pairing-button')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pairing-success-title')), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.byKey(const Key('success-add-plant-button')), findsNothing);

    await tester.tap(find.byKey(const Key('success-return-home-button')));
    await tester.pumpAndSettle();
    expect(find.text('设备列表'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the device list opens the unplanted page, then details', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(375, 812), seedDevice: true);
    await _signIn(tester);

    expect(find.text('设备列表'), findsOneWidget);
    expect(find.byKey(const Key('device-list-profile-button')), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('device-list-item-vdevo17235508413621')),
    );
    await tester.pumpAndSettle();
    expect(find.text('还未添加植物'), findsOneWidget);
    expect(find.byKey(const Key('home-back-button')), findsOneWidget);

    await tester.tap(find.text('添加植物'));
    await tester.pumpAndSettle();
    expect(find.text('确认添加'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-plant-selection')));
    await tester.pumpAndSettle();

    expect(find.text('还未添加植物'), findsNothing);
    expect(find.text('定制动画'), findsOneWidget);
    expect(find.text('电池状态'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the login page opens the Tuya SDK console', (tester) async {
    await _pumpApp(tester, const Size(375, 812));

    final entry = find.byKey(const Key('tuya-debug-entry'));
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('运行环境'), findsOneWidget);
    expect(find.text('账号参数'), findsOneWidget);
    expect(find.byKey(const Key('tuya-debug-enter-app')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the profile page reopens the SDK console after signing in', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(375, 812), seedDevice: true);
    await _signIn(tester);

    await tester.tap(find.byKey(const Key('device-list-profile-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mine-tuya-debug-entry')));
    await tester.pumpAndSettle();

    expect(find.text('运行环境'), findsOneWidget);
    expect(find.text('账号参数'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home remains usable on a compact 320x568 viewport', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(320, 568), seedDevice: true);
    await _signIn(tester);

    expect(find.text('设备列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  Size size, {
  bool seedDevice = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.pumpWidget(
    FlowerpotApp(
      repository: MockTuyaRepository(
        latency: Duration.zero,
        seedDevice: seedDevice,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Signs in with an arbitrary phone number and code, which is all the demo
/// build asks for.
Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '13800000000');
  await tester.enterText(find.byType(TextField).at(1), '8888');

  final agreement = find.byType(Checkbox);
  await tester.ensureVisible(agreement);
  await tester.pumpAndSettle();
  await tester.tap(agreement);
  await tester.pumpAndSettle();

  final loginButton = find.widgetWithText(FilledButton, '登录');
  await tester.ensureVisible(loginButton);
  await tester.pumpAndSettle();
  await tester.tap(loginButton);
  await tester.pumpAndSettle();
}
