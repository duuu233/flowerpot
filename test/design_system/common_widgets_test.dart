import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/asset_finder.dart';

void main() {
  testWidgets('trailing chevron uses the compact shared dimension', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppTrailingChevron())),
    );

    final image = tester.widget<Image>(
      findAssetImage(AppAssets.chevronRightIcon),
    );
    expect(AppTrailingChevron.dimension, 14);
    expect(image.width, AppTrailingChevron.dimension);
    expect(image.height, AppTrailingChevron.dimension);
  });

  Widget app(Widget child) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    );
  }

  testWidgets('primary button forwards taps and blocks taps while loading', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      app(AppPrimaryButton(label: '继续', onPressed: () => taps++)),
    );
    await tester.tap(find.text('继续'));
    expect(taps, 1);

    await tester.pumpWidget(
      app(
        AppPrimaryButton(label: '继续', loading: true, onPressed: () => taps++),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    expect(taps, 1);
  });

  testWidgets('load state view renders empty and error states', (tester) async {
    await tester.pumpWidget(
      app(
        const AppLoadStateView(
          state: AppLoadState.empty,
          content: SizedBox(),
          emptyTitle: '暂无设备',
          emptyMessage: '请先添加设备',
        ),
      ),
    );
    expect(find.text('暂无设备'), findsOneWidget);
    expect(find.text('请先添加设备'), findsOneWidget);

    await tester.pumpWidget(
      app(
        const AppLoadStateView(
          state: AppLoadState.error,
          content: SizedBox(),
          errorMessage: '加载失败',
        ),
      ),
    );
    expect(find.text('加载失败'), findsOneWidget);
  });

  testWidgets('time range selector reports selection', (tester) async {
    String? selected;
    await tester.pumpWidget(
      app(
        TimeRangeSelector<String>(
          values: const <String>['日', '周', '月'],
          selected: '日',
          labelBuilder: (value) => value,
          onChanged: (value) => selected = value,
        ),
      ),
    );
    await tester.tap(find.text('周'));
    expect(selected, '周');
  });

  testWidgets('back button keeps its tap target while using a smaller arrow', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      app(Center(child: AppBackButton(onPressed: () => tapped = true))),
    );

    final arrow = tester.widget<Image>(
      findAssetImage(AppAssets.chevronLeftIcon),
    );
    expect(arrow.width, 16);
    expect(arrow.height, 16);

    final tapTarget = tester.getSize(find.byType(IconButton));
    expect(tapTarget.width, greaterThanOrEqualTo(48));
    expect(tapTarget.height, greaterThanOrEqualTo(48));

    await tester.tap(find.byType(IconButton));
    expect(tapped, isTrue);
  });
}
