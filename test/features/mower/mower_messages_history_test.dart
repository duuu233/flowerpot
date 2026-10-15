import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/mower/presentation/mower_messages_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/mock_tuya_repository.dart';

const _deviceId = 'selected-mower';

void main() {
  testWidgets('云端历史按设备查询并分三栏，清除本机数据后同账号仍重新取回', (tester) async {
    for (var install = 0; install < 2; install++) {
      SharedPreferences.setMockInitialValues({});
      final repository = _CloudMessagesRepository([
        _message('历史割草日志', DateTime(2026, 10, 15, 9), '通知'),
        _message('历史割草提醒', DateTime(2026, 10, 15, 10), '轻微'),
        _message('历史割草告警', DateTime(2026, 10, 15, 11), '严重'),
        {'msgTitle': '未识别等级的历史告警', 'time': 1792036800},
      ]);
      final state = await _state(repository);
      addTearDown(state.dispose);
      expect((await state.mowerMachineLog(_deviceId)).entries, isEmpty);
      await _pumpPage(tester, state);
      expect(repository.requests, [(_deviceId, 'MSG_REPORT', 0, 50)]);
      for (var category = 0; category < 3; category++) {
        await tester.tap(find.byKey(Key('mower-messages-tab-$category')));
        await tester.pumpAndSettle();
        final titles = ['历史割草日志', '历史割草提醒', '历史割草告警'];
        expect(find.text(titles[category]), findsOneWidget);
        for (var other = 0; other < 3; other++) {
          if (other != category) expect(find.text(titles[other]), findsNothing);
        }
      }
      expect(find.text('未识别等级的历史告警'), findsOneWidget);
      expect(find.text('全部日期'), findsOneWidget);
      expect(find.textContaining('当前等级'), findsNothing);
      expect(find.text('云端推送调试'), findsNothing);
      expect(find.byKey(const Key('message-monitor-console')), findsNothing);
      expect(find.byKey(const Key('mower-messages-debug-panel')), findsNothing);
      expect(find.byKey(const Key('mower-nav-home')), findsNothing);
      expect(find.byKey(const Key('mower-nav-plan')), findsNothing);
      expect(find.byKey(const Key('mower-nav-settings')), findsNothing);
      expect(repository.windowRequests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('日期弹框中文且每栏独立筛选，收到推送后按原逻辑刷新云端记录', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final repository = _CloudMessagesRepository([
      _message('今天的日志', today, '通知'),
      _message('昨天的日志', yesterday, '通知'),
      _message('今天的告警', today, '严重'),
      _message('昨天的告警', yesterday, '严重'),
    ]);
    final state = await _state(repository);
    addTearDown(state.dispose);
    await _pumpPage(tester, state);
    expect(find.text('今天的日志'), findsOneWidget);
    expect(find.text('昨天的日志'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-messages-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('选择日期'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(
      Localizations.localeOf(
        tester.element(find.byType(DatePickerDialog)),
      ).languageCode,
      'zh',
    );
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('今天的日志'), findsOneWidget);
    expect(find.text('昨天的日志'), findsNothing);
    await tester.tap(find.byKey(const Key('mower-messages-tab-2')));
    await tester.pumpAndSettle();
    expect(find.text('今天的告警'), findsOneWidget);
    expect(find.text('昨天的告警'), findsOneWidget);
    expect(find.text('全部日期'), findsOneWidget);
    repository.items.add(_message('推送后云端新告警', today, '严重'));
    repository.emitPushMessage({'source': '802'});
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.requests, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(2));
    expect(find.text('推送后云端新告警'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-messages-tab-0')));
    await tester.pumpAndSettle();
    expect(find.text('今天的日志'), findsOneWidget);
    expect(find.text('昨天的日志'), findsNothing);
    await tester.tap(find.byKey(const Key('mower-messages-date-all')));
    await tester.pumpAndSettle();
    expect(find.text('昨天的日志'), findsOneWidget);
    expect(repository.windowRequests, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Map<String, Object?> _message(String title, DateTime at, String level) => {
  'msgTitle': title,
  'msgContent': '$title说明',
  'time': at.millisecondsSinceEpoch ~/ 1000,
  'extendParams': {'level': level},
};

Future<FlowerpotState> _state(_CloudMessagesRepository repository) async {
  final state = FlowerpotState(repository: repository);
  await state.initialize();
  state.pauseDeviceWatch();
  return state;
}

Future<void> _pumpPage(WidgetTester tester, FlowerpotState state) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 812);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: buildAppTheme(),
        home: const MowerMessagesPage(deviceId: _deviceId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _CloudMessagesRepository extends MockTuyaRepository {
  _CloudMessagesRepository(this.items)
    : super(latency: Duration.zero, seedDevice: false);
  final List<Map<String, Object?>> items;
  final requests = <(String, String, int, int)>[];
  int windowRequests = 0;

  @override
  Future<AppUser?> restoreSession() async =>
      const AppUser(id: 'same-owner', nickname: '测试账号', account: 'same-owner');

  @override
  Future<Map<String, Object?>> deviceMessages({
    required String deviceId,
    String msgType = 'MSG_REPORT',
    int offset = 0,
    int limit = 50,
  }) async {
    requests.add((deviceId, msgType, offset, limit));
    final page = items.skip(offset).take(limit).toList();
    return {'ok': true, 'items': page, 'totalCount': items.length};
  }

  @override
  Future<Map<String, Object?>> messagesByTime({
    required int startTime,
    required int endTime,
    String deviceId = '',
    int offset = 0,
    int limit = 50,
  }) async {
    windowRequests++;
    return {'ok': true, 'items': <Object?>[]};
  }
}
