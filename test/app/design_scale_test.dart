import 'package:flowerpot/src/app/design_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 全局按设计稿缩放（2026-09-23）：手机宽度下页面在 375 宽的坐标系里排版，整体等比放大到屏宽。
void main() {
  setUp(() => DesignScale.enabled = true);
  tearDown(() => DesignScale.enabled = false);

  testWidgets('412 宽的屏：页面拿到 375 宽，画出来撑满屏宽，点击位置对得上', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Size? seen;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => DesignScale(child: child!),
        home: Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  key: const Key('box'),
                  onTap: () => taps++,
                  child: const SizedBox(width: 187.5, height: 100),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(seen!.width, DesignScale.designWidth);
    expect(seen!.height, closeTo(915 * 375 / 412, .01));
    // 375 坐标系里半屏宽的块，画到 412 的屏上也是半屏宽
    expect(tester.getSize(find.byKey(const Key('box'))).width, closeTo(206, .01));
    await tester.tap(find.byKey(const Key('box')));
    expect(taps, 1);
  });

  testWidgets('375 宽、平板宽度都不缩放', (tester) async {
    expect(DesignScale.scaleFor(375), 1);
    expect(DesignScale.scaleFor(800), 1);
    expect(DesignScale.scaleFor(412), closeTo(412 / 375, 1e-9));
  });
}
