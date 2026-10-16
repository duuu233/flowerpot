import 'dart:convert';
import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/core/network/network.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  for (final size in [const Size(375, 812), const Size(320, 568)]) {
    for (final imageSelected in [false, true]) {
      testWidgets('纪念日切换保留两份草稿，保存仅保留所选类型 image=$imageSelected $size', (
        tester,
      ) async {
        final entry = MemorialEntry(
          id: 7,
          date: DateTime(2026, 10, 16),
          title: '纪念日',
          type: MemorialContentType.image,
          content: 'https://example.test/old.jpg',
        );
        final requests = <http.Request>[];
        final backend = _memorialBackend(entry, requests);
        final result = await _pumpEditPage(
          tester,
          entry,
          backend: backend,
          size: size,
        );
        expect(find.text('内容 （类型二选一）'), findsOneWidget);
        await _switchType(tester, false);
        await tester.enterText(
          find.byKey(const Key('memorial-text-field')),
          '新的祝福',
        );
        await _switchType(tester, true);
        expect(
          tester
              .widget<Image>(
                find.descendant(
                  of: find.byKey(const Key('memorial-image-slot')),
                  matching: find.byType(Image),
                ),
              )
              .image,
          isA<NetworkImage>().having(
            (image) => image.url,
            'url',
            entry.content,
          ),
        );
        await _switchType(tester, false);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('memorial-text-field')))
              .controller!
              .text,
          '新的祝福',
        );
        expect(requests, isEmpty, reason: '切换不能调用保存或清除接口');
        if (imageSelected) await _switchType(tester, true);
        await tester.tap(find.byKey(const Key('memorial-save')));
        await tester.tap(find.byKey(const Key('memorial-save')));
        await tester.pumpAndSettle();
        final edits = requests
            .where((r) => r.url.path.endsWith('editUserProductAnniversary'))
            .toList();
        expect(edits, hasLength(1), reason: '同一次保存只发一次内容更新');
        final body = jsonDecode(edits.single.body) as Map<String, dynamic>;
        expect(body['contentType'], imageSelected ? 1 : 0);
        expect(body['content'], imageSelected ? entry.content : '新的祝福');
        expect(body.keys.toSet(), {
          'anniversaryId',
          'deviceId',
          'title',
          'content',
          'contentType',
          'anniversaryDate',
        });
        expect(requests, hasLength(2), reason: '一次内容更新和既有启停更新，不另发清除请求');
        final saved = result.state.customMemorialsFor('device-01').single;
        expect(
          saved.type,
          imageSelected ? MemorialContentType.image : MemorialContentType.text,
        );
        expect(saved.content, imageSelected ? entry.content : '新的祝福');
        final frame = TuyaMemorialCodec.decodeRaw(
          result.repository.lastDps![154],
        )!;
        expect(frame[8], imageSelected ? 2 : 1);
        expect(
          utf8.decode(frame.sublist(10)),
          imageSelected ? entry.content : '新的祝福',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('文字切图片不借用原文字，空图片保存不写入且切回保留文字', (tester) async {
    final entry = MemorialEntry(
      id: 8,
      date: DateTime(2026, 10, 16),
      title: '纪念日',
      type: MemorialContentType.text,
      content: '原文字',
    );
    final requests = <http.Request>[];
    final result = await _pumpEditPage(
      tester,
      entry,
      backend: _memorialBackend(entry, requests),
    );
    await _switchType(tester, true);
    expect(find.text('上传图片'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('memorial-image-slot')),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('memorial-save')));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(result.repository.lastDps, isNull);
    await _switchType(tester, false);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('memorial-text-field')))
          .controller!
          .text,
      '原文字',
    );
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('custom fields paint no theme fill inside the grey box', (
    tester,
  ) async {
    // 全局 inputDecorationTheme 是白底 + 胶囊边框，漏进来就是灰框里套一个紧贴文字的
    // 白胶囊（2026-09-13 产品反馈）。两个输入框都必须把底色和边框显式关掉。
    await _pumpEditPage(
      tester,
      MemorialEntry(
        id: 7,
        date: DateTime(2026, 8, 31),
        type: MemorialContentType.text,
        content: '',
      ),
    );

    for (final key in const <Key>[
      Key('memorial-title-field'),
      Key('memorial-text-field'),
    ]) {
      final decoration = tester.widget<TextField>(find.byKey(key)).decoration!;
      expect(decoration.filled, isFalse, reason: '$key');
      expect(decoration.border, InputBorder.none, reason: '$key');
      expect(decoration.enabledBorder, InputBorder.none, reason: '$key');
      expect(decoration.focusedBorder, InputBorder.none, reason: '$key');
    }
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
    expect(result.state.customMemorialsFor('device-01').single.title, '认识100天');
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
    await tester.enterText(
      find.byKey(const Key('memorial-text-field')),
      '生日快乐',
    );
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
  MemorialEntry entry, {
  AppBackendRepository? backend,
  Size size = const Size(375, 812),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _MemorialRepository();
  final state = FlowerpotState(
    repository: repository,
    backendRepository: backend,
  );
  addTearDown(state.dispose);
  await state.refreshDevices();
  if (backend != null) await state.refreshMemorials('device-01');
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

Future<void> _switchType(WidgetTester tester, bool image) async {
  final tab = find.byKey(
    Key(image ? 'memorial-type-image' : 'memorial-type-text'),
  );
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

HttpAppBackendRepository _memorialBackend(
  MemorialEntry entry,
  List<http.Request> writes,
) {
  final session = ApiSession(storageKey: 'memorial.exclusive')
    ..setToken('test-token');
  return HttpAppBackendRepository(
    client: ApiClient(
      baseUrl: 'https://example.test',
      session: session,
      httpClient: MockClient((request) async {
        Object? data = true;
        if (request.url.path.endsWith('getProductAnniversaryList')) {
          data = {
            'pageData': [
              {
                'anniversaryId': entry.id,
                'deviceId': 'device-01',
                'title': entry.title,
                'anniversaryDate': entry.dateLabel,
                'contentType': entry.type == MemorialContentType.image ? 1 : 0,
                'content': entry.content,
              },
            ],
          };
        } else {
          writes.add(request);
        }
        return http.Response(
          jsonEncode({'retCode': 200, 'retMsg': 'ok', 'retData': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    ),
  );
}
