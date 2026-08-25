import 'package:flowerpot/src/features/devices/presentation/widgets/water_level_calibration_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the four confirmations report steps 0, 1, 2 and 3', (
    tester,
  ) async {
    final steps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWaterLevelCalibrationDialog(
              context,
              onCalibrate: (step) async {
                steps.add(step);
                return true;
              },
              onCancel: () async {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (var index = 0; index < 4; index++) {
      await tester.tap(find.byKey(const Key('calibration-primary-button')));
      await tester.pumpAndSettle();
    }

    expect(steps, <int>[0, 1, 2, 3]);
    expect(
      find.byKey(const Key('water-level-calibration-dialog')),
      findsNothing,
    );
  });

  testWidgets('cancel invokes the dedicated cancel callback', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWaterLevelCalibrationDialog(
              context,
              onCalibrate: (_) async => true,
              onCancel: () async => cancelled = true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calibration-secondary-button')));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
  });

  testWidgets('closing the summary before confirming step 3 also cancels', (
    tester,
  ) async {
    final steps = <int>[];
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWaterLevelCalibrationDialog(
              context,
              onCalibrate: (step) async {
                steps.add(step);
                return true;
              },
              onCancel: () async => cancelled = true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.byKey(const Key('calibration-primary-button')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('calibration-secondary-button')));
    await tester.pumpAndSettle();

    expect(steps, <int>[0, 1, 2]);
    expect(cancelled, isTrue);
  });
}
