import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/profile/presentation/help_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('help center matches the 375x812 Figma content', (tester) async {
    await _pumpHelpPage(tester, const Size(375, 812));

    expect(find.text('帮助中心'), findsOneWidget);
    expect(find.text('如何添加设备？'), findsOneWidget);
    expect(find.text('Wi-Fi配网问题'), findsOneWidget);
    expect(find.text('为什么搜索不到设备？'), findsOneWidget);
    expect(find.text('设备离线了怎么办？'), findsOneWidget);
    expect(find.text('为什么土壤湿度没有变化？'), findsOneWidget);
    expect(find.text('如何重新绑定植物？'), findsOneWidget);
    expect(find.byKey(const Key('help-faq-answer-add-device')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('help center FAQ items expand and collapse independently', (
    tester,
  ) async {
    await _pumpHelpPage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('help-faq-toggle-wifi-pairing')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-faq-answer-add-device')), findsOneWidget);
    expect(
      find.byKey(const Key('help-faq-answer-wifi-pairing')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('help-faq-toggle-add-device')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-faq-answer-add-device')), findsNothing);
    expect(
      find.byKey(const Key('help-faq-answer-wifi-pairing')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('help center remains scrollable at 320x568', (tester) async {
    await _pumpHelpPage(tester, const Size(320, 568));

    final lastQuestion = find.text('如何重新绑定植物？');
    await tester.ensureVisible(lastQuestion);
    await tester.pump();

    expect(lastQuestion, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpHelpPage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const HelpPage()),
  );
  await tester.pump();
}
