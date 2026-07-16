import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/home/models/home_dashboard_model.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_plant_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('companion summary scene shows days and battery', (tester) async {
    await _pumpOverview(tester, HomeDashboardScene.withCompanionSummary);

    expect(find.text('已陪伴52天'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('alternate scene hides the companion summary', (tester) async {
    await _pumpOverview(tester, HomeDashboardScene.withoutCompanionSummary);

    expect(find.text('已陪伴52天'), findsNothing);
    expect(find.text('80%'), findsNothing);
    expect(find.text('需水状态'), findsOneWidget);
    expect(find.text('相对湿度'), findsOneWidget);
  });
}

Future<void> _pumpOverview(
  WidgetTester tester,
  HomeDashboardScene scene,
) async {
  final model = HomeDashboardModel.fromDevice(
    device: null,
    userLabel: '用户',
    scene: scene,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 335,
            child: HomePlantOverview(model: model, onMetricTap: (_) {}),
          ),
        ),
      ),
    ),
  );
}
