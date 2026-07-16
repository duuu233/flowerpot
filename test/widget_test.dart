import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('experience mode reaches the Figma home at 375x812', (
    tester,
  ) async {
    await _openExperienceHome(tester, const Size(375, 812));

    expect(find.text('YSplanter'), findsOneWidget);
    expect(find.text('定制动画'), findsOneWidget);
    expect(find.text('电池状态'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('home remains usable on a compact 320x568 iPhone viewport', (
    tester,
  ) async {
    await _openExperienceHome(tester, const Size(320, 568));

    expect(find.text('YSplanter'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openExperienceHome(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.pumpWidget(
    FlowerpotApp(repository: MockTuyaRepository(latency: Duration.zero)),
  );
  await tester.pumpAndSettle();

  expect(find.text('照顾植物，\n也照顾生活。'), findsOneWidget);
  final demoButton = find.text('体验模式');
  await tester.ensureVisible(demoButton);
  await tester.pumpAndSettle();
  await tester.tap(demoButton);
  await tester.pumpAndSettle();
}
