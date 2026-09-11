import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/home/models/home_dashboard_model.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_care_banner.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_header.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_plant_overview.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_quick_actions.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_status_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('companion summary scene shows days and battery', (tester) async {
    await _pumpOverview(tester, HomeDashboardScene.withCompanionSummary);

    expect(find.text('已陪伴127天'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('alternate scene hides the companion summary', (tester) async {
    await _pumpOverview(tester, HomeDashboardScene.withoutCompanionSummary);

    expect(find.text('已陪伴127天'), findsNothing);
    expect(find.text('80%'), findsNothing);
    expect(find.text('需水状态'), findsOneWidget);
    expect(find.text('相对湿度'), findsOneWidget);
  });

  testWidgets('home chrome uses the supplied care icon and compact chevrons', (
    tester,
  ) async {
    final model = HomeDashboardModel.fromDevice(device: _fixture, userLabel: '用户');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              HomeCareBanner(
                title: model.careTitle,
                messages: model.careMessages,
              ),
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

  testWidgets('养护建议轮播四条状态建议，8 秒换一条', (tester) async {
    final model = HomeDashboardModel.fromDevice(device: _fixture, userLabel: '用户');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: HomeCareBanner(
            title: model.careTitle,
            messages: model.careMessages,
          ),
        ),
      ),
    );

    // 没有设备时四条状态走兜底档：喝水中 / 正合适 / 正舒适 / 正舒服。
    expect(model.careMessages, hasLength(4));
    expect(find.text('今日养护'), findsOneWidget);
    expect(find.text(model.careMessages[0]), findsOneWidget);
    expect(find.text(model.careMessages[1]), findsNothing);

    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text(model.careMessages[1]), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text(model.careMessages[2]), findsOneWidget);

    // 四条播完回到第一条。
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text(model.careMessages[3]), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text(model.careMessages[0]), findsOneWidget);
  });

  testWidgets('顶栏正中显示设备名称，没有设备时仍是品牌标识', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: HomeHeader(userLabel: '用户', title: 'YSplanter-01'),
        ),
      ),
    );

    expect(find.byKey(const Key('home-device-name')), findsOneWidget);
    expect(find.text('YSplanter-01'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: HomeHeader(userLabel: '用户')),
      ),
    );

    expect(find.byKey(const Key('home-device-name')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('养护建议与状态卡片同源，并跟随界面语言', () {
    final zh = HomeDashboardModel.fromDevice(device: _fixture, userLabel: '用户');
    expect(zh.careTitle, '今日养护');
    expect(zh.careMessages, <String>[
      TuyaStatusCopy.waterNeeds[WaterNeedsStatus.drinking]!.description,
      TuyaStatusCopy.lighting[LightingCondition.good]!.description,
      TuyaStatusCopy.airTemperature[ComfortLevel.suitable]!.description,
      TuyaStatusCopy.airHumidity[ComfortLevel.suitable]!.description,
    ]);

    final en = HomeDashboardModel.fromDevice(
      device: _fixture,
      userLabel: 'User',
      language: 'en',
    );
    expect(en.careTitle, "Today's care");
    expect(en.careMessages, <String>[
      TuyaStatusCopy.waterNeedsEn[WaterNeedsStatus.drinking]!.description,
      TuyaStatusCopy.lightingEn[LightingCondition.good]!.description,
      TuyaStatusCopy.airTemperatureEn[ComfortLevel.suitable]!.description,
      TuyaStatusCopy.airHumidityEn[ComfortLevel.suitable]!.description,
    ]);
    expect(en.metrics.first.label, 'Water');
    expect(
      en.metrics.first.value,
      TuyaStatusCopy.waterNeedsEn[WaterNeedsStatus.drinking]!.label,
    );
  });
}

Future<void> _pumpOverview(
  WidgetTester tester,
  HomeDashboardScene scene,
) async {
  final model = HomeDashboardModel.fromDevice(
    device: _fixture,
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

SmartPlanterDevice get _fixture => MockTuyaRepository.fixtureDevice.copyWith(
  battery: 80,
  sensors: const SensorSnapshot(waterLevel: 78, soilMoisture: 60,
    illuminance: 800, ppfd: 6, airTemperature: 25.5, relativeHumidity: 60),
);
