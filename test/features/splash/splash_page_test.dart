import 'package:flowerpot/src/core/backend/backend.dart';
import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/splash/presentation/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/asset_finder.dart';

void main() {
  test('the two backgrounds the root switch crosses share one gradient', () {
    // _RootTransitionBackdrop paints only this gradient, on the premise that it
    // is common to both destinations: blending one colour with itself at any
    // opacity leaves it unchanged, so the background stays constant while only
    // the artwork cross-fades. Give the two variants different gradients and
    // that stops being true.
    expect(
      AppPageBackground.home.gradient,
      AppPageBackground.account.gradient,
    );
  });

  testWidgets('启动页只画背景图，品牌那一组内容先隐藏', (tester) async {
    // 2026-09-10 产品要求：启动页先只留背景图。logo / 字标 / 标语的代码还在
    // （`_showBranding` 开关），但当前不该画出来。
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const SplashPage()),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(findAssetImage(AppAssets.homeBackground), findsOneWidget);
    expect(findAssetImage(AppAssets.appLogo), findsNothing);
    expect(findAssetImage(AppAssets.ysplanterWordmark), findsNothing);
    expect(find.text('您的智能设备贴心伴侣'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cold start shows the splash before the login page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      FlowerpotApp(
      backendRepository: const DisabledAppBackendRepository(),
        splashDuration: const Duration(milliseconds: 600),
        repository: MockTuyaRepository(latency: Duration.zero),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('splash-page')), findsOneWidget);
    expect(find.text('登录账号，连接和管理你的智能设备'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('splash-page')), findsNothing);
    expect(find.text('登录账号，连接和管理你的智能设备'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the splash cross-fades into the login page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      FlowerpotApp(
      backendRepository: const DisabledAppBackendRepository(),
        splashDuration: const Duration(milliseconds: 600),
        repository: MockTuyaRepository(latency: Duration.zero),
      ),
    );
    await tester.pump();

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher).first,
    );
    expect(switcher.duration, kRootTransitionDuration);

    // Half-way through the switch both screens are still mounted, which a hard
    // cut would not do. Mounted, not both visible: the two-stage fade-through
    // deliberately keeps their opacities from overlapping, so at the midpoint
    // the outgoing splash is fully transparent but has not been pruned yet
    // (AnimatedSwitcher drops it only once the animation reaches dismissed).
    await tester.pump(const Duration(milliseconds: 600)); // minimum elapses
    await tester.pump(kRootTransitionDuration ~/ 2);
    expect(find.byKey(const Key('splash-page')), findsOneWidget);
    expect(find.text('登录账号，连接和管理你的智能设备'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('splash-page')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
