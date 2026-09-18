import 'package:flowerpot/src/features/devices/presentation/widgets/water_level_calibration_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 打开弹窗，记录下发顺序。[accept] 决定每次下发是否被设备收下。
Future<void> _open(
  WidgetTester tester, {
  required List<int> steps,
  required List<bool> cancelled,
  bool Function(int step)? accept,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showWaterLevelCalibrationDialog(
            context,
            onCalibrate: (step) async {
              steps.add(step);
              return accept?.call(step) ?? true;
            },
            onCancel: () async => cancelled.add(true),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tapPrimary(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('calibration-primary-button')));
  await tester.pumpAndSettle();
}

Future<void> _tapSecondary(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('calibration-secondary-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('step0 goes out as the dialog opens, before any tap', (
    tester,
  ) async {
    final steps = <int>[];
    final cancelled = <bool>[];
    await _open(tester, steps: steps, cancelled: cancelled);

    expect(steps, <int>[0]);
    expect(find.text('请先移出植物内胆，\n并倒空水仓中的剩余水。'), findsOneWidget);
  });

  testWidgets('each card reports its own step, and 完成 sends nothing', (
    tester,
  ) async {
    final steps = <int>[];
    final cancelled = <bool>[];
    await _open(tester, steps: steps, cancelled: cancelled);

    // 三次「下一步」把 step1/2/3 带出去，第四次是「完成」，只关闭。
    for (var index = 0; index < 4; index++) {
      await _tapPrimary(tester);
    }

    expect(steps, <int>[0, 1, 2, 3]);
    expect(cancelled, isEmpty);
    expect(
      find.byKey(const Key('water-level-calibration-dialog')),
      findsNothing,
    );
  });

  testWidgets('cancelling part way through releases the device with step5', (
    tester,
  ) async {
    final steps = <int>[];
    final cancelled = <bool>[];
    await _open(tester, steps: steps, cancelled: cancelled);

    await _tapPrimary(tester);
    await _tapSecondary(tester);

    expect(steps, <int>[0, 1]);
    expect(cancelled, <bool>[true]);
    expect(
      find.byKey(const Key('water-level-calibration-dialog')),
      findsNothing,
    );
  });

  testWidgets('关闭 on the summary card does not cancel a finished sequence', (
    tester,
  ) async {
    final steps = <int>[];
    final cancelled = <bool>[];
    await _open(tester, steps: steps, cancelled: cancelled);

    for (var index = 0; index < 3; index++) {
      await _tapPrimary(tester);
    }
    expect(find.text('校准完成！'), findsOneWidget);
    await _tapSecondary(tester);

    // step0–step3 已经发全，再发 step5 等于作废刚校准好的结果。
    expect(steps, <int>[0, 1, 2, 3]);
    expect(cancelled, isEmpty);
    expect(
      find.byKey(const Key('water-level-calibration-dialog')),
      findsNothing,
    );
  });

  testWidgets('a rejected opening step0 is resent on the first 下一步', (
    tester,
  ) async {
    final steps = <int>[];
    final cancelled = <bool>[];
    var rejectFirst = true;
    await _open(
      tester,
      steps: steps,
      cancelled: cancelled,
      accept: (step) {
        if (step == 0 && rejectFirst) {
          rejectFirst = false;
          return false;
        }
        return true;
      },
    );

    expect(steps, <int>[0]);
    // 开场那条没收下，仍停在第一张卡。
    expect(find.text('请先移出植物内胆，\n并倒空水仓中的剩余水。'), findsOneWidget);

    await _tapPrimary(tester);

    expect(steps, <int>[0, 0, 1]);
    expect(find.text('请向水仓中倒入30mL水，\n并点击“下一步”确认'), findsOneWidget);
  });

  testWidgets('a rejected next step keeps the card and does not resend', (
    tester,
  ) async {
    final steps = <int>[];
    final cancelled = <bool>[];
    await _open(
      tester,
      steps: steps,
      cancelled: cancelled,
      accept: (step) => step != 1,
    );

    await _tapPrimary(tester);
    expect(steps, <int>[0, 1]);
    expect(find.text('请先移出植物内胆，\n并倒空水仓中的剩余水。'), findsOneWidget);

    // 重试只补发失败的那一条，step0 不会再发一遍。
    await _tapPrimary(tester);
    expect(steps, <int>[0, 1, 1]);
  });
}
