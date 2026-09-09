import '../../support/fixture_backend.dart';
import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/animations_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('animation page exposes the Figma empty state', (tester) async {
    final state = await _pumpAnimationsPage(tester, const Size(375, 812));

    expect(find.text('定制动画'), findsOneWidget);
    // 「文件同步」和权限提示条已经下线，上传说明也只提本地图片。
    expect(find.text('文件同步'), findsNothing);
    expect(find.text('仅支持屏幕录制或本地文件。'), findsNothing);
    expect(find.text('点击这里重新授权'), findsNothing);
    expect(find.text('支持本地图片文件上传'), findsOneWidget);
    expect(find.text('提示'), findsOneWidget);
    expect(find.text('上传文件'), findsOneWidget);
    expect(find.text('Files  0/10'), findsOneWidget);
    expect(find.byKey(AnimationsPage.uploadZoneKey), findsOneWidget);
    expect(find.text('清晨问候'), findsNothing);
    expect(state.animations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('提示卡右下角的背景图整块落在卡片里', (tester) async {
    await _pumpAnimationsPage(tester, const Size(375, 812));

    final card = find.ancestor(
      of: find.text('提示'),
      matching: find.byType(AppSurfaceCard),
    );
    expect(card, findsOneWidget);
    final cardRect = tester.getRect(card);
    final illustration = tester.getRect(
      find.byKey(const Key('animation-tips-illustration')),
    );

    // 118 的方图整块都在卡片范围内：右边贴着卡片边缘，底部留 14px。之前卡片留
    // 内边距、图片用负偏移往外顶，Stack 默认的 hardEdge 裁剪把顶出去的下沿直接
    // 切掉了，文件夹缺一块。
    expect(illustration.size, const Size(118, 118));
    expect(illustration.right, moreOrLessEquals(cardRect.right, epsilon: 0.5));
    expect(
      illustration.bottom,
      moreOrLessEquals(cardRect.bottom - 14, epsilon: 0.5),
    );
    expect(illustration.top, greaterThanOrEqualTo(cardRect.top));
    expect(illustration.left, greaterThanOrEqualTo(cardRect.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('animation page remains scrollable at 320x568', (tester) async {
    await _pumpAnimationsPage(tester, const Size(320, 568));

    final formats = find.text('仅支持JPG/GIF等格式');
    await tester.ensureVisible(formats);
    await tester.pump();

    expect(formats, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uploaded files appear and can be deleted with a long press', (
    tester,
  ) async {
    final state = await _createState(tester);
    await tester.runAsync(
      () => state.addAnimation(
        state.devices.single.id,
        name: 'demo.gif',
        path: 'C:/tmp/demo.gif',
      ),
    );
    await _pumpWithState(tester, state, const Size(375, 812));

    expect(find.text('demo.gif'), findsOneWidget);
    expect(find.text('Files  1/10'), findsOneWidget);

    await tester.longPress(find.text('demo.gif'));
    await tester.pump();

    expect(find.text('demo.gif'), findsNothing);
    expect(find.text('Files  0/10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}

Future<FlowerpotState> _pumpAnimationsPage(
  WidgetTester tester,
  Size size,
) async {
  final state = await _createState(tester);
  await _pumpWithState(tester, state, size);
  return state;
}

Future<FlowerpotState> _createState(WidgetTester tester) async {
  final state = FlowerpotState(
    backendRepository: FixtureBackend(),
    repository: MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.runAsync(
    () => state.login(
      account: 'demo@example.test',
      credential: 'demo',
      region: LoginRegion.overseas,
      verificationCode: false,
    ),
  );
  return state;
}

Future<void> _pumpWithState(
  WidgetTester tester,
  FlowerpotState state,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: AnimationsPage(deviceId: state.devices.single.id),
      ),
    ),
  );
  await tester.pump();
}
