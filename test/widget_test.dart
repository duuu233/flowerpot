import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('preview hub is the default entry and pages return to it', (
    tester,
  ) async {
    await _pumpPreviewHub(tester, const Size(375, 812));

    expect(find.text('页面场景\n调试目录'), findsOneWidget);
    expect(find.byKey(const Key('preview-search-field')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('preview-scenario-auth-code')),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录账号，连接和管理你的智能设备'), findsOneWidget);
    expect(find.byKey(const Key('preview-return-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('preview-return-button')));
    await tester.pumpAndSettle();

    expect(find.text('页面场景\n调试目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview catalogue reaches the Figma home at 375x812', (
    tester,
  ) async {
    await _openPreviewHome(tester, const Size(375, 812));

    expect(find.text('YSplanter'), findsOneWidget);
    expect(find.text('定制动画'), findsOneWidget);
    expect(find.text('电池状态'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('home remains usable on a compact 320x568 iPhone viewport', (
    tester,
  ) async {
    await _openPreviewHome(tester, const Size(320, 568));

    expect(find.text('YSplanter'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPreviewHub(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.pumpWidget(
    FlowerpotApp(repository: MockTuyaRepository(latency: Duration.zero)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openPreviewHome(WidgetTester tester, Size size) async {
  await _pumpPreviewHub(tester, size);

  await tester.enterText(
    find.byKey(const Key('preview-search-field')),
    '已添加植物',
  );
  await tester.pumpAndSettle();
  final homeButton = find.byKey(
    const ValueKey<String>('preview-scenario-home-companion'),
  );
  await tester.ensureVisible(homeButton);
  await tester.pumpAndSettle();
  await tester.tap(homeButton);
  await tester.pumpAndSettle();
}
