import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/profile/presentation/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('about page matches the 375x812 Figma content', (tester) async {
    await _pumpAboutPage(tester, const Size(375, 812));

    expect(find.text('关于YSplanter'), findsOneWidget);
    expect(findAssetImage(AppAssets.appLogo), findsOneWidget);
    expect(findAssetImage(AppAssets.ysplanterWordmark), findsOneWidget);
    expect(find.text('您的智能花盆贴心伴侣'), findsOneWidget);
    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text('V1.0.0'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('已是最新版本'), findsOneWidget);
    // 版本说明已下线：升级说明改由「检查更新」的弹窗展示。
    expect(find.text('版本说明'), findsNothing);
    expect(find.byKey(const Key('about-logo')), findsOneWidget);
    expect(find.byKey(const Key('about-version-card')), findsOneWidget);
    expect(findAssetImage(AppAssets.aboutCurrentVersionIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('check update reports the current status', (tester) async {
    await _pumpAboutPage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('about-check-update')));
    await tester.pumpAndSettle();

    // 没有状态层时这一页只显示自带的「已是最新版本」，点检查更新不弹升级窗。
    expect(find.text('已是最新版本'), findsOneWidget);
    expect(find.byKey(const Key('app-update-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('版本说明整行已下线', (tester) async {
    await _pumpAboutPage(tester, const Size(375, 812));

    expect(find.byKey(const Key('about-release-notes')), findsNothing);
    expect(find.text('版本说明'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('about page remains usable at 320x568', (tester) async {
    await _pumpAboutPage(tester, const Size(320, 568));

    final checkUpdate = find.byKey(const Key('about-check-update'));
    await tester.ensureVisible(checkUpdate);
    await tester.pump();

    expect(checkUpdate, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAboutPage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const AboutPage()),
  );
  await tester.pump();
}
