import 'dart:ui' show PointerDeviceKind;
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_plan_edit_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final size in [const Size(375, 812), const Size(320, 568)]) {
      testWidgets(
        '编辑周四 scrollbar is painted before any gesture: $platform $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme().copyWith(platform: platform),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showMowerPlanEditSheet(
                      context,
                      draft: const MowerPlanDraft(
                        day: 4,
                        one: MowerScheduleSlot(
                          startMinutes: 510,
                          endMinutes: 720,
                          enabled: true,
                        ),
                        two: MowerScheduleSlot(
                          startMinutes: 840,
                          endMinutes: 1080,
                          enabled: false,
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(find.text('编辑周四'), findsOneWidget);
          final finder = find.byType(RawScrollbar);
          final bar = tester.widget<RawScrollbar>(finder);
          expect(bar.thumbVisibility, isTrue);
          expect(bar.trackVisibility, isTrue);
          expect(bar.thumbColor, AppColors.brandDark);
          expect(bar.trackColor, AppColors.brandSurface);
          expect(bar.radius, const Radius.circular(4));
          expect(bar.thickness, 4);
          expect(bar.controller!.position.maxScrollExtent, greaterThan(0));
          final rect = tester.getRect(finder);
          final painter = tester
              .widgetList<CustomPaint>(
                find.descendant(of: finder, matching: find.byType(CustomPaint)),
              )
              .map((paint) => paint.foregroundPainter)
              .whereType<ScrollbarPainter>()
              .single;
          final thumbPoint = Offset(rect.width - 2, 12);
          expect(
            painter.hitTestOnlyThumbInteractive(
              thumbPoint,
              PointerDeviceKind.mouse,
            ),
            isTrue,
          );
          await tester.pump(const Duration(seconds: 2));
          expect(
            painter.hitTestOnlyThumbInteractive(
              thumbPoint,
              PointerDeviceKind.mouse,
            ),
            isTrue,
            reason: '首次可见且不会在等待时淡出',
          );
          final save = find.byKey(const Key('mower-plan-edit-save'));
          final cancel = find.byKey(const Key('mower-plan-edit-cancel'));
          expect(save.hitTestable(), findsOneWidget);
          expect(cancel.hitTestable(), findsOneWidget);
          final buttonRect = tester.getRect(save);
          await tester.dragFrom(
            rect.topLeft + thumbPoint,
            const Offset(0, 60),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          expect(bar.controller!.offset, greaterThan(0));
          bar.controller!.jumpTo(bar.controller!.position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('mower-plan-edit-copy-week')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.getRect(save), buttonRect);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('mower-plan-edit-title')), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
