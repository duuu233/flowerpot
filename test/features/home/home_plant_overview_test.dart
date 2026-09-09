import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/home/models/home_dashboard_model.dart';
import 'package:flowerpot/src/features/home/presentation/widgets/home_plant_overview.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('已绑定设备首页用后台给这株植物配的图片', (tester) async {
    await _pumpOverview(
      tester,
      _device(imageUrl: 'https://example.com/plant.png'),
    );

    // 只看控件树上挂的是哪张图：测试环境里 `Image.network` 必然加载失败，多 pump
    // 一帧就会走 errorBuilder 换成本地图，那样断言反而不稳。
    final network = tester
        .widgetList<Image>(find.byType(Image))
        .where((image) => image.image is NetworkImage)
        .toList();
    expect(network, hasLength(1));
    expect(
      (network.single.image as NetworkImage).url,
      'https://example.com/plant.png',
    );
  });

  testWidgets('后台没配图片时回落到本地静态图', (tester) async {
    await _pumpOverview(tester, _device());

    expect(findAssetImage(AppAssets.smartPlanterWithPlant), findsOneWidget);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .where((image) => image.image is NetworkImage),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpOverview(
  WidgetTester tester,
  SmartPlanterDevice device,
) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final model = HomeDashboardModel.fromDevice(device: device, userLabel: '我');
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: HomePlantOverview(model: model, onMetricTap: (_) {}),
      ),
    ),
  );
}

SmartPlanterDevice _device({String? imageUrl}) => SmartPlanterDevice(
  id: 'device-01',
  productId: 'product-01',
  name: 'YSplanter-01',
  online: true,
  signal: 86,
  battery: 94,
  charging: false,
  boundAt: DateTime.now().subtract(const Duration(days: 51)),
  plant: PlantProfile(
    id: 'pilea_cadierei',
    name: '冷水花',
    latinName: 'Pilea cadierei',
    color: const Color(0xFF4D8B55),
    moistureTarget: 68,
    lightTarget: 120,
    tip: '喜湿润明亮环境。',
    tuyaIdentifier: 'pilea_cadierei',
    imageUrl: imageUrl,
  ),
  sensors: const SensorSnapshot(
    waterLevel: 80,
    soilMoisture: 97,
    illuminance: 305,
    ppfd: 5.642,
    airTemperature: 26.9,
    relativeHumidity: 52,
  ),
  settings: const DeviceControlSettings(),
  firmwareVersion: '1.0.0',
  macAddress: 'D8:85:AC:A2:B9:B4',
);
