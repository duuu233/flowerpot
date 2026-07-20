import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/profile/presentation/legal_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('privacy policy matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpLegalPage(tester, const Size(375, 812));

    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('《YSplanter 隐私政策》'), findsOneWidget);
    expect(find.text('更新日期：2026-6-13'), findsOneWidget);
    expect(find.text('生效日期：2026-6-13'), findsOneWidget);
    expect(find.text('前言'), findsOneWidget);
    expect(find.text('一、我们收集哪些信息？'), findsOneWidget);
    expect(find.byKey(const Key('legal-document-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy policy can scroll to the final section', (tester) async {
    await _pumpLegalPage(tester, const Size(375, 812));

    final finalSection = find.byKey(const Key('legal-section-9'));
    await tester.scrollUntilVisible(
      finalSection,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('九、联系我们'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agreement route keeps its own document content', (tester) async {
    await _pumpLegalPage(tester, const Size(375, 812), privacy: false);

    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('《YSplanter 用户协议》'), findsOneWidget);
    expect(find.text('一、服务内容'), findsOneWidget);
    expect(find.text('《YSplanter 隐私政策》'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy policy remains scrollable at 320x568', (tester) async {
    await _pumpLegalPage(tester, const Size(320, 568));

    final collectionSection = find.byKey(const Key('legal-section-1'));
    await tester.ensureVisible(collectionSection);
    await tester.pump();

    expect(collectionSection, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpLegalPage(
  WidgetTester tester,
  Size size, {
  bool privacy = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: LegalPage(privacy: privacy),
    ),
  );
  await tester.pump();
}
