import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
    testWidgets('原类型为文字时，切回只回填接口content，不保留旧编辑草稿 $size', (tester) async {
      await _pumpEditPage(
        tester,
        MemorialEntry(
          id: 8,
          date: DateTime(2026, 10, 21),
          title: '纪念日',
          type: MemorialContentType.text,
          content: '接口文字',
        ),
        size: size,
      );
      final field = find.byKey(const Key('memorial-text-field'));
      expect(tester.widget<TextField>(field).controller!.text, '接口文字');
      await tester.enterText(field, '未保存的修改');
      await _switchType(tester, true);
      expect(find.text('上传图片'), findsOneWidget);
      await _switchType(tester, false);
      expect(tester.widget<TextField>(field).controller!.text, '接口文字');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('纪念日内容用单选按钮切换且始终只选一项', (tester) async {
    await _pumpEditPage(
      tester,
      MemorialEntry(
        id: 7,
        date: DateTime(2026, 10, 20),
        title: '纪念日',
        type: MemorialContentType.text,
        content: '祝福',
      ),
    );
    expect(find.byType(RadioListTile<MemorialContentType>), findsNWidgets(2));
    expect(
      tester
          .widget<RadioGroup<MemorialContentType>>(
            find.byType(RadioGroup<MemorialContentType>),
          )
          .groupValue,
      MemorialContentType.text,
    );
    await _switchType(tester, true);
    expect(
      tester
          .widget<RadioGroup<MemorialContentType>>(
            find.byType(RadioGroup<MemorialContentType>),
          )
          .groupValue,
      MemorialContentType.image,
    );
    await _switchType(tester, true);
    expect(find.byKey(const Key('memorial-image-slot')), findsOneWidget);
    expect(find.byKey(const Key('memorial-text-field')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(375, 812), const Size(320, 568)]) {
    for (final imageSelected in [false, true]) {
      testWidgets('纪念日按原类型回填，另一类型为空且保存仅含所选内容 image=$imageSelected $size', (
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
          isEmpty,
          reason: '原接口类型为图片，切回文字不能恢复旧页面草稿',
        );
        expect(requests, isEmpty, reason: '切换不能调用保存或清除接口');
        if (imageSelected) {
          await _switchType(tester, true);
        } else {
          await tester.enterText(
            find.byKey(const Key('memorial-text-field')),
            '新的祝福',
          );
        }
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
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        // 退出页面，重新请求列表，再建立一个全新的编辑页面。
        await result.state.refreshMemorials('device-01');
        final reopened = result.state.customMemorialsFor('device-01').single;
        expect(reopened.type, saved.type);
        expect(reopened.content, saved.content);
        await tester.pumpWidget(
          FlowerpotScope(
            state: result.state,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: MemorialEditPage(
                arguments: MemorialEditArguments(
                  deviceId: 'device-01',
                  entry: reopened,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _switchType(tester, !imageSelected);
        if (imageSelected) {
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('memorial-text-field')))
                .controller!
                .text,
            isEmpty,
            reason: '保存图片后，重进不能恢复未选中的文字',
          );
        } else {
          expect(find.text('上传图片'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const Key('memorial-image-slot')),
              matching: find.byType(Image),
            ),
            findsNothing,
            reason: '保存文字后，重进不能恢复未选中的图片',
          );
        }
        expect(requests, hasLength(2), reason: '重进与切换不额外写入');
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

  testWidgets('接了后端时拉取失败显示重试，不拿上次拉到的旧列表顶替', (tester) async {
    // 2026-10-21 用户「读取到的数据不做任何缓存」。
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _AnniversaryBackend()..rows = [_anniversary('旧的纪念日')];
    final state = FlowerpotState(
      repository: _MemorialRepository(),
      backendRepository: backend,
    );
    addTearDown(state.dispose);
    await state.refreshDevices();
    await state.refreshMemorials('device-01');
    expect(state.customMemorialsFor('device-01').single.title, '旧的纪念日');

    backend.fail = true;
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const MemorialPage(deviceId: 'device-01'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('纪念日加载失败，请检查网络后重试'), findsOneWidget);
    expect(find.text('旧的纪念日'), findsNothing);
    expect(find.byKey(const Key('memorial-add')), findsNothing);

    backend
      ..fail = false
      ..rows = [_anniversary('新的纪念日')];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('新的纪念日'), findsOneWidget);
    expect(find.text('旧的纪念日'), findsNothing);
    expect(backend.requests, 3);
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

  for (final detailImage in [false, true]) {
    testWidgets('编辑已有纪念日先拉详情再回填，不用列表那一行 image=$detailImage', (
      tester,
    ) async {
      final server = _AnniversaryServer()
        ..rows[9] = _row(
          9,
          title: '详情标题',
          image: detailImage,
          content: detailImage ? 'https://example.test/detail.jpg' : '详情文字',
        )
        // 列表里是另一种类型的旧值：编辑页不能拿它回填。
        ..staleList = <Map<String, Object?>>[
          _row(
            9,
            title: '列表标题',
            image: !detailImage,
            content: detailImage ? '列表文字' : 'https://example.test/list.jpg',
          ),
        ];
      final hold = Completer<void>();
      server.holdDetail = hold.future;
      final result = await _pumpEditPage(
        tester,
        _entryFromRow(server.staleList!.single),
        backend: server.repository(),
        creating: false,
      );
      expect(find.byKey(const Key('memorial-edit-load-state')), findsOneWidget);
      expect(find.byKey(const Key('memorial-save')), findsNothing);
      hold.complete();
      await tester.pumpAndSettle();
      expect(server.detailRequests, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('memorial-title-field')))
            .controller!
            .text,
        '详情标题',
      );
      expect(
        tester
            .widget<RadioGroup<MemorialContentType>>(
              find.byType(RadioGroup<MemorialContentType>),
            )
            .groupValue,
        detailImage ? MemorialContentType.image : MemorialContentType.text,
      );
      if (detailImage) {
        expect(_slotImageUrl(tester), 'https://example.test/detail.jpg');
        expect(find.byKey(const Key('memorial-text-field')), findsNothing);
        await _switchType(tester, false);
        expect(_textFieldValue(tester), isEmpty);
        await _switchType(tester, true);
        expect(_slotImageUrl(tester), 'https://example.test/detail.jpg');
      } else {
        expect(_textFieldValue(tester), '详情文字');
        expect(find.byKey(const Key('memorial-image-slot')), findsNothing);
        await _switchType(tester, true);
        expect(_slotImageUrl(tester), isNull);
        await _switchType(tester, false);
        expect(_textFieldValue(tester), '详情文字');
      }
      // 列表里那一行也换成详情的值。
      final listed = result.state.customMemorialsFor('device-01').single;
      expect(listed.title, '详情标题');
      expect(listed.content, server.rows[9]!['content']);

      await tester.tap(find.byKey(const Key('memorial-save')));
      await tester.pumpAndSettle();
      final body = server.bodyOf('editUserProductAnniversary');
      expect(body['contentType'], detailImage ? 1 : 0);
      expect(body['content'], server.rows[9]!['content']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('详情拉取失败显示重试且不能保存，重试成功后按详情回填', (tester) async {
    final server = _AnniversaryServer()
      ..rows[9] = _row(9, title: '纪念日', image: false, content: '详情文字')
      ..failDetail = true;
    await _pumpEditPage(
      tester,
      _entryFromRow(server.rows[9]!).copyWith(content: '列表文字'),
      backend: server.repository(),
      creating: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('纪念日加载失败，请检查网络后重试'), findsOneWidget);
    expect(find.byKey(const Key('memorial-save')), findsNothing);
    expect(find.byKey(const Key('memorial-text-field')), findsNothing);

    server.failDetail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(server.detailRequests, 2);
    expect(_textFieldValue(tester), '详情文字');
    expect(find.byKey(const Key('memorial-save')), findsOneWidget);
    expect(server.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情文字超过 15 字时回填直接截断，停用后可以直接保存', (tester) async {
    const url = 'https://example.test/upload/anniversary-photo.jpg';
    final server = _AnniversaryServer()
      // 后端把图片地址按文字类型返回：原样填进文字框会被保存时的字数校验挡住。
      ..rows[9] = _row(9, title: '纪念日', image: false, content: url);
    await _pumpEditPage(
      tester,
      _entryFromRow(server.rows[9]!),
      backend: server.repository(),
      creating: false,
    );
    await tester.pumpAndSettle();
    expect(_textFieldValue(tester), url.substring(0, 15));

    await tester.tap(find.byKey(const Key('memorial-enable-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('memorial-save')));
    await tester.pumpAndSettle();
    final body = server.bodyOf('editUserProductAnniversary');
    expect(body['contentType'], 0);
    expect(body['content'], url.substring(0, 15));
    expect(server.bodyOf('setUserProductAnniversaryVerify')['verify'], 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情文字按 45 字节截断，不切半个字符', (tester) async {
    final server = _AnniversaryServer()
      ..rows[9] = _row(9, title: '纪念日', image: false, content: '🎉' * 15);
    await _pumpEditPage(
      tester,
      _entryFromRow(server.rows[9]!),
      backend: server.repository(),
      creating: false,
    );
    await tester.pumpAndSettle();
    // 每个 emoji 4 字节：45 字节以内最多 11 个。
    expect(_textFieldValue(tester), '🎉' * 11);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新增纪念日同样二选一：没选图不保存，文字保存只带 contentType=0', (
    tester,
  ) async {
    final server = _AnniversaryServer();
    await _pumpEditPage(
      tester,
      MemorialEntry(
        id: 77,
        date: DateTime(2026, 10, 27),
        type: MemorialContentType.text,
        content: '',
      ),
      backend: server.repository(),
    );
    expect(server.detailRequests, 0, reason: '新增没有详情可拉');
    await tester.enterText(find.byKey(const Key('memorial-title-field')), '新的');
    await tester.enterText(find.byKey(const Key('memorial-text-field')), '草稿');
    await _switchType(tester, true);
    await tester.tap(find.byKey(const Key('memorial-save')));
    await tester.pumpAndSettle();
    expect(server.writes, isEmpty, reason: '图片类型没有图，不能提交');
    await _switchType(tester, false);
    expect(_textFieldValue(tester), isEmpty, reason: '切换会丢掉没保存的文字');
    await tester.enterText(
      find.byKey(const Key('memorial-text-field')),
      '在一起100天',
    );
    await tester.tap(find.byKey(const Key('memorial-save')));
    await tester.pumpAndSettle();
    final body = server.bodyOf('addUserProductAnniversary');
    expect(body['contentType'], 0);
    expect(body['content'], '在一起100天');
    expect(body.keys.toSet(), {
      'deviceId',
      'title',
      'content',
      'contentType',
      'anniversaryDate',
    });
    expect(tester.takeException(), isNull);
  });

  test('新增图片纪念日先上传，保存只带 contentType=1 和上传后的地址', () async {
    final directory = Directory.systemTemp.createTempSync('memorial-test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final picked = File('${directory.path}/picked.jpg')
      ..writeAsStringSync('jpeg');
    final server = _AnniversaryServer();
    final repository = _MemorialRepository();
    final state = FlowerpotState(
      repository: repository,
      backendRepository: server.repository(),
    );
    addTearDown(state.dispose);
    await state.refreshDevices();
    await state.refreshMemorials('device-01');

    final result = await state.saveMemorial(
      'device-01',
      MemorialEntry(
        id: 77,
        date: DateTime(2026, 10, 27),
        title: '图片纪念日',
        type: MemorialContentType.image,
        content: picked.path,
      ),
    );
    expect(result.success, isTrue, reason: result.message);
    expect(server.uploads, 1);
    final body = server.bodyOf('addUserProductAnniversary');
    expect(body['contentType'], 1);
    expect(body['content'], _AnniversaryServer.uploadedUrl);
    final saved = state.customMemorialsFor('device-01').single;
    expect(saved.type, MemorialContentType.image);
    expect(saved.content, _AnniversaryServer.uploadedUrl);
    final frame = TuyaMemorialCodec.decodeRaw(repository.lastDps![154])!;
    expect(frame[8], 2);
  });

  testWidgets('停用时保存也按二选一校验：所选类型为空不提交', (tester) async {
    final server = _AnniversaryServer()
      ..rows[9] = _row(9, title: '纪念日', image: false, content: '原文字');
    await _pumpEditPage(
      tester,
      _entryFromRow(server.rows[9]!),
      backend: server.repository(),
      creating: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('memorial-enable-switch')));
    await tester.pumpAndSettle();
    await _switchType(tester, true);
    await tester.tap(find.byKey(const Key('memorial-save')));
    await tester.pumpAndSettle();
    expect(server.writes, isEmpty, reason: '停用也不能用空图片覆盖原文字');

    await _switchType(tester, false);
    expect(_textFieldValue(tester), '原文字');
    await tester.tap(find.byKey(const Key('memorial-save')));
    await tester.pumpAndSettle();
    final body = server.bodyOf('editUserProductAnniversary');
    expect(body['contentType'], 0);
    expect(body['content'], '原文字');
    expect(server.bodyOf('setUserProductAnniversaryVerify')['verify'], 0);
    expect(tester.takeException(), isNull);
  });

  test('状态层同样拒绝空内容的自定义纪念日，停用也不例外', () async {
    final repository = _MemorialRepository();
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await state.refreshDevices();
    for (final type in MemorialContentType.values) {
      final result = await state.saveMemorial(
        'device-01',
        MemorialEntry(
          id: 5,
          date: DateTime(2026, 10, 27),
          title: '纪念日',
          type: type,
          content: '  ',
          enabled: false,
        ),
      );
      expect(result.success, isFalse);
    }
    expect(repository.lastDps, isNull);
    expect(state.customMemorialsFor('device-01'), isEmpty);
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
  bool creating = true,
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
            creating: creating,
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
  var persisted = entry;
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
                'anniversaryId': persisted.id,
                'deviceId': 'device-01',
                'title': persisted.title,
                'anniversaryDate': persisted.dateLabel,
                'contentType': persisted.type == MemorialContentType.image
                    ? 1
                    : 0,
                'content': persisted.content,
              },
            ],
          };
        } else {
          writes.add(request);
          if (request.url.path.endsWith('editUserProductAnniversary')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            persisted = persisted.copyWith(
              type: body['contentType'] == 1
                  ? MemorialContentType.image
                  : MemorialContentType.text,
              content: body['content'] as String,
              title: body['title'] as String,
            );
          }
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

BackendAnniversary _anniversary(String title) => BackendAnniversary(
  anniversaryId: 7,
  deviceId: 'device-01',
  title: title,
  content: '祝福',
  imageContent: false,
  date: DateTime(2026, 5, 20),
);

class _AnniversaryBackend extends DisabledAppBackendRepository {
  bool fail = false;
  int requests = 0;
  List<BackendAnniversary> rows = const <BackendAnniversary>[];

  @override
  bool get enabled => true;

  @override
  bool get hasSession => true;

  @override
  Future<List<BackendAnniversary>> getAnniversaries(String deviceId) async {
    requests++;
    if (fail) throw const ApiException('NETWORK_ERROR', '网络异常');
    return rows;
  }
}

String? _slotImageUrl(WidgetTester tester) {
  final images = find.descendant(
    of: find.byKey(const Key('memorial-image-slot')),
    matching: find.byType(Image),
  );
  if (images.evaluate().isEmpty) return null;
  final provider = tester.widget<Image>(images.first).image;
  return provider is NetworkImage ? provider.url : null;
}

String _textFieldValue(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('memorial-text-field')))
    .controller!
    .text;

/// swagger `ClientProductAnniversaryDetailApiOut`：列表和详情都是这个模型。
Map<String, Object?> _row(
  int id, {
  required String title,
  required bool image,
  required String content,
  int verify = 1,
}) => <String, Object?>{
  'anniversaryId': id,
  'deviceId': 'device-01',
  'title': title,
  'anniversaryDate': '2026-10-20',
  'contentType': image ? 1 : 0,
  'content': content,
  'verify': verify,
};

MemorialEntry _entryFromRow(Map<String, Object?> row) => MemorialEntry(
  id: row['anniversaryId']! as int,
  date: DateTime(2026, 10, 20),
  title: row['title']! as String,
  type: row['contentType'] == 1
      ? MemorialContentType.image
      : MemorialContentType.text,
  content: row['content']! as String,
);

/// 按 swagger 模拟纪念日这组接口：列表 / 详情同一个模型，新增和编辑只认一组
/// `contentType + content`，新增只回 `true`（id 由仓库层回列表按标题 + 日期找）。
class _AnniversaryServer {
  static const String uploadedUrl = 'https://example.test/upload/new.jpg';

  final Map<int, Map<String, Object?>> rows = <int, Map<String, Object?>>{};

  /// 设了就让列表接口返回它，用来模拟列表与详情不一致。
  List<Map<String, Object?>>? staleList;
  Future<void>? holdDetail;
  bool failDetail = false;
  int detailRequests = 0;
  int uploads = 0;
  int _nextId = 40;

  /// 除列表、详情、上传之外的写请求。
  final List<http.Request> writes = <http.Request>[];

  Map<String, dynamic> bodyOf(String endpoint) =>
      jsonDecode(
            writes.lastWhere((r) => r.url.path.endsWith(endpoint)).body,
          )
          as Map<String, dynamic>;

  HttpAppBackendRepository repository() {
    final session = ApiSession(storageKey: 'memorial.detail')
      ..setToken('test-token');
    return HttpAppBackendRepository(
      client: ApiClient(
        baseUrl: 'https://example.test',
        session: session,
        httpClient: MockClient(_handle),
      ),
    );
  }

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    Object? data = true;
    if (path.endsWith('getProductAnniversaryList')) {
      data = <String, Object?>{'pageData': staleList ?? rows.values.toList()};
    } else if (path.endsWith('getProductAnniversaryDetail')) {
      detailRequests++;
      await holdDetail;
      if (failDetail) {
        return http.Response('unavailable', 503);
      }
      data = rows[int.parse(request.url.queryParameters['id']!)];
    } else if (path.endsWith('setFileUpload')) {
      uploads++;
      data = uploadedUrl;
    } else {
      writes.add(request);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (path.endsWith('addUserProductAnniversary')) {
        final id = _nextId++;
        rows[id] = <String, Object?>{...body, 'anniversaryId': id, 'verify': 1};
      } else if (path.endsWith('editUserProductAnniversary')) {
        final id = body['anniversaryId'] as int;
        rows[id] = <String, Object?>{...?rows[id], ...body};
      }
    }
    return http.Response(
      jsonEncode({'retCode': 200, 'retMsg': 'ok', 'retData': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}
