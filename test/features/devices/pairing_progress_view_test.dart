import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/pairing_progress_view.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ⚠️ 进行中的那一步是一个一直在转的圈：这里不能用 pumpAndSettle，它等不到"安定"。

  testWidgets('正在执行的那一步画转圈：已完成是对勾，等待中仍是序号', (tester) async {
    await _pump(tester, PairingStage.sendingWifi);

    expect(find.byKey(const Key('pairing-step-spinner-1')), findsOneWidget);
    expect(find.byKey(const Key('pairing-step-spinner-0')), findsNothing);
    expect(find.byKey(const Key('pairing-step-spinner-2')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // 第一步已完成 → 对勾；第三步等待中 → 仍画序号 3；第二步不再画序号 2。
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('第二步说明文案（2026-09-14 产品定稿）', (tester) async {
    await _pump(tester, PairingStage.sendingWifi);

    expect(find.text('正在把Wi-Fi信息同步给设备，请勿离开本页面'), findsOneWidget);
    expect(find.textContaining('名称和密码发给设备'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('第三步进行中：前两步都是对勾，转圈落在第三步', (tester) async {
    await _pump(tester, PairingStage.connectingCloud);

    expect(find.byKey(const Key('pairing-step-spinner-2')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, PairingStage stage) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: PairingProgressView(stage: stage, onCancel: () {}),
      ),
    ),
  );
  await tester.pump();
}
