import 'package:flowerpot/src/features/mower/presentation/widgets/mower_start_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('整小时默认值向下取整，18点后不跨天', () {
    expect(mowerStartMaxHours(DateTime(2026, 10, 10, 12, 30)), 5);
    expect(mowerStartMaxHours(DateTime(2026, 10, 10, 17)), 1);
    expect(mowerStartMaxHours(DateTime(2026, 10, 10, 17, 0, 1)), 0);
    expect(mowerStartMaxHours(DateTime(2026, 10, 10, 18)), 0);
    expect(mowerStartMaxHours(DateTime(2026, 10, 10, 23)), 0);
    expect(mowerStartMaxHours(DateTime(2026, 10, 11)), 18);
  });

  testWidgets('安全确认正文完整，取消不确认，每次打开重新确认', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  results.add(await showMowerSafetyDialog(context)),
              child: const Text('启动'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('启动'));
    await tester.pumpAndSettle();
    expect(find.text('启动安全提醒'), findsOneWidget);
    expect(
      find.text(
        '请确保您已站在割草机旁边，且设备周围 10 米内没有儿童、宠物或障碍物。\n'
        '启动后刀盘将高速旋转，请勿靠近。',
      ),
      findsOneWidget,
    );
    expect(find.text('我已确认，周围安全'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(results, <bool>[false]);

    await tester.tap(find.text('启动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已确认，周围安全'));
    await tester.pumpAndSettle();
    expect(results, <bool>[false, true]);

    await tester.tap(find.text('启动'));
    await tester.pumpAndSettle();
    expect(find.text('启动安全提醒'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(results, <bool>[false, true, false]);
    expect(find.text('启动'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
