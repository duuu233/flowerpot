import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/plant_detail_page.dart';
import 'package:flowerpot/src/features/devices/presentation/plant_picker_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('plant picker exposes the Figma content', (tester) async {
    await _pumpPlantPicker(tester, const Size(375, 812));

    expect(find.text('添加植物'), findsOneWidget);
    expect(find.text('搜索植物名称'), findsOneWidget);
    expect(find.text('选择植物，获取更精准的养护建议'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('绿萝'), findsOneWidget);
    expect(find.text('常春藤'), findsOneWidget);
    expect(find.byKey(const Key('plant-card-monstera')), findsOneWidget);
    expect(find.text('天堂鸟'), findsOneWidget);
    expect(find.text('幸福树'), findsOneWidget);
    expect(find.text('确认添加'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plant selection moves the selected treatment', (tester) async {
    await _pumpPlantPicker(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('plant-card-pothos')));
    await tester.pump();

    expect(find.text('绿萝'), findsNothing);
    expect(find.text('查看详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing plant switches the page to selection mode', (
    tester,
  ) async {
    await _pumpPlantPicker(
      tester,
      const Size(375, 812),
      withExistingPlant: true,
    );

    expect(find.text('选择植物'), findsOneWidget);
    expect(find.text('确认选择'), findsOneWidget);
    expect(find.text('添加植物'), findsNothing);
    expect(find.text('确认添加'), findsNothing);
    expect(find.byKey(const Key('plant-card-monstera')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirming an added plant returns to the home shell', (
    tester,
  ) async {
    var shellOpened = false;
    await _pumpPlantPicker(
      tester,
      const Size(375, 812),
      onShellOpened: () => shellOpened = true,
    );

    await tester.tap(find.byKey(const Key('confirm-plant-selection')));
    await tester.pumpAndSettle();

    expect(find.text('home-shell-target'), findsOneWidget);
    expect(shellOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected plant details opens the detail page', (tester) async {
    await _pumpPlantPicker(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('plant-details-pilea_cadierei')));
    await tester.pumpAndSettle();

    expect(find.text('植物详情'), findsOneWidget);
    expect(find.text('冷水花'), findsOneWidget);
    expect(find.text('Pilea cadierei'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plant search filters by Chinese name', (tester) async {
    await _pumpPlantPicker(tester, const Size(375, 812));

    await tester.enterText(find.byKey(const Key('plant-search-field')), '龟背竹');
    await tester.pump();

    expect(find.byKey(const Key('plant-card-monstera')), findsOneWidget);
    expect(find.text('绿萝'), findsNothing);
    expect(find.text('常春藤'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plant picker remains scrollable at 320x568', (tester) async {
    await _pumpPlantPicker(tester, const Size(320, 568));

    final target = find.byKey(const Key('plant-card-china_doll'));
    await tester.drag(
      find.byKey(const Key('plant-picker-scroll-view')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    expect(target, findsOneWidget);
    expect(find.text('确认添加'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPlantPicker(
  WidgetTester tester,
  Size size, {
  bool withExistingPlant = false,
  VoidCallback? onShellOpened,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.shell) {
            onShellOpened?.call();
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Center(child: Text('home-shell-target')),
              ),
            );
          }
          if (settings.name == AppRoutes.plantDetail) {
            return MaterialPageRoute<void>(
              builder: (_) => PlantDetailPage(
                arguments: settings.arguments! as PlantDetailArguments,
              ),
              settings: settings,
            );
          }
          return null;
        },
        home: PlantPickerPage(
          deviceId: 'unplanted-device',
          mode: withExistingPlant ? PlantPickerMode.select : null,
        ),
      ),
    ),
  );
  await tester.pump();
}
