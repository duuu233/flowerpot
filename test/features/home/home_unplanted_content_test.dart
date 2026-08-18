import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/features/home/models/home_dashboard_model.dart';
import 'package:flowerpot/src/features/home/presentation/home_page.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_unplanted_content.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('unplanted scene matches the 375x812 content structure', (
    tester,
  ) async {
    await _pumpScene(tester, const Size(375, 812));

    expect(find.bySemanticsLabel('YSplanter'), findsOneWidget);
    expect(find.text('已陪伴1天'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('还未添加植物'), findsOneWidget);
    final title = tester.widget<Text>(find.text('还未添加植物'));
    expect(title.style?.fontSize, 26);
    expect(find.text('添加植物'), findsOneWidget);
    expect(find.text('需水状态'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unplanted scene scrolls to its action at 320x568', (
    tester,
  ) async {
    var tapped = false;
    await _pumpScene(
      tester,
      const Size(320, 568),
      onAddPlant: () => tapped = true,
    );

    final action = find.text('添加植物');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);

    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unplanted home keeps the full-screen dashboard background', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    final model = HomeDashboardModel.fromDevice(
      device: null,
      userLabel: '用户',
      scene: HomeDashboardScene.withoutPlant,
    );

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: HomePage(dashboard: model),
        ),
      ),
    );
    await tester.pump();

    final background = findAssetImage(AppAssets.homeBackground);
    expect(background, findsOneWidget);
    expect(tester.widget<Image>(background).fit, BoxFit.fitWidth);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpScene(
  WidgetTester tester,
  Size size, {
  VoidCallback? onAddPlant,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final model = HomeDashboardModel.fromDevice(
    device: null,
    userLabel: '用户',
    scene: HomeDashboardScene.withoutPlant,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: HomeUnplantedContent(
          model: model,
          onRefresh: () async {},
          onAvatarTap: () {},
          onAddPlant: onAddPlant ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
