import 'dart:ui' show PointerDeviceKind;

import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/firmware_upgrade_flow.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/standby_settings_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/water_level_calibration_dialog.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_plan_dialogs.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/time_edit_sheet.dart';
import 'package:flowerpot/src/features/profile/presentation/widgets/app_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final longMessage = List.filled(60, '故障说明：请检查现场，排除故障后再重试。').join('\n');

Future<void> openModal(
  WidgetTester tester,
  void Function(BuildContext) open, {
  Size size = const Size(375, 812),
  double scale = 1,
  double keyboard = 0,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme().copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

RawScrollbar overflowingBar(WidgetTester tester) {
  return tester
      .widgetList<RawScrollbar>(find.byType(RawScrollbar))
      .firstWhere((bar) => bar.controller!.position.maxScrollExtent > 0);
}

void expectActionsVisible(WidgetTester tester, List<Key> keys) {
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (final key in keys) {
    final finder = find.byKey(key);
    expect(finder.hitTestable(), findsOneWidget);
    final rect = tester.getRect(finder);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(
      rect.bottom,
      lessThanOrEqualTo(screen.height - tester.view.viewInsets.bottom),
    );
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'long confirmation has a painted draggable thumb on $platform',
      (tester) async {
        await openModal(
          tester,
          (context) {
            showAppDialog(context, title: '设备异常', message: longMessage);
          },
          size: const Size(320, 568),
          scale: 1.8,
          platform: platform,
        );
        final bar = overflowingBar(tester);
        expect(bar.thumbVisibility, isTrue);
        expect(bar.interactive, isTrue);
        expectActionsVisible(tester, [
          const Key('app-dialog-confirm'),
          const Key('app-dialog-cancel'),
        ]);
        final barFinder = find.byWidget(bar);
        final rect = tester.getRect(barFinder);
        final painter = tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: barFinder,
                matching: find.byType(CustomPaint),
              ),
            )
            .map((paint) => paint.foregroundPainter)
            .whereType<ScrollbarPainter>()
            .single;
        final thumbPoint = Offset(rect.width - 2, 10);
        expect(
          painter.hitTestOnlyThumbInteractive(
            thumbPoint,
            PointerDeviceKind.mouse,
          ),
          isTrue,
        );
        await tester.dragFrom(
          rect.topLeft + thumbPoint,
          const Offset(0, 80),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(bar.controller!.offset, greaterThan(0));
        final buttonRect = tester.getRect(
          find.byKey(const Key('app-dialog-confirm')),
        );
        await tester.drag(find.byWidget(bar), const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('app-dialog-confirm'))),
          buttonRect,
        );
        await tester.tap(find.byKey(const Key('app-dialog-cancel')));
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('short content shrinks and paints no scrollbar thumb', (
    tester,
  ) async {
    await openModal(
      tester,
      (context) => showAppDialog(context, title: '提示', message: '已完成'),
    );
    final bar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
    expect(bar.controller!.position.maxScrollExtent, 0);
    expect(
      tester.getSize(find.byType(AppDialogScrollView)).height,
      lessThan(250),
    );
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(RawScrollbar),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((paint) => paint.foregroundPainter)
        .whereType<ScrollbarPainter>()
        .single;
    expect(
      painter.hitTestOnlyThumbInteractive(
        const Offset(1, 1),
        PointerDeviceKind.mouse,
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long explanation and footer keep stacked actions visible above keyboard',
    (tester) async {
      await openModal(
        tester,
        (context) => showAppDialog(
          context,
          title: '输入设备名称',
          message: longMessage,
          stackActions: true,
          content: const TextField(),
          footer: Text(longMessage),
        ),
        size: const Size(375, 812),
        keyboard: 300,
      );
      expect(
        tester.widgetList<RawScrollbar>(find.byType(RawScrollbar)).length,
        2,
      );
      expectActionsVisible(tester, [
        const Key('app-dialog-confirm'),
        const Key('app-dialog-cancel'),
      ]);
    },
  );

  testWidgets('many options scroll to the last option and return it', (
    tester,
  ) async {
    String? chosen;
    await openModal(tester, (context) async {
      chosen = await showAppOptionDialog(
        context,
        title: '选择语言',
        selected: '0',
        options: List.generate(
          50,
          (i) => AppOption(value: '$i', label: '选项 $i'),
        ),
      );
    }, size: const Size(375, 568));
    final bar = overflowingBar(tester);
    expectActionsVisible(tester, [
      const Key('app-option-dialog-confirm'),
      const Key('app-option-dialog-cancel'),
    ]);
    bar.controller!.jumpTo(bar.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项 49'));
    await tester.tap(find.byKey(const Key('app-option-dialog-confirm')));
    await tester.pumpAndSettle();
    expect(chosen, '49');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long App release notes keep optional and forced update actions visible',
    (tester) async {
      for (final force in [false, true]) {
        await openModal(
          tester,
          (context) => showAppUpdateDialog(
            context,
            force: force,
            version: BackendAppVersion(
              versionNo: '1.1.6',
              hasUpdate: true,
              releaseNotes: List.filled(50, '修复设备连接及长内容显示问题。'),
            ),
          ),
          size: const Size(375, 568),
          scale: 1.5,
        );
        overflowingBar(tester);
        expectActionsVisible(tester, [const Key('app-update-now')]);
        expect(
          find.byKey(const Key('app-update-later')),
          force ? findsNothing : findsOneWidget,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('app-update-dialog')),
          force ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'long firmware versions wrap and scroll without hiding update actions',
    (tester) async {
      await openModal(
        tester,
        (context) => showFirmwareUpdateDialog(
          context,
          currentVersion: List.filled(20, '1.2.3456').join('.'),
          availableVersion: List.filled(20, '2.3.4567').join('.'),
        ),
        size: const Size(320, 568),
        scale: 1.5,
      );
      overflowingBar(tester);
      expectActionsVisible(tester, [
        const Key('postpone-firmware-update'),
        const Key('install-firmware-update'),
      ]);
    },
  );

  testWidgets('time editor long body scrolls while cancel/save stay fixed', (
    tester,
  ) async {
    await openModal(
      tester,
      (context) => showTimeEditSheet(
        context,
        builder: (context) => TimeEditSheet(
          title: '编辑周四',
          onSave: () {},
          cancelKey: const Key('cancel'),
          saveKey: const Key('save'),
          child: Text(longMessage),
        ),
      ),
      size: const Size(375, 568),
      scale: 1.5,
    );
    final bar = overflowingBar(tester);
    final before = tester.getRect(find.byKey(const Key('save')));
    await tester.drag(find.byWidget(bar), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('save'))), before);
    expectActionsVisible(tester, [const Key('cancel'), const Key('save')]);
  });

  testWidgets('long mower overlap text does not hide return action', (
    tester,
  ) async {
    await openModal(
      tester,
      (context) => showMowerOverlapDialog(context, message: longMessage),
      size: const Size(320, 568),
      scale: 1.8,
    );
    overflowingBar(tester);
    expectActionsVisible(tester, [const Key('mower-plan-overlap-back')]);
  });

  testWidgets('calibration remains operable on a short large text screen', (
    tester,
  ) async {
    final steps = <int>[];
    await openModal(
      tester,
      (context) => showWaterLevelCalibrationDialog(
        context,
        onCalibrate: (step) async {
          steps.add(step);
          return true;
        },
        onCancel: () async {},
      ),
      size: const Size(320, 360),
      scale: 1.8,
    );
    overflowingBar(tester);
    expectActionsVisible(tester, [
      const Key('calibration-primary-button'),
      const Key('calibration-secondary-button'),
    ]);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('calibration-primary-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(steps, [0, 1, 2, 3]);
  });

  testWidgets('delay dialog outer scroll does not share wheel controllers', (
    tester,
  ) async {
    await openModal(
      tester,
      (context) => showStandbyDelayDialog(context, initialMinutes: 30),
      size: const Size(320, 280),
      scale: 1.5,
    );
    final bar = overflowingBar(tester);
    bar.controller!.jumpTo(bar.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final before = bar.controller!.offset;
    final wheel = tester.widget<ListWheelScrollView>(
      find.byKey(const Key('standby-minute-wheel')),
    );
    final minuteController = wheel.controller! as FixedExtentScrollController;
    final minuteBefore = minuteController.selectedItem;
    await tester.drag(
      find.byKey(const Key('standby-minute-wheel')),
      const Offset(0, -44),
    );
    await tester.pumpAndSettle();
    expect(bar.controller!.offset, before);
    expect(minuteController.selectedItem, isNot(minuteBefore));
    expectActionsVisible(tester, [
      const Key('standby-delay-save'),
      const Key('standby-delay-cancel'),
    ]);
  });

  testWidgets(
    'generic bottom sheet constrains long content and supports scrolling',
    (tester) async {
      await openModal(
        tester,
        (context) => showAppBottomSheet(
          context,
          title: '说明',
          builder: (context) => Text(longMessage),
        ),
        size: const Size(375, 568),
      );
      overflowingBar(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
