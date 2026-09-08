import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/home/presentation/home_page.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_empty_device_content.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('empty device home matches the 375x812 Figma content', (
    tester,
  ) async {
    await _pumpContent(tester, const Size(375, 812));

    expect(find.bySemanticsLabel('YSplanter'), findsOneWidget);
    expect(find.text('暂无设备'), findsOneWidget);
    expect(find.text('还没有连接智能设备，请先添加设备开始养护吧'), findsOneWidget);
    expect(find.text('添加设备'), findsOneWidget);
    expect(find.text('小提示'), findsOneWidget);
    expect(find.text('1. 打开设备电源\n2. 请将设备放在手机附近'), findsOneWidget);
    // The design's empty state shows the radar-with-router artwork, which the
    // plain orbit blob does not contain.
    expect(
      findAssetImage(AppAssets.pairingDeviceSearchIllustration),
      findsOneWidget,
    );
    final title = tester.widget<Text>(find.text('暂无设备'));
    expect(title.style?.fontSize, 24);
    final buttonBottom = tester
        .getBottomLeft(find.byKey(const Key('add-device-button')))
        .dy;
    final tipTop = tester
        .getTopLeft(find.byKey(const Key('empty-device-tip-card')))
        .dy;
    expect(tipTop - buttonBottom, AppSpacing.xxl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty device action remains usable at 320x568', (tester) async {
    var tapped = false;
    await _pumpContent(
      tester,
      const Size(320, 568),
      onAddDevice: () => tapped = true,
    );

    final action = find.byKey(const Key('add-device-button'));
    await tester.ensureVisible(action);
    await tester.pump();
    await tester.tap(action);

    expect(tapped, isTrue);
    expect(find.text('小提示'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home page uses the empty device scene when no device exists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      ),
    );
    await tester.pump();

    expect(find.text('暂无设备'), findsOneWidget);
    expect(find.text('添加设备'), findsOneWidget);
    expect(findAssetImage(AppAssets.homeBackground), findsNothing);
    final background = tester.widget<DecoratedBox>(
      find.byKey(const Key('app-page-background')),
    );
    final decoration = background.decoration as BoxDecoration;
    expect(decoration.gradient?.colors, const <Color>[
      AppColors.surface,
      AppColors.surface,
    ]);
    final avatar = findAssetImage(AppAssets.profileAvatarIcon);
    expect(avatar, findsOneWidget);
    expect(tester.getCenter(avatar).dx, lessThan(75));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpContent(
  WidgetTester tester,
  Size size, {
  VoidCallback? onAddDevice,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: HomeEmptyDeviceContent(
          userLabel: '用户',
          onRefresh: () async {},
          onAvatarTap: () {},
          onAddDevice: onAddDevice ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}
