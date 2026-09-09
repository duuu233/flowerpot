import '../../support/plant_catalog.dart';
import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/memorial_edit_page.dart';
import 'package:flowerpot/src/features/devices/presentation/memorial_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_memorial_codec.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the list always carries the two fixed memorial days', (
    tester,
  ) async {
    // 158/159 是设备上固定存在的两条，删不掉，所以列表里永远有它们。
    await _pumpMemorialPage(tester);

    expect(find.text('纪念日'), findsOneWidget);
    expect(find.text('自定义纪念日'), findsOneWidget);
    expect(find.text('生日'), findsOneWidget);
    expect(find.text('结婚纪念日'), findsOneWidget);
    // 计数是整份列表：固定两条已经占了 2/12，上限 12 = 10 条自定义 + 生日 + 结婚。
    expect(find.text('2/12条'), findsOneWidget);
    expect(find.byKey(const Key('memorial-add')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a device that reported 158 shows the date', (tester) async {
    await _pumpMemorialPage(tester, birthday: DateTime(2026, 8, 31));

    expect(find.text('2026-08-31'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving the birthday writes eight ASCII bytes to DP 158', (
    tester,
  ) async {
    final result = await _pumpEditPage(
      tester,
      MemorialEntry(
        id: 0,
        date: DateTime(2026, 8, 31),
        type: MemorialContentType.text,
        content: '',
        title: '生日',
        kind: MemorialKind.birthday,
      ),
    );

    // 固定那两条的标题是设备内置的，页面上是纯文本，没有输入框。
    expect(find.byKey(const Key('memorial-fixed-title')), findsOneWidget);
    expect(find.byKey(const Key('memorial-title-field')), findsNothing);

    await tester.tap(find.byKey(const Key('memorial-save')));
    await tester.pumpAndSettle();

    final dps = result.repository.lastDps!;
    expect(dps.keys.single, 158);
    // 固定日期是 8 字节 ASCII，raw 下发按十六进制串。
    expect(dps[158], isA<String>());
    expect((dps[158]! as String).length, 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a custom entry writes one 154 upsert frame', (tester) async {
    final result = await _pumpEditPage(
      tester,
      MemorialEntry(
        id: 0x01020304,
        date: DateTime(2026, 8, 31),
        type: MemorialContentType.text,
        content: '',
      ),
    );

    await tester.enterText(
      find.byKey(const Key('memorial-title-field')),
      '认识100天',
    );
    await tester.enterText(
      find.byKey(const Key('memorial-text-field')),
      '在一起100天啦',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('memorial-save')));
    await tester.pumpAndSettle();

    final dps = result.repository.lastDps!;
    expect(dps.keys.single, 154);
    final frame = dps[154]! as String;
    // ID 是大端 4 字节，帧头能直接看出来。
    expect(frame.startsWith('01020304'), isTrue);
    expect(
      result.state.customMemorialsFor('device-01').single.title,
      '认识100天',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty title is refused before anything is sent', (
    tester,
  ) async {
    final result = await _pumpEditPage(
      tester,
      MemorialEntry(
        id: 5,
        date: DateTime(2026, 8, 31),
        type: MemorialContentType.text,
        content: '',
      ),
    );

    await tester.tap(find.byKey(const Key('memorial-save')));
    await tester.pumpAndSettle();

    expect(result.repository.lastDps, isNull);
    expect(result.state.customMemorialsFor('device-01'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the text tab counts characters against the 15 char cap', (
    tester,
  ) async {
    await _pumpEditPage(
      tester,
      MemorialEntry(
        id: 5,
        date: DateTime(2026, 8, 31),
        type: MemorialContentType.text,
        content: '',
      ),
    );

    expect(find.text('0 / 15'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('memorial-text-field')), '生日快乐');
    await tester.pump();

    expect(find.text('4 / 15'), findsOneWidget);

    await tester.tap(find.byKey(const Key('memorial-type-image')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('memorial-image-slot')), findsOneWidget);
    expect(find.text('上传图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<({FlowerpotState state, _MemorialRepository repository})>
_pumpMemorialPage(WidgetTester tester, {DateTime? birthday}) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _MemorialRepository(birthday: birthday);
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const MemorialPage(deviceId: 'device-01'),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.memorialEdit) {
            return MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Center(child: Text('memorial-edit'))),
            );
          }
          return null;
        },
      ),
    ),
  );
  await tester.pump();
  return (state: state, repository: repository);
}

Future<({FlowerpotState state, _MemorialRepository repository})> _pumpEditPage(
  WidgetTester tester,
  MemorialEntry entry,
) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _MemorialRepository();
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.refreshDevices();
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MemorialEditPage(
          arguments: MemorialEditArguments(
            deviceId: 'device-01',
            entry: entry,
            creating: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (state: state, repository: repository);
}

SmartPlanterDevice _device({DateTime? birthday}) => SmartPlanterDevice(
  id: 'device-01',
  productId: 'product-01',
  name: 'YSplanter-01',
  online: true,
  signal: 86,
  battery: 94,
  charging: false,
  boundAt: DateTime.now().subtract(const Duration(days: 51)),
  plant: PlantCatalog.items.first,
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
  birthday: birthday,
);

class _MemorialRepository extends MockTuyaRepository {
  _MemorialRepository({this.birthday}) : super(latency: Duration.zero);

  final DateTime? birthday;
  Map<int, Object>? lastDps;

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    _device(birthday: birthday),
  ];

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    lastDps = dps;
  }
}
