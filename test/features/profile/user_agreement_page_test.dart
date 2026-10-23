import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/profile/presentation/legal_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('user agreement matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpAgreementPage(tester, const Size(375, 812));

    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('《东方金穗用户协议》'), findsOneWidget);
    expect(find.text('更新日期：2026-6-13'), findsOneWidget);
    expect(find.text('生效日期：2026-6-13'), findsOneWidget);
    expect(find.text('前言'), findsOneWidget);
    expect(find.text('一、服务说明'), findsOneWidget);
    expect(find.textContaining('本协议是您与东方金穗服务提供方之间'), findsOneWidget);
    expect(find.textContaining('本应用为智能花盆设备提供移动端管理服务'), findsOneWidget);
    expect(find.byKey(const Key('legal-document-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('user agreement can scroll to the final section', (tester) async {
    await _pumpAgreementPage(tester, const Size(375, 812));

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

  testWidgets('user agreement remains scrollable at 320x568', (tester) async {
    await _pumpAgreementPage(tester, const Size(320, 568));

    final accountSection = find.byKey(const Key('legal-section-2'));
    await tester.ensureVisible(accountSection);
    await tester.pump();

    expect(find.text('二、账号注册与使用规则'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAgreementPage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const LegalPage(privacy: false)),
  );
  await tester.pump();
}
