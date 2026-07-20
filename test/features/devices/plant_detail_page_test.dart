import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/plant_detail_page.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('plant detail page exposes the Figma content', (tester) async {
    await _pumpPlantDetail(tester, const Size(375, 812));

    expect(find.text('植物详情'), findsOneWidget);
    expect(find.text('冷水花'), findsOneWidget);
    expect(find.text('当前绑定'), findsOneWidget);
    expect(find.text('适宜温度'), findsOneWidget);
    expect(find.text('18-28°C'), findsOneWidget);
    expect(find.text('适宜湿度'), findsOneWidget);
    expect(find.text('50-70%'), findsOneWidget);
    expect(find.text('光照需求'), findsOneWidget);
    expect(find.text('基础信息'), findsOneWidget);
    expect(find.text('Pilea cadierei'), findsOneWidget);
    expect(find.text('银脉冷水花'), findsOneWidget);
    expect(find.text('养护建议'), findsOneWidget);
    expect(
      find.byKey(const Key('plant-detail-image-placeholder')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plant detail content remains scrollable at 320x568', (
    tester,
  ) async {
    await _pumpPlantDetail(tester, const Size(320, 568));

    final target = find.text('生长期每月施一次稀释的液体肥，促进叶片生长更旺盛。');
    await tester.ensureVisible(target);
    await tester.pump();

    expect(target, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unbound plant uses the pending binding chip', (tester) async {
    await _pumpPlantDetail(tester, const Size(375, 812), bound: false);

    expect(find.text('待绑定'), findsOneWidget);
    expect(find.text('当前绑定'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPlantDetail(
  WidgetTester tester,
  Size size, {
  bool bound = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: PlantDetailPage(
        arguments: PlantDetailArguments(plant: _pilea, bound: bound),
      ),
    ),
  );
  await tester.pump();
}

const _pilea = PlantProfile(
  id: 'pilea_cadierei',
  name: '冷水花',
  latinName: 'Pilea cadierei',
  color: Color(0xFF4D8B55),
  moistureTarget: 68,
  lightTarget: 120,
  tip: '喜湿润明亮环境，适合室内桌面或半阴环境栽培。',
);
