import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/home/models/home_dashboard_model.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_care_banner.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_plant_overview.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_quick_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

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

  testWidgets('home chrome uses the supplied care icon and compact chevrons', (
    tester,
  ) async {
    final model = HomeDashboardModel.fromDevice(device: null, userLabel: '用户');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              HomeCareBanner(message: model.careMessage),
              HomeQuickActions(actions: model.actions, onActionTap: (_) {}),
            ],
          ),
        ),
      ),
    );

    expect(findAssetImage(AppAssets.selectPlantIcon), findsOneWidget);
    expect(findAssetImage(AppAssets.plantIcon), findsNothing);
    final chevrons = findAssetImage(AppAssets.chevronRightIcon);
    expect(chevrons, findsNWidgets(3));
    for (final image in tester.widgetList<Image>(chevrons)) {
      expect(image.width, AppTrailingChevron.dimension);
      expect(image.height, AppTrailingChevron.dimension);
    }
    expect(tester.takeException(), isNull);
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
