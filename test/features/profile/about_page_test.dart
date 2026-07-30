import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/profile/presentation/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('about page matches the 375x812 Figma content', (tester) async {
    await _pumpAboutPage(tester, const Size(375, 812));

    expect(find.text('关于YSplanter'), findsOneWidget);
    expect(find.text('YSplanter'), findsOneWidget);
    expect(find.text('您的智能花盆贴心伴侣'), findsOneWidget);
    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text('V1.0.0'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('已是最新版本'), findsOneWidget);
    expect(find.text('版本说明'), findsOneWidget);
    expect(find.byKey(const Key('about-logo-placeholder')), findsOneWidget);
    expect(find.byKey(const Key('about-version-card')), findsOneWidget);
    expect(findAssetImage(AppAssets.aboutCurrentVersionIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('check update reports the current status', (tester) async {
    await _pumpAboutPage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('about-check-update')));
    await tester.pump();

    expect(find.text('已是最新版本'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('release notes open in the shared bottom sheet', (tester) async {
    await _pumpAboutPage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('about-release-notes')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('about-release-notes-sheet')), findsOneWidget);
    expect(find.text('• 新增智能花盆设备连接与管理能力'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('about page remains usable at 320x568', (tester) async {
    await _pumpAboutPage(tester, const Size(320, 568));

    final releaseNotes = find.byKey(const Key('about-release-notes'));
    await tester.ensureVisible(releaseNotes);
    await tester.pump();

    expect(releaseNotes, findsOneWidget);
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
