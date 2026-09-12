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
    // 一张图都没有时底部只留上传按钮：删除选中和取消选择这时候点了也没对象。
    expect(find.byKey(const Key('animation-upload-action')), findsOneWidget);
    expect(find.byKey(const Key('animation-delete-action')), findsNothing);
    expect(
      find.byKey(const Key('animation-clear-selection-action')),
      findsNothing,
    );
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

  testWidgets('有图时画图库网格，虚线上传位让位给它', (tester) async {
    final state = await _uploadOne(tester);
    await _pumpWithState(tester, state, const Size(375, 812));

    // v2 设计稿里有图那一屏没有虚线上传位，只有「已上传文件」这张卡。
    expect(find.byKey(AnimationsPage.uploadZoneKey), findsNothing);
    expect(find.text('已上传文件'), findsOneWidget);
    expect(find.byKey(const Key('animation-tile-0')), findsOneWidget);
    final count = tester.widget<Text>(
      find.byKey(const Key('animation-file-count')),
    );
    expect(count.data, '1/10');
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部按钮按「有没有选中图片」换面孔', (tester) async {
    final state = await _uploadOne(tester);
    await _pumpWithState(tester, state, const Size(375, 812));

    // 没选中：只有那条长的上传按钮。
    expect(find.byKey(const Key('animation-upload-action')), findsOneWidget);
    expect(find.byKey(const Key('animation-pin-action')), findsNothing);
    expect(find.byKey(const Key('animation-delete-action')), findsNothing);
    expect(
      find.byKey(const Key('animation-clear-selection-action')),
      findsNothing,
    );

    // 选中一张：换成一排功能钮，**第一颗是置顶**（DP 157），上传变成图标继续留着。
    await tester.tap(find.byKey(const Key('animation-tile-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('animation-pin-action')), findsOneWidget);
    expect(find.byKey(const Key('animation-upload-icon-action')), findsOneWidget);
    expect(find.byKey(const Key('animation-delete-action')), findsOneWidget);
    expect(
      find.byKey(const Key('animation-clear-selection-action')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('animation-upload-action')), findsNothing);

    // 取消选中：切回长按钮。
    await tester.tap(find.byKey(const Key('animation-clear-selection-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('animation-upload-action')), findsOneWidget);
    expect(find.byKey(const Key('animation-pin-action')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部按钮悬浮固定，滚到底最后一行也不会被压住', (tester) async {
    // 九张图三行网格，矮屏上一定滚得动。
    final state = await _uploadMany(tester, 9);
    await _pumpWithState(tester, state, const Size(320, 568));

    final upload = find.byKey(const Key('animation-upload-action'));
    final firstTile = find.byKey(const Key('animation-tile-0'));
    final barRect = tester.getRect(upload);
    final tileTop = tester.getRect(firstTile).top;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();

    // 内容滚上去了，按钮条还钉在原地。
    expect(tester.getRect(firstTile).top, lessThan(tileTop));
    expect(tester.getRect(upload), barRect);

    // 滚到底：内容底部留的位置要够，最后一行缩略图不能钻到按钮下面。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final lastTile = tester.getRect(find.byKey(const Key('animation-tile-8')));

    expect(lastTile.bottom, lessThanOrEqualTo(barRect.top));
    expect(tester.getRect(upload), barRect);
    expect(tester.takeException(), isNull);
  });
}

Future<FlowerpotState> _uploadOne(WidgetTester tester) => _uploadMany(tester, 1);

Future<FlowerpotState> _uploadMany(WidgetTester tester, int count) async {
  final state = await _createState(tester);
  for (var index = 0; index < count; index++) {
    await tester.runAsync(
      () => state.addAnimation(
        state.devices.single.id,
        name: 'demo-$index.gif',
        path: 'C:/tmp/demo-$index.gif',
      ),
    );
  }
  return state;
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
