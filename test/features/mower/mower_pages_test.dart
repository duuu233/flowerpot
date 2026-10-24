import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/pairing_gate.dart';
import 'package:flowerpot/src/features/devices/presentation/device_online_guard.dart';
import 'package:flowerpot/src/features/devices/presentation/device_search_page.dart';
import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/presentation/mower_home_page.dart';
import 'package:flowerpot/src/features/mower/presentation/mower_zones_page.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_plan_edit_sheet.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_plan_chart.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/time_edit_sheet.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_raw.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_status_card.dart';

import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';
import '../../support/plant_catalog.dart';

/// 割草机页面（2026-09-23 联调起只接真机）。
///
/// 原来这套用例跑在「静态演示」上（写死的割草机、本地模拟 DP5、长按电量环改只读 DP）。
/// 演示模式删掉之后，改成绑一台 Mock 的割草机：只读 DP 由设备快照给，
/// 断言看的是**真正交给 SDK 的下发**（`publishedDps`）。
///
/// ⚠️ 下发后有 5 秒的回显计时器；测试框架在用例体结束时就检查挂着的 Timer（比 tearDown 早），
/// 所以每条下发过的用例结尾都手动 `resetForTest` 一次把它们取消。
void main() {
  for (final size in [const Size(375, 812), const Size(320, 568)]) {
    testWidgets('离线首页四按钮均可点击、每次弹窗、可进入参数页 $size', (tester) async {
      final repo = await _pumpMowerHome(tester, {
        2: true,
        3: 'standby',
        5: 'mowing',
        13: 65,
        117: 'not_charging',
      });
      tester.view.physicalSize = size;
      await tester.binding.setSurfaceSize(size);
      repo.pushDeviceUpdate(
        DeviceUpdate.changed(_mower().copyWith(online: false)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-offline-read-only')), findsNothing);
      expect(find.textContaining('未在充电', findRichText: true), findsNothing);
      for (final action in ['smart', 'spot', 'gotoCharge', 'switch']) {
        final button = find.byKey(Key('mower-action-$action'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(tester.widget<InkWell>(button).onTap, isNotNull);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('设备已离线'), findsOneWidget);
        expect(find.byType(Dialog), findsOneWidget);
        expect(repo.publishedDps, isEmpty);
        await tester.tap(find.text('我知道了'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('mower-nav-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-offline-read-only')), findsNothing);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      for (final route in [
        AppRoutes.mowerZones,
        AppRoutes.mowerRain,
        AppRoutes.mowerTimeSync,
        AppRoutes.mowerLanguage,
      ]) {
        unawaited(nav.pushNamed(route));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('device-offline-read-only')), findsNothing);
        final save = find.text('保存');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('设备已离线'), findsOneWidget);
        expect(repo.publishedDps, isEmpty);
        await tester.tap(find.text('我知道了'));
        await tester.pumpAndSettle();
        nav.pop();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      MowerDevice.instance.resetForTest();
    });
  }

  testWidgets('编辑周一时收到新回读，保存只改当前时段，保留另一时段和修边的新值', (tester) async {
    final incoming = Uint8List(88);
    incoming.setRange(0, 11, [0x1c, 2, 0xd0, 2, 0x48, 3, 0x38, 4, 1, 1, 1]);
    final repo = await _pumpMowerHome(tester, {101: TuyaRaw.hex(incoming)});
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-plan-slot-1-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-plan-edit-slot-enabled')));
    final reported = Uint8List(88);
    for (var group = 1; group <= 7; group++) {
      reported.setRange(group * 11, group * 11 + 11, [
        0x1c,
        2,
        0xd0,
        2,
        0x48,
        3,
        0x38,
        4,
        1,
        1,
        1,
      ]);
    }
    reported.setRange(15, 20, [0x84, 3, 0x74, 4, 0]);
    repo.rawDpsByDevice[_mowerId]![101] = TuyaRaw.hex(reported);
    repo.pushDeviceUpdate(
      DeviceUpdate.changed(
        _mower(),
        changedDps: {101},
        reportedDps: {101: TuyaRaw.hex(reported)},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-plan-edit-save')));
    await tester.pumpAndSettle();
    final sent = TuyaRaw.bytes(repo.publishedDps.single.$2[101])!;
    expect(sent.sublist(0, 11), everyElement(0));
    expect(sent.sublist(11, 22), [0x1c, 2, 0xd0, 2, 0x84, 3, 0x74, 4, 0, 0, 1]);
    expect(sent.sublist(22), reported.sublist(22));
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(375, 812),
    const Size(390, 844),
    const Size(430, 932),
    const Size(320, 568),
  ]) {
    testWidgets('首页电量设备区域在剩余空间居中，紧凑屏可滚动 $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await _pumpMowerHome(tester, {13: 100, 117: 'charging'});
      tester.view.physicalSize = size;
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      final viewport = find.byKey(const Key('mower-status-viewport'));
      if (size.height >= 812) {
        final area = tester.getRect(viewport);
        final cardCenter = tester.getCenter(find.byType(MowerStatusCard));
        expect(cardCenter.dx, closeTo(area.center.dx, .5));
        expect(cardCenter.dy, closeTo(area.center.dy, .5));
        final plan = tester.getRect(find.byKey(const Key('mower-today-plan')));
        expect(area.bottom, lessThanOrEqualTo(plan.top));
      } else {
        expect(viewport, findsNothing);
        expect(find.byType(SingleChildScrollView), findsWidgets);
        await tester.ensureVisible(find.byKey(const Key('mower-action-panel')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('mower-action-panel')).hitTestable(),
          findsOneWidget,
        );
      }
      expect(find.text('充电中 100%', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      MowerDevice.instance.resetForTest();
    });
  }

  for (var weekday = 0; weekday < 7; weekday++) {
    testWidgets('每天上报展开后独立编辑周$weekday，不复制且不改变其它日期/时段', (tester) async {
      final raw = Uint8List(88);
      raw.setRange(0, 11, [0x1c, 2, 0xd0, 2, 0x48, 3, 0x38, 4, 1, 1, 1]);
      final repo = await _pumpMowerHome(tester, {101: TuyaRaw.hex(raw)});
      await tester.tap(find.byKey(const Key('mower-nav-plan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mower-plan-slot-1-1')), findsOneWidget);
      final slot = weekday.isEven ? 1 : 2;
      await tester.tap(find.byKey(Key('mower-plan-slot-$weekday-$slot')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(find.byKey(const Key('mower-plan-edit-copy-week')))
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('mower-plan-edit-slot-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mower-plan-edit-save')));
      await tester.pumpAndSettle();
      final sent = TuyaRaw.bytes(repo.publishedDps.single.$2[101])!;
      expect(sent.sublist(0, 11), everyElement(0));
      for (var group = 1; group <= 7; group++) {
        final target = group == (weekday == 0 ? 7 : weekday);
        expect(sent.sublist(group * 11, group * 11 + 8), [
          0x1c,
          2,
          0xd0,
          2,
          0x48,
          3,
          0x38,
          4,
        ]);
        expect(sent[group * 11 + 8], 1);
        expect(sent[group * 11 + 9], target && slot == 1 ? 0 : 1);
        expect(sent[group * 11 + 10], target && slot == 2 ? 0 : 1);
      }
      expect(find.byKey(Key('mower-plan-slot-$weekday-$slot')), findsNothing);
      expect(
        find.byKey(Key('mower-plan-slot-$weekday-${slot == 1 ? 2 : 1}')),
        findsOneWidget,
      );
      MowerDevice.instance.resetForTest();
      expect(tester.takeException(), isNull);
    });
  }

  for (final percent in [99, 100]) {
    for (final (charging, expected) in <(Object, String)>[
      (0, ''),
      (1, '充电中'),
      (2, '已充满'),
      ('0', ''),
      ('1', '充电中'),
      ('2', '已充满'),
      ('not_charging', ''),
      ('charging', '充电中'),
      ('full', '已充满'),
    ]) {
      testWidgets('电量$percent%，DP117=$charging按含义显示$expected', (tester) async {
        await _pumpMowerHome(tester, {13: percent, 117: charging});
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.text(
            expected.isEmpty ? '电量 $percent%' : '$expected $percent%',
            findRichText: true,
          ),
          findsOneWidget,
        );
        final shouldAnimate = percent < 100 && expected == '充电中';
        expect(
          find.byKey(const Key('mower-charging-bolt')),
          shouldAnimate ? findsOneWidget : findsNothing,
        );
        MowerDevice.instance.resetForTest();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('DP117未上报或非法时不编造文案，异常回报保留最后有效充电状态', (tester) async {
    final repository = await _pumpMowerHome(tester, {13: 100});
    await tester.pumpAndSettle();
    expect(find.text('电量 100%'), findsOneWidget);
    for (final raw in <Object?>['unknown', '2', 3, '3', -1, null, true, 1.5]) {
      repository.pushDeviceUpdate(
        DeviceUpdate.changed(
          _mower(),
          changedDps: {117},
          reportedDps: {117: raw},
        ),
      );
      await tester.pumpAndSettle();
      if (raw == 'unknown') {
        expect(find.text('电量 100%'), findsOneWidget);
      } else {
        expect(find.text('已充满 100%', findRichText: true), findsOneWidget);
      }
    }
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('等待雨停挂桩且DP117=charging时文案仍为充电中', (tester) async {
    await _pumpMowerHome(tester, {13: 100, 5: 'wait_rain', 117: 'charging'});
    await tester.pumpAndSettle();
    expect(find.text('充电中 100%', findRichText: true), findsOneWidget);
    expect(find.text('在桩等待雨停'), findsOneWidget);
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  for (final entry in <(Object, String)>[
    ('escaping', '陷坑脱困中'),
    ('goto_charge_low_pwr', '低电回充中'),
    (14, '雨滴回充中'),
  ]) {
    testWidgets('DP5=${entry.$1} 状态胶囊显示「${entry.$2}」', (tester) async {
      await _pumpMowerHome(tester, {13: 80, 5: entry.$1});
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
      MowerDevice.instance.resetForTest();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('计划图只显示设备DP，点击修边等实际回读，复制诊断含收发两份', (tester) async {
    final repo = _MowerRepository()..echoSchedules = false;
    final incoming = Uint8List(88);
    for (var group = 1; group <= 7; group++) {
      incoming.setRange(group * 11, group * 11 + 11, [
        0x1c,
        2,
        0xd0,
        2,
        0,
        0,
        0,
        0,
        1,
        1,
        0,
      ]);
    }
    await _pumpMowerHome(tester, {
      101: TuyaRaw.hex(incoming),
    }, repositoryOverride: repo);
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pumpAndSettle();
    final chart = find.byType(MowerPlanChart);
    expect(
      tester.widget<MowerPlanChart>(chart).enabledDays,
      everyElement(true),
    );
    expect(
      tester.widget<MowerPlanChart>(chart).trimDays,
      everyElement(true),
      reason: 'DP包含周一二四六沿边时，APP不能取消',
    );
    await tester.tap(find.byKey(const Key('mower-plan-trim-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mower-plan-pending')), findsOneWidget);
    expect(
      tester.widget<MowerPlanChart>(chart).trimDays[2],
      isTrue,
      reason: 'SDK下发完成不代表已回显，仍显示设备值',
    );
    final reply = Uint8List.fromList(incoming)..[30] = 0;
    repo.rawDpsByDevice[_mowerId]![101] = TuyaRaw.hex(reply);
    repo.pushDeviceUpdate(
      DeviceUpdate.changed(
        _mower(),
        changedDps: {101},
        reportedDps: {101: TuyaRaw.hex(reply)},
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<MowerPlanChart>(chart).trimDays[2], isFalse);
    expect(find.byKey(const Key('mower-plan-pending')), findsNothing);
    expect(find.textContaining('本机下发草稿（不是设备已确认）'), findsOneWidget);
    expect(find.textContaining('设备上报'), findsWidgets);
    MowerDevice.instance.resetForTest();
  });
  testWidgets('编辑修边后保存，不清掉设备已报且等于默认时间的停用时段', (tester) async {
    final raw = Uint8List(88);
    raw.setRange(44, 55, [0xfe, 1, 0xd0, 2, 0x48, 3, 0x38, 4, 0, 0, 0]);
    final repo = await _pumpMowerHome(tester, {101: TuyaRaw.hex(raw)});
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pumpAndSettle();
    final chart = tester.widget<MowerPlanChart>(find.byType(MowerPlanChart));
    chart.onEditDay(4, 1);
    await tester.pumpAndSettle();
    final trim = find.byKey(const Key('mower-plan-edit-trim'));
    await Scrollable.ensureVisible(tester.element(trim), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(trim);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-plan-edit-save')));
    await tester.pumpAndSettle();
    final sent = TuyaRaw.bytes(repo.publishedDps.single.$2[101])!;
    expect(sent.sublist(44, 55), [0xfe, 1, 0xd0, 2, 0x48, 3, 0x38, 4, 1, 0, 0]);
    MowerDevice.instance.resetForTest();
  });

  for (final edge in [true, false]) {
    for (final changeEdge in [false, true]) {
      testWidgets('复制整周仅复制时段，各天修边独立：源修边=$edge、现场修改=$changeEdge', (
        tester,
      ) async {
        // 独立于编码器的协议样例：组0全部，组1~7周一~周日。
        final incoming = Uint8List(88);
        for (var group = 1; group <= 7; group++) {
          incoming.setRange(group * 11, group * 11 + 11, [
            group == 4 ? 0x1c : 0x1c + group,
            0x02,
            0xd0,
            0x02,
            0x84,
            0x03,
            0xfc,
            0x03,
            (group == 4 ? edge : group.isEven) ? 1 : 0,
            1,
            0,
          ]);
        }
        final repo = await _pumpMowerHome(tester, {
          MowerDp.mowSchedule: TuyaRaw.hex(incoming),
        });
        await tester.tap(find.byKey(const Key('mower-nav-plan')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('mower-plan-slot-4-1')));
        await tester.pumpAndSettle();
        final trim = find.byKey(const Key('mower-plan-edit-trim'));
        expect(
          tester.widget<Switch>(trim).value,
          edge,
          reason: '周四修边按设备组4，不能借全部组覆盖整周',
        );
        final savedEdge = changeEdge ? !edge : edge;
        if (changeEdge) {
          await Scrollable.ensureVisible(tester.element(trim), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(trim);
          await tester.pumpAndSettle();
        }
        // 编辑期间其它天修边上报变更，复制仍以最新回读保留。
        if (changeEdge) {
          incoming[19] = 1 - incoming[19];
          repo.rawDpsByDevice[_mowerId]![101] = TuyaRaw.hex(incoming);
          repo.pushDeviceUpdate(
            DeviceUpdate.changed(
              _mower(),
              changedDps: {101},
              reportedDps: {101: TuyaRaw.hex(incoming)},
            ),
          );
          await tester.pumpAndSettle();
        }
        final copy = find.byKey(const Key('mower-plan-edit-copy-week'));
        await Scrollable.ensureVisible(tester.element(copy), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(copy);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('mower-plan-edit-save')));
        await tester.pumpAndSettle();
        expect(_sentDps(repo), [MowerDp.mowSchedule]);
        final sent = TuyaRaw.bytes(
          repo.publishedDps.single.$2[MowerDp.mowSchedule],
        )!;
        expect(sent, hasLength(88));
        for (var group = 1; group <= 7; group++) {
          expect(
            sent[group * 11 + 8],
            group == 4 ? (savedEdge ? 1 : 0) : incoming[group * 11 + 8],
            reason: '协议组$group修边仅本日维护',
          );
          expect(sent[group * 11 + 9], 1);
          expect(sent[group * 11 + 10], 0, reason: '停用时段保持停用');
          expect(sent.sublist(group * 11, group * 11 + 8), [
            0x1c,
            0x02,
            0xd0,
            0x02,
            0x84,
            0x03,
            0xfc,
            0x03,
          ]);
        }
        expect(sent.sublist(0, 11), everyElement(0), reason: '全部组保持零');
        repo.rawDpsByDevice[_mowerId]![MowerDp.mowSchedule] = TuyaRaw.hex(sent);
        repo.pushDeviceUpdate(
          DeviceUpdate.changed(_mower(), changedDps: {MowerDp.mowSchedule}),
        );
        await tester.pumpAndSettle();
        for (var day = 0; day < 7; day++) {
          final tick = find.descendant(
            of: find.byKey(Key('mower-plan-trim-$day')),
            matching: find.byIcon(Icons.check_rounded),
          );
          expect(
            tick,
            (day == 4
                    ? savedEdge
                    : incoming[(day == 0 ? 7 : day) * 11 + 8] == 1)
                ? findsOneWidget
                : findsNothing,
            reason: '回读后第$day天修边',
          );
        }
        MowerDevice.instance.resetForTest();
      });
    }
  }

  testWidgets('复制整周勾选后取消：七天时段修边保持，不下发DP101', (tester) async {
    final repo = await _pumpMowerHome(tester, {
      MowerDp.mowSchedule: TuyaRaw.hex(MowerScheduleCodec.encodeByDay(_week())),
    });
    final original = MowerDevice.instance.schedule;
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-plan-slot-2-1')));
    await tester.pumpAndSettle();
    final copy = find.byKey(const Key('mower-plan-edit-copy-week'));
    await Scrollable.ensureVisible(tester.element(copy), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-plan-edit-cancel')));
    await tester.pumpAndSettle();
    expect(repo.publishedDps, isEmpty);
    expect(identical(MowerDevice.instance.schedule, original), isTrue);
    MowerDevice.instance.resetForTest();
  });
  testWidgets('计划页标题恢复默认：离线可点击并弹提示，在线恢复', (tester) async {
    final repo = await _pumpMowerHome(tester, {});
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pumpAndSettle();
    repo.pushDeviceUpdate(
      DeviceUpdate.changed(_mower().copyWith(online: false)),
    );
    await tester.pumpAndSettle();
    final restore = find.byKey(const Key('mower-plan-restore'));
    expect(tester.widget<GestureDetector>(restore).onTap, isNotNull);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text('设备已离线'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(repo.publishedDps, isEmpty);
    repo.pushDeviceUpdate(DeviceUpdate.changed(_mower()));
    await tester.pumpAndSettle();
    expect(tester.widget<GestureDetector>(restore).onTap, isNotNull);
    MowerDevice.instance.resetForTest();
  });
  for (final status in <Object>['stop', 7, 'fault', 6, 'paused']) {
    testWidgets('$status 继续只发DP2，不选择时长、不覆盖DP119', (tester) async {
      final repository = await _pumpMowerHome(tester, {
        MowerDp.switchGo: false,
        MowerDp.status: status,
        MowerDp.mode: 'smart',
        MowerDp.operatingTime: 3,
      }, now: () => DateTime(2026, 10, 14, 17, 30));
      await tester.tap(find.byKey(const Key('mower-action-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我已确认，周围安全'));
      await tester.pumpAndSettle();
      expect(find.text('割草时间设置'), findsNothing);
      expect(find.text('暂时无法启动'), findsNothing);
      expect(repository.publishedDps.map((e) => e.$2).toList(), [
        {MowerDp.switchGo: true},
      ]);
      expect(MowerDevice.instance.operatingTimeHours, 3);
      MowerDevice.instance.resetForTest();
    });
  }
  testWidgets('真实割草停止、急停上报、继续：不重新弹割草时间', (tester) async {
    final repo = await _pumpMowerHome(tester, {
      MowerDp.status: 'mowing',
      MowerDp.switchGo: true,
      MowerDp.mode: 'smart',
    });
    await tester.tap(find.text('停止'));
    await tester.pumpAndSettle();
    repo.rawDpsByDevice[_mowerId]!
      ..[MowerDp.status] = 'stop'
      ..[MowerDp.switchGo] = false;
    repo.pushDeviceUpdate(
      DeviceUpdate.changed(
        _mower(),
        changedDps: {MowerDp.status, MowerDp.switchGo},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已确认，周围安全'));
    await tester.pumpAndSettle();
    expect(find.text('割草时间设置'), findsNothing);
    expect(repo.publishedDps.map((e) => e.$2).toList(), [
      {MowerDp.switchGo: false},
      {MowerDp.switchGo: true},
    ]);
    MowerDevice.instance.resetForTest();
  });
  testWidgets('待机继续置灰，点击不弹框也不发指令，自动仍可开始新任务', (tester) async {
    final repo = await _pumpMowerHome(tester, {
      MowerDp.status: 'standby',
      MowerDp.switchGo: false,
      MowerDp.mode: 'standby',
    });
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('mower-action-switch')))
          .onTap,
      isNull,
    );
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(repo.publishedDps, isEmpty);
    await tester.tap(find.text('自动'));
    await _confirmStart(tester);
    expect(_sentDps(repo), [MowerDp.operatingTime, MowerDp.mode]);
    MowerDevice.instance.resetForTest();
  });
  // V3.0：电量 <70% 被拒 54 进入在桩等待充电、有雨被拒 35 等待雨停，DP2 在桩等待中无效，停止/继续置灰。
  for (final entry in <(String, Map<int, Object?>)>[
    (
      'DP5=wait_charge',
      {MowerDp.status: 'wait_charge', MowerDp.switchGo: false},
    ),
    ('DP5=9且DP2=true', {MowerDp.status: 9, MowerDp.switchGo: true}),
    (
      'DP3=wait_charge',
      {
        MowerDp.status: 'mowing',
        MowerDp.switchGo: true,
        MowerDp.mode: 'wait_charge',
      },
    ),
    (
      'DP5=wait_rain',
      {MowerDp.status: 'wait_rain', MowerDp.switchGo: false},
    ),
    (
      'DP3=7',
      {MowerDp.status: 'mowing', MowerDp.switchGo: true, MowerDp.mode: 7},
    ),
  ]) {
    testWidgets('在桩等待 ${entry.$1}：停止/继续置灰，点击不发指令', (tester) async {
      final repo = await _pumpMowerHome(tester, entry.$2);
      expect(
        tester
            .widget<InkWell>(find.byKey(const Key('mower-action-switch')))
            .onTap,
        isNull,
      );
      await tester.tap(find.byKey(const Key('mower-action-switch')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(repo.publishedDps, isEmpty);
      MowerDevice.instance.resetForTest();
    });
  }
  testWidgets('离开在桩等待后停止/继续恢复原规则', (tester) async {
    await _pumpMowerHome(tester, {
      MowerDp.status: 'stop',
      MowerDp.switchGo: false,
      MowerDp.mode: 'smart',
    });
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('mower-action-switch')))
          .onTap,
      isNotNull,
    );
    MowerDevice.instance.resetForTest();
  });
  testWidgets('安全确认期间离线：继续不发送，弹窗提示但按钮仍可点', (tester) async {
    final repo = await _pumpMowerHome(tester, {
      MowerDp.status: 'stop',
      MowerDp.switchGo: false,
    });
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    repo.pushDeviceUpdate(
      DeviceUpdate.changed(_mower().copyWith(online: false)),
    );
    await tester.pump();
    await tester.tap(find.text('我已确认，周围安全'));
    await tester.pumpAndSettle();
    expect(repo.publishedDps, isEmpty);
    expect(find.text('设备已离线'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device-offline-read-only')), findsNothing);
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('mower-action-switch')))
          .onTap,
      isNotNull,
    );
    repo.pushDeviceUpdate(DeviceUpdate.changed(_mower()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device-offline-read-only')), findsNothing);
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('mower-action-switch')))
          .onTap,
      isNotNull,
    );
    MowerDevice.instance.resetForTest();
  });
  testWidgets('割草参数页离线可编辑，保存弹窗且草稿保留', (tester) async {
    final repo = await _pumpMowerHome(tester, {
      MowerDp.rainDetectEnable: false,
    });
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(nav.pushNamed(AppRoutes.mowerRain));
    await tester.pumpAndSettle();
    repo.pushDeviceUpdate(
      DeviceUpdate.changed(_mower().copyWith(online: false)),
    );
    await tester.pumpAndSettle();
    final switches = find.byType(Switch);
    final before = tester.widget<Switch>(switches.first).value;
    await tester.tap(switches.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, !before);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('设备已离线'), findsOneWidget);
    expect(find.textContaining('已下发'), findsNothing);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, !before);
    expect(repo.publishedDps, isEmpty);
    await tester.tap(find.byType(AppBackButton).first);
    await tester.pumpAndSettle();
    expect(find.byType(MowerHomePage), findsOneWidget);
    MowerDevice.instance.resetForTest();
  });

  // ⚠️ MowerDevice 是单例：上一条用例改过的开关会漏到下一条，每条前后都要复位。
  setUp(MowerDevice.instance.resetForTest);
  tearDown(MowerDevice.instance.resetForTest);

  for (final action in <String>[
    'smart',
    'spot',
    'gotoCharge',
    'start',
    'pause',
  ]) {
    testWidgets('DP115 $action 被拒：安全与时间窗之后显示设备异常，关闭不重发', (tester) async {
      final repository = _ResultMowerRepository();
      await _pumpMowerHome(tester, <int, Object?>{
        MowerDp.switchGo: action == 'pause',
        MowerDp.status: action == 'start' ? 'stop' : 'mowing',
        MowerDp.mode: 'standby',
        MowerDp.commandResults: '{"code":26,"seq":255,"dp":3,"val":1}',
      }, repositoryOverride: repository);
      expect(find.text('设备异常'), findsNothing, reason: '快照旧回执不弹');
      final starts = action == 'smart' || action == 'spot' || action == 'start';
      final key = action == 'start' || action == 'pause' ? 'switch' : action;
      await tester.tap(find.byKey(Key('mower-action-$key')));
      if (starts) {
        await tester.pumpAndSettle();
        expect(find.text('启动安全提醒'), findsOneWidget);
        expect(find.text('设备异常'), findsNothing);
        await tester.tap(find.text('我已确认，周围安全'));
        await tester.pumpAndSettle();
        if (action == 'start') {
          expect(find.text('割草时间设置'), findsNothing);
        } else {
          expect(find.text('割草时间设置'), findsOneWidget);
          expect(find.text('设备异常'), findsNothing);
          await tester.tap(find.text('确认启动'));
        }
      }
      await tester.pumpAndSettle();
      expect(find.text('设备异常'), findsOneWidget);
      expect(
        find.text('以下故障尚未排除：\n机器被抬起，请放回地面并合上盖子\n请在现场处理后等待1～2秒，再手动重试原操作。'),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('我已处理'), findsOneWidget);
      final count = repository.publishedDps.length;
      await tester.tap(find.text('我已处理'));
      await tester.pumpAndSettle();
      expect(find.text('设备异常'), findsNothing);
      expect(repository.publishedDps.length, count);
      repository.pushResult(26, repository.resultDp!, repository.resultVal!);
      await tester.pumpAndSettle();
      expect(find.text('设备异常'), findsNothing, reason: '相同seq重复回读不弹');
      MowerDevice.instance.resetForTest();
      expect(tester.takeException(), isNull);
    });
  }

  for (final code in <int>[0, 3, 15, 16, 31, 32, 35, 54, 255]) {
    testWidgets('DP115 门槛 $code：内部失败3及16以上有提示，其余小于16不弹', (tester) async {
      final repository = _ResultMowerRepository()..code = code;
      await _pumpMowerHome(tester, {}, repositoryOverride: repository);
      await tester.tap(find.byKey(const Key('mower-action-gotoCharge')));
      await tester.pumpAndSettle();
      final shown = code == 3 || code >= 16;
      expect(find.text('设备异常'), shown ? findsOneWidget : findsNothing);
      if (shown) {
        expect(
          find.text(switch (code) {
            3 => '操作未生效，请重试',
            16 => '机器已关机',
            32 => '机器已在充电桩上',
            35 => '雨天暂停中，雨停后自动继续',
            54 => '机器电量小于70%，已进入充电等待',
            _ => '操作未生效（码 $code）',
          }),
          findsOneWidget,
        );
        await tester.tap(find.text('我已处理'));
        await tester.pumpAndSettle();
      }
      MowerDevice.instance.resetForTest();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('DP115迟到回执不盖住安全与时间窗，时间窗退出后再弹', (tester) async {
    final repository = _ResultMowerRepository()..autoResult = false;
    await _pumpMowerHome(tester, {}, repositoryOverride: repository);
    await tester.tap(find.byKey(const Key('mower-action-gotoCharge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pumpAndSettle();
    repository.pushResult(24, MowerDp.mode, 3);
    await tester.pumpAndSettle();
    expect(find.text('启动安全提醒'), findsOneWidget);
    expect(find.text('设备异常'), findsNothing);
    await tester.tap(find.text('我已确认，周围安全'));
    await tester.pumpAndSettle();
    expect(find.text('割草时间设置'), findsOneWidget);
    expect(find.text('设备异常'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('设备异常'), findsOneWidget);
    expect(find.text('机器正在寻找边界线，请稍候'), findsOneWidget);
    expect(repository.publishedDps, hasLength(1));
    await tester.tap(find.text('我已处理'));
    await tester.pumpAndSettle();
    MowerDevice.instance.resetForTest();
  });

  testWidgets('DP115无关DP、旧序号、错误val和畸形帧不误弹，本次匹配回执可弹', (tester) async {
    final repository = _ResultMowerRepository()..autoResult = false;
    await _pumpMowerHome(tester, {
      MowerDp.commandResults: '{"code":26,"seq":9,"dp":3,"val":3}',
    }, repositoryOverride: repository);
    await tester.tap(find.byKey(const Key('mower-action-gotoCharge')));
    await tester.pumpAndSettle();
    repository.pushResult(26, MowerDp.mode, 3, seq: 9);
    await tester.pumpAndSettle();
    repository.pushResult(26, MowerDp.operatingTime, 5, seq: 10);
    await tester.pumpAndSettle();
    repository.pushResult(26, MowerDp.mode, 1, seq: 11);
    await tester.pumpAndSettle();
    repository.pushRaw('broken');
    await tester.pumpAndSettle();
    expect(find.text('设备异常'), findsNothing);
    repository.pushResult(26, MowerDp.mode, 3, seq: 12);
    await tester.pumpAndSettle();
    expect(find.text('设备异常'), findsOneWidget);
    await tester.tap(find.text('我已处理'));
    await tester.pumpAndSettle();
    MowerDevice.instance.resetForTest();
  });

  testWidgets('DP115回执晚于5秒回弹仍显示，收到前不会另报异常', (tester) async {
    final repository = _ResultMowerRepository()..autoResult = false;
    await _pumpMowerHome(tester, {}, repositoryOverride: repository);
    await tester.tap(find.byKey(const Key('mower-action-gotoCharge')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('设备异常'), findsNothing);
    repository.pushResult(26, MowerDp.mode, 3);
    await tester.pumpAndSettle();
    expect(find.text('设备异常'), findsOneWidget);
    await tester.tap(find.text('我已处理'));
    await tester.pumpAndSettle();
    MowerDevice.instance.resetForTest();
  });

  testWidgets('DP115长建议在320×568小屏可读，单按钮可点击且不溢出', (tester) async {
    final repository = _ResultMowerRepository()..code = 24;
    await _pumpMowerHome(tester, {}, repositoryOverride: repository);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mower-action-gotoCharge')));
    await tester.pumpAndSettle();
    expect(find.text('机器正在寻找边界线，请稍候'), findsOneWidget);
    expect(find.text('我已处理'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('我已处理'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    MowerDevice.instance.resetForTest();
  });

  testWidgets('DP115页面退出后到达：不弹、不访问已销毁页面', (tester) async {
    final repository = _ResultMowerRepository()..autoResult = false;
    await _pumpMowerHome(tester, {}, repositoryOverride: repository);
    await tester.tap(find.byKey(const Key('mower-action-gotoCharge')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    repository.pushResult(26, MowerDp.mode, 3);
    await tester.pumpAndSettle();
    expect(find.text('设备异常'), findsNothing);
    expect(tester.takeException(), isNull);
    MowerDevice.instance.resetForTest();
  });

  testWidgets('实际通道不可达：离线弹窗不叠加，关闭后仍可再次操作', (tester) async {
    final repository = await _pumpMowerHome(
      tester,
      {MowerDp.switchGo: false, MowerDp.mode: 'standby'},
      setup: (repository) {
        repository.wifiLinked = false;
        repository.bleLinked = false;
        repository.bleConnectSucceeds = false;
      },
    );
    await tester.tap(find.byKey(const Key('mower-action-gotoCharge')));
    await tester.pumpAndSettle();
    expect(find.text('设备已离线'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    final context = tester.element(find.byType(MowerHomePage));
    showMowerOfflineNotice(context);
    showMowerOfflineNotice(context);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(repository.publishedDps, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('设备已离线'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-action-gotoCharge')));
    await tester.pumpAndSettle();
    expect(find.text('设备已离线'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    MowerDevice.instance.resetForTest();
  });

  testWidgets('搜索页不再列写死的割草机（2026-09-23 联调起删掉）', (tester) async {
    await _pumpSearchPage(tester);

    expect(find.byKey(const Key('device-search-mower-demo')), findsNothing);
    expect(find.text('YSmower-01'), findsNothing);
    expect(find.textContaining('静态演示数据'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('割草机首页：标题是设备名，电量来自 DP13', (tester) async {
    await _pumpMowerHome(tester, <int, Object?>{MowerDp.battery: 78});

    expect(find.text('割草机-联调'), findsOneWidget);
    expect(find.byKey(const Key('mower-battery-ring')), findsOneWidget);
    expect(find.text('电量 78%'), findsOneWidget);
    expect(find.byKey(const Key('mower-today-plan')), findsOneWidget);
    // 没报过 DP18：黄条隐藏（协议 V2.3 位图，0 / 未上报 = 正常）
    expect(find.byKey(const Key('mower-safety-notice')), findsNothing);
    // 左三＝DP3 的三个可下发模式，最右＝DP2 开关
    for (final key in <String>[
      'mower-action-smart',
      'mower-action-spot',
      'mower-action-gotoCharge',
      'mower-action-switch',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    expect(find.text('YSmower-01'), findsNothing, reason: '不再画稿子上的假名字');
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('进来设备正常：Wi-Fi 和蓝牙两个图标都亮', (tester) async {
    await _pumpMowerHome(tester, <int, Object?>{});

    expect(find.byKey(const Key('mower-link-wifi-on')), findsOneWidget);
    expect(find.byKey(const Key('mower-link-ble-on')), findsOneWidget);
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('回归和暂停直接下发，不弹安全或时间窗，也不读取蓝牙信号', (tester) async {
    final repository = _FailingMowerRepository();
    await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.switchGo: true,
      MowerDp.mode: 'standby',
      MowerDp.coverStatus: true,
    }, repositoryOverride: repository);
    await tester.tap(find.byKey(const Key('mower-action-switch')));
    await tester.pump();
    expect(repository.publishedDps.last.$2, <int, Object>{
      MowerDp.switchGo: false,
    });
    await tester.tap(find.byKey(const Key('mower-action-gotoCharge')));
    await tester.pump();
    expect(repository.publishedDps.last.$2, <int, Object>{
      MowerDp.mode: 'goto_charge',
    });
    expect(repository.rssiReads, 0);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
    MowerDevice.instance.resetForTest();
  });

  for (final action in <String>['smart', 'spot']) {
    testWidgets('$action 每次安全确认后选整小时，DP119先成功再启动', (tester) async {
      final repository = _FailingMowerRepository();
      await _pumpMowerHome(tester, <int, Object?>{
        MowerDp.switchGo: false,
        MowerDp.mode: 'standby',
        MowerDp.coverStatus: true,
      }, repositoryOverride: repository);
      await tester.tap(find.byKey(Key('mower-action-$action')));
      await tester.pumpAndSettle();
      expect(find.text('启动安全提醒'), findsOneWidget);
      expect(repository.publishedDps, isEmpty);
      await tester.tap(find.text('我已确认，周围安全'));
      await tester.pumpAndSettle();
      expect(find.text('割草时间设置'), findsOneWidget);
      expect(find.text('5 小时'), findsOneWidget);
      expect(repository.publishedDps, isEmpty);
      await tester.tap(find.byKey(const Key('mower-start-hours')));
      await tester.pumpAndSettle();
      expect(find.text('6 小时'), findsNothing);
      await tester.tap(find.text('2 小时').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认启动'));
      await tester.pumpAndSettle();
      expect(
        repository.publishedDps.map((entry) => entry.$2).toList(),
        <Map<int, Object>>[
          <int, Object>{MowerDp.operatingTime: 2},
          action == 'switch'
              ? <int, Object>{MowerDp.switchGo: true}
              : <int, Object>{MowerDp.mode: action},
        ],
      );
      expect(repository.rssiReads, 0);
      expect(tester.takeException(), isNull);
      MowerDevice.instance.resetForTest();
    });

    testWidgets('$action 任一弹窗取消都不下发，再点仍需安全确认', (tester) async {
      final repository = await _pumpMowerHome(tester, <int, Object?>{
        MowerDp.switchGo: false,
        MowerDp.mode: 'standby',
      });
      for (final timeDialog in <bool>[false, true]) {
        await tester.tap(find.byKey(Key('mower-action-$action')));
        await tester.pumpAndSettle();
        expect(find.text('启动安全提醒'), findsOneWidget);
        if (timeDialog) {
          await tester.tap(find.text('我已确认，周围安全'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(repository.publishedDps, isEmpty);
      }
      await tester.tap(find.byKey(Key('mower-action-$action')));
      await tester.pumpAndSettle();
      expect(find.text('启动安全提醒'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(repository.publishedDps, isEmpty);
      MowerDevice.instance.resetForTest();
    });
  }

  for (final hour in <int>[17, 18, 22]) {
    testWidgets('$hour:30 剩余不足整小时或已过18点不启动，给出友好提示', (tester) async {
      final repository = await _pumpMowerHome(
        tester,
        <int, Object?>{},
        now: () => DateTime(2026, 10, 10, hour, 30),
      );
      await tester.tap(find.byKey(const Key('mower-action-smart')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我已确认，周围安全'));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法启动'), findsOneWidget);
      expect(find.text('割草时间设置'), findsNothing);
      expect(repository.publishedDps, isEmpty);
      expect(tester.takeException(), isNull);
      MowerDevice.instance.resetForTest();
    });
  }

  testWidgets('时间弹窗跨过18点：确认后不设置时间或启动', (tester) async {
    var now = DateTime(2026, 10, 10, 16, 30);
    final repository = await _pumpMowerHome(
      tester,
      <int, Object?>{},
      now: () => now,
    );
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已确认，周围安全'));
    await tester.pumpAndSettle();
    now = DateTime(2026, 10, 10, 18);
    await tester.tap(find.text('确认启动'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法启动'), findsOneWidget);
    expect(repository.publishedDps, isEmpty);
    MowerDevice.instance.resetForTest();
  });

  testWidgets('每次默认时长重新计算，不缓存安全确认或上次选择', (tester) async {
    var now = DateTime(2026, 10, 10, 12, 30);
    await _pumpMowerHome(tester, <int, Object?>{}, now: () => now);
    for (final hours in <int>[5, 4]) {
      await tester.tap(find.byKey(const Key('mower-action-smart')));
      await tester.pumpAndSettle();
      expect(find.text('启动安全提醒'), findsOneWidget);
      await tester.tap(find.text('我已确认，周围安全'));
      await tester.pumpAndSettle();
      expect(find.text('$hours 小时'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      now = DateTime(2026, 10, 10, 13, 30);
    }
    MowerDevice.instance.resetForTest();
  });

  testWidgets('DP119等待期间不启动，连点不重复下发；旧会话完成不启动重绑设备', (tester) async {
    final repository = _DelayedOperatingTimeRepository();
    await _pumpMowerHome(
      tester,
      <int, Object?>{},
      repositoryOverride: repository,
    );
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await _confirmStart(tester);
    expect(repository.publishedDps, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pump();
    expect(find.text('启动安全提醒'), findsNothing);
    final state = FlowerpotScope.of(tester.element(find.byType(MowerHomePage)));
    await MowerDevice.instance.bind(state, owner: Object(), deviceId: _mowerId);
    repository.delay.complete();
    await tester.pumpAndSettle();
    expect(_sentDps(repository), <int>[MowerDp.operatingTime]);
    expect(MowerDevice.instance.switchGo, isFalse);
    expect(tester.takeException(), isNull);
    MowerDevice.instance.resetForTest();
  });

  testWidgets('安全弹窗期间同设备重绑，确认也不继续时间设置或启动', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{});
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pumpAndSettle();
    final state = FlowerpotScope.of(tester.element(find.byType(MowerHomePage)));
    await MowerDevice.instance.bind(state, owner: Object(), deviceId: _mowerId);
    await tester.tap(find.text('我已确认，周围安全'));
    await tester.pumpAndSettle();
    expect(find.text('割草时间设置'), findsNothing);
    expect(repository.publishedDps, isEmpty);
    MowerDevice.instance.resetForTest();
  });

  testWidgets('DP119下发失败：不继续发启动DP', (tester) async {
    final repository = await _pumpMowerHome(
      tester,
      <int, Object?>{},
      setup: (repo) {
        repo.publishError = const TuyaException('reject', '设置失败');
      },
    );
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await _confirmStart(tester);
    expect(_sentDps(repository), <int>[MowerDp.operatingTime]);
    expect(find.text('指令没有发出去：设置失败'), findsOneWidget);
    expect(MowerDevice.instance.switchGo, isFalse);
    MowerDevice.instance.resetForTest();
  });

  testWidgets('DP18 按协议 V2.3 位图：0 = 正常黄条隐藏，1 = 第 0 位左轮异常', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.fault: 0,
    });
    expect(find.byKey(const Key('mower-safety-notice')), findsNothing);

    repository.rawDpsByDevice[_mowerId]![MowerDp.fault] = 1;
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(_mower(), changedDps: <int>{MowerDp.fault}),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mower-safety-notice')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('mower-safety-notice')),
        matching: find.text('左轮异常，请清理异物并重启。'),
      ),
      findsOneWidget,
    );

    // 2026-09-28：控制页捕捉到新的故障位 → 弹「设备告警」，内容是该位的文案，按钮「我知道了」
    expect(find.text('设备告警'), findsOneWidget);
    expect(find.text('左轮异常，请清理异物并重启。'), findsNWidgets(2));
    await tester.tap(find.text('我知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('设备告警'), findsNothing);

    // 设备 60 秒兜底重报同一个值：不再弹
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(_mower(), changedDps: <int>{MowerDp.fault}),
    );
    await tester.pumpAndSettle();
    expect(find.text('设备告警'), findsNothing);

    // 又多了一位（第 4 位抬起）：算新故障，再弹，两条文案都列出来
    repository.rawDpsByDevice[_mowerId]![MowerDp.fault] = 1 | (1 << 4);
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(_mower(), changedDps: <int>{MowerDp.fault}),
    );
    await tester.pumpAndSettle();
    expect(find.text('设备告警'), findsOneWidget);
    expect(find.textContaining('机器被悬空，请放回地面。'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('DP113 非在桩关机：状态写「已关机」，黄条换成关机提示，按钮全部置灰，不弹设备告警', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.fault: 0,
    });
    expect(find.text('已关机'), findsNothing);

    repository.rawDpsByDevice[_mowerId]![MowerDp.shutdownReport] = true;
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(_mower(), changedDps: <int>{MowerDp.shutdownReport}),
    );
    await tester.pumpAndSettle();

    expect(find.text('已关机'), findsOneWidget);
    expect(find.text('割草机已关机，开机后可继续操作'), findsOneWidget);
    for (final key in <String>[
      'mower-action-smart',
      'mower-action-spot',
      'mower-action-gotoCharge',
      'mower-action-switch',
    ]) {
      expect(tester.widget<InkWell>(find.byKey(Key(key))).onTap, isNull);
    }

    // 关机前后留下的故障位：不弹「设备告警」，黄条仍是关机提示
    repository.rawDpsByDevice[_mowerId]![MowerDp.fault] = 1;
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(_mower(), changedDps: <int>{MowerDp.fault}),
    );
    await tester.pumpAndSettle();
    expect(find.text('设备告警'), findsNothing);
    expect(find.text('割草机已关机，开机后可继续操作'), findsOneWidget);

    // 下次开机首报 DP113=false：复位，故障位按新上报再弹
    repository.rawDpsByDevice[_mowerId]![MowerDp.shutdownReport] = false;
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(_mower(), changedDps: <int>{MowerDp.shutdownReport}),
    );
    await tester.pumpAndSettle();
    expect(find.text('已关机'), findsNothing);
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('mower-action-switch')))
          .onTap,
      isNull,
    );
    expect(find.text('设备告警'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('设备没报过割草计划：首页「暂无割草计划」、计划页不画任何色块、编辑框不预填', (tester) async {
    await _pumpMowerHome(tester, <int, Object?>{MowerDp.battery: 50});

    expect(find.byKey(const Key('mower-today-plan')), findsOneWidget);
    expect(find.byKey(const Key('mower-today-empty')), findsOneWidget);
    expect(find.text('暂无割草计划'), findsOneWidget);
    expect(find.byKey(const Key('mower-today-range')), findsNothing);

    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pump();
    expect(find.byKey(const Key('mower-plan-empty')), findsOneWidget);
    expect(find.text('暂无割草计划（设备还没有上报）'), findsOneWidget);
    expect(find.text('总工作时间：未设置'), findsOneWidget);

    // 空的那天开编辑框：滚轮停在默认时间（2026-10-08：时段一 08:30–12:00、时段二 14:00–18:00），
    // 开关关着——不打开就不写进 DP101，也不算「停用的时段」。
    final draft = MowerPlanDraft.forDay(1, MowerDevice.instance.schedule);
    expect(draft.one.enabled, isFalse);
    expect(draft.two.enabled, isFalse);
    expect(draft.one.startMinutes, 8 * 60 + 30);
    expect(draft.one.endMinutes, 12 * 60);
    expect(draft.two.startMinutes, 14 * 60);
    expect(draft.two.endMinutes, 18 * 60);
    expect(draft.day0.slotOne, isNull, reason: '没碰过的默认时段不算排了');
    expect(draft.day0.slotTwo, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final slotNumber in <int>[1, 2]) {
    for (final dismissal in <String>['取消', '返回', '遮罩']) {
      testWidgets('长按计划时段$slotNumber后$dismissal：保留计划且不下发', (tester) async {
        final repository = await _pumpMowerHome(tester, <int, Object?>{
          MowerDp.mowSchedule: TuyaRaw.hex(
            MowerScheduleCodec.encodeByDay(_week()),
          ),
        });
        await tester.tap(find.byKey(const Key('mower-nav-plan')));
        await tester.pump();
        final before = MowerScheduleCodec.encodeByDay(
          MowerDevice.instance.schedule,
        );
        final block = find.byKey(Key('mower-plan-slot-0-$slotNumber'));

        await tester.longPress(block);
        await tester.pumpAndSettle();
        expect(find.text('计划时间是否要删除？'), findsOneWidget);
        expect(block, findsOneWidget);
        expect(
          MowerScheduleCodec.encodeByDay(MowerDevice.instance.schedule),
          before,
        );
        expect(repository.publishedDps, isEmpty);

        switch (dismissal) {
          case '取消':
            await tester.tap(find.byKey(const Key('app-dialog-cancel')));
          case '返回':
            await tester.binding.handlePopRoute();
          case '遮罩':
            await tester.tapAt(const Offset(5, 5));
        }
        await tester.pumpAndSettle();
        expect(find.text('计划时间是否要删除？'), findsNothing);
        expect(block, findsOneWidget);
        expect(
          MowerScheduleCodec.encodeByDay(MowerDevice.instance.schedule),
          before,
        );
        expect(repository.publishedDps, isEmpty);
        MowerDevice.instance.resetForTest();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('长按计划时段$slotNumber确认：只删除目标时段并整周下发一次', (tester) async {
      final repository = await _pumpMowerHome(tester, <int, Object?>{
        MowerDp.mowSchedule: TuyaRaw.hex(
          MowerScheduleCodec.encodeByDay(_week()),
        ),
      });
      await tester.tap(find.byKey(const Key('mower-nav-plan')));
      await tester.pump();
      await tester.longPress(find.byKey(Key('mower-plan-slot-0-$slotNumber')));
      await tester.pumpAndSettle();
      expect(repository.publishedDps, isEmpty);
      await tester.tap(find.byKey(const Key('app-dialog-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('mower-plan-slot-0-$slotNumber')), findsNothing);
      expect(
        find.byKey(Key('mower-plan-slot-0-${3 - slotNumber}')),
        findsOneWidget,
      );
      final expected = _week();
      final source = expected[0];
      expected[0] = MowerScheduleDay(
        slotOne: slotNumber == 1 ? null : source.slotOne,
        slotTwo: slotNumber == 2 ? null : source.slotTwo,
        edge: source.edge,
      );
      expect(_sentDps(repository), <int>[MowerDp.mowSchedule]);
      expect(repository.publishedDps, hasLength(1));
      expect(
        TuyaRaw.bytes(repository.publishedDps.single.$2[MowerDp.mowSchedule]),
        MowerScheduleCodec.encodeByDay(expected),
      );
      expect(
        MowerScheduleCodec.encodeByDay(MowerDevice.instance.schedule),
        MowerScheduleCodec.encodeByDay(expected),
      );
      MowerDevice.instance.resetForTest();
      expect(tester.takeException(), isNull);
    });
  }

  for (final targetChanged in <bool>[false, true]) {
    testWidgets('长按确认期间上报${targetChanged ? '目标' : '其他'}时段变化：不误删或覆盖新计划', (
      tester,
    ) async {
      final repository = await _pumpMowerHome(tester, <int, Object?>{
        MowerDp.mowSchedule: TuyaRaw.hex(
          MowerScheduleCodec.encodeByDay(_week()),
        ),
      });
      await tester.tap(find.byKey(const Key('mower-nav-plan')));
      await tester.pump();
      await tester.longPress(find.byKey(const Key('mower-plan-slot-0-1')));
      await tester.pumpAndSettle();
      expect(find.text('计划时间是否要删除？'), findsOneWidget);
      expect(repository.publishedDps, isEmpty);
      final updated = _week();
      final source = updated[0];
      const changed = MowerScheduleSlot(startMinutes: 960, endMinutes: 1020);
      updated[0] = MowerScheduleDay(
        slotOne: targetChanged ? changed : source.slotOne,
        slotTwo: targetChanged ? source.slotTwo : changed,
        edge: false,
      );
      repository.rawDpsByDevice[_mowerId]![MowerDp.mowSchedule] = TuyaRaw.hex(
        MowerScheduleCodec.encodeByDay(updated),
      );
      repository.pushDeviceUpdate(
        DeviceUpdate.changed(_mower(), changedDps: <int>{MowerDp.mowSchedule}),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('app-dialog-confirm')));
      await tester.pumpAndSettle();
      if (targetChanged) {
        expect(repository.publishedDps, isEmpty);
        expect(find.text('计划时间已更新，请重新长按删除'), findsOneWidget);
      } else {
        updated[0] = MowerScheduleDay(slotTwo: changed, edge: false);
        expect(repository.publishedDps, hasLength(1));
        expect(
          TuyaRaw.bytes(repository.publishedDps.single.$2[MowerDp.mowSchedule]),
          MowerScheduleCodec.encodeByDay(updated),
        );
      }
      expect(
        MowerScheduleCodec.encodeByDay(MowerDevice.instance.schedule),
        MowerScheduleCodec.encodeByDay(updated),
      );
      MowerDevice.instance.resetForTest();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('长按确认删掉时段后再新建：滚轮停在默认时间，不打开开关不下发，打开就按默认时间排上', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.mowSchedule: TuyaRaw.hex(MowerScheduleCodec.encodeByDay(_week())),
    });
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pump();

    // 周二只有时段 1（10:00–12:00），长按确认后删掉。
    await tester.longPress(find.byKey(const Key('mower-plan-slot-2-1')));
    await tester.pumpAndSettle();
    expect(find.text('计划时间是否要删除？'), findsOneWidget);
    expect(repository.publishedDps, isEmpty);
    await tester.tap(find.byKey(const Key('app-dialog-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mower-plan-slot-2-1')), findsNothing);
    expect(MowerDevice.instance.schedule[2].slotOne, isNull);

    // 点周二空白：开在时段 1，08:30–12:00，开关关着（不是 00:00）。
    await tester.tap(find.byKey(const Key('mower-plan-column-2')));
    await tester.pumpAndSettle();
    FixedExtentScrollController wheel(int index) =>
        tester
                .widget<ListWheelScrollView>(
                  find
                      .descendant(
                        of: find.byType(TimeRangeWheels),
                        matching: find.byType(ListWheelScrollView),
                      )
                      .at(index),
                )
                .controller!
            as FixedExtentScrollController;
    expect(wheel(0).selectedItem, 8);
    expect(wheel(1).selectedItem, 30);
    expect(wheel(2).selectedItem, 12);
    expect(wheel(3).selectedItem, 0);
    expect(find.text('时长 3 小时 30 分'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('mower-plan-edit-slot-enabled')))
          .value,
      isFalse,
    );

    // 时段 2 默认 14:00–18:00。
    await tester.tap(find.byKey(const Key('mower-plan-edit-tab-2')));
    await tester.pumpAndSettle();
    expect(wheel(0).selectedItem, 14);
    expect(wheel(2).selectedItem, 18);
    expect(find.text('时长 4 小时 0 分'), findsOneWidget);

    // 不开开关直接保存：两个默认时段都不写进 DP101。
    await tester.tap(find.byKey(const Key('mower-plan-edit-save')));
    await tester.pumpAndSettle();
    final bytes = TuyaRaw.bytes(
      repository.publishedDps.last.$2[MowerDp.mowSchedule],
    )!;
    const tuesday = 1 * MowerScheduleCodec.groupSize;
    expect(bytes.sublist(tuesday, tuesday + 8), everyElement(0));
    expect(bytes[tuesday + 9], 0);
    expect(bytes[tuesday + 10], 0);
    expect(MowerDevice.instance.schedule[2].slotOne, isNull);

    // 再开一次，打开时段 1 的开关保存：按默认时间排上。
    await tester.tap(find.byKey(const Key('mower-plan-column-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-plan-edit-slot-enabled')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mower-plan-edit-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mower-plan-slot-2-1')), findsOneWidget);
    final slot = MowerDevice.instance.schedule[2].slotOne;
    expect(slot?.enabled, isTrue);
    expect(slot?.startMinutes, 8 * 60 + 30);
    expect(slot?.endMinutes, 12 * 60);
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('刚开机待机（DP2=false、DP3=standby）：「自动」能点，发 DP3=smart', (
    tester,
  ) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.switchGo: false,
      MowerDp.mode: 'standby',
      MowerDp.status: 'standby',
    });

    expect(find.text('继续'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await _confirmStart(tester);

    expect(_sentDps(repository), <int>[MowerDp.operatingTime, MowerDp.mode]);
    expect(repository.publishedDps.last.$2[MowerDp.mode], 'smart');
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('按过停止（DP5=paused）时左三点不动；继续、设备回作业后恢复', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.switchGo: false,
      MowerDp.mode: 'smart',
      MowerDp.status: 'paused',
    });

    await tester.tap(find.byKey(const Key('mower-action-spot')));
    await tester.pump();
    expect(_sentDps(repository), isEmpty, reason: '暂停中左三不下发');

    await tester.tap(find.byKey(const Key('mower-action-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已确认，周围安全'));
    await tester.pumpAndSettle();
    expect(_sentDps(repository), <int>[MowerDp.switchGo]);

    // 设备收下「继续」，回到割草中
    repository.rawDpsByDevice[_mowerId]!
      ..[MowerDp.switchGo] = true
      ..[MowerDp.status] = 'mowing';
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(
        _mower(),
        changedDps: <int>{MowerDp.switchGo, MowerDp.status},
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('mower-action-spot')));
    await _confirmStart(tester);
    expect(_sentDps(repository), <int>[
      MowerDp.switchGo,
      MowerDp.operatingTime,
      MowerDp.mode,
    ]);
    expect(repository.publishedDps.last.$2[MowerDp.mode], 'spot');
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一个模式不重复下发：点过「自动」之后它置灰', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.switchGo: true,
      MowerDp.mode: 'standby',
    });
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await _confirmStart(tester);
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pump();

    expect(MowerDevice.instance.isCurrentMode(MowerMode.smart), isTrue);
    expect(
      _sentDps(repository).where((dp) => dp == MowerDp.mode),
      hasLength(1),
    );
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('设备报盖子没合（DP118=false）时点「自动」弹窗且不下发', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.switchGo: true,
      MowerDp.mode: 'standby',
      MowerDp.coverStatus: false,
    });

    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await _confirmStart(tester);

    expect(find.text('盖子未合上'), findsOneWidget);
    expect(_sentDps(repository), isNot(contains(MowerDp.mode)));
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('割草计划页按设备报的计划合计工作时间；星期下面那排勾是修边，点了只翻沿边位、整周下发', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.mowSchedule: TuyaRaw.hex(MowerScheduleCodec.encodeByDay(_week())),
    });
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pump();

    expect(find.text('总工作时间：5小时23分钟'), findsOneWidget);
    // 2026-10-08：那排勾左边标「修边」，勾 = 修边；图例只剩两个时段，修边不再画成色块描边。
    expect(find.byKey(const Key('mower-plan-trim-label')), findsOneWidget);
    expect(find.text('修边'), findsOneWidget);
    expect(find.text('时段一'), findsOneWidget);
    expect(find.text('时段二'), findsOneWidget);
    Finder tick(int day) => find.descendant(
      of: find.byKey(Key('mower-plan-trim-$day')),
      matching: find.byIcon(Icons.check_rounded),
    );
    expect(tick(0), findsOneWidget, reason: '周日设备报的是修边');
    expect(tick(2), findsNothing);
    expect(tick(4), findsOneWidget);

    // 周日取消勾：只关修边，两个时段照旧在图上、合计不变。
    await tester.tap(find.byKey(const Key('mower-plan-trim-0')));
    await tester.pump();
    expect(tick(0), findsNothing);
    expect(find.text('总工作时间：5小时23分钟'), findsOneWidget);
    expect(find.byKey(const Key('mower-plan-slot-0-1')), findsOneWidget);
    expect(_sentDps(repository), <int>[MowerDp.mowSchedule]);
    final sent = TuyaRaw.bytes(
      repository.publishedDps.last.$2[MowerDp.mowSchedule],
    )!;
    const sunday = 7 * MowerScheduleCodec.groupSize;
    expect(sent[sunday + 8], 0, reason: '周日沿边位清掉');
    expect(sent[sunday + 9], 1, reason: '时段有效位不动');
    expect(sent[4 * MowerScheduleCodec.groupSize + 8], 1, reason: '周四修边照旧');
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑弹窗里停用的时段不画在图上；设备回显后时间还在，再启用原样回来', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.mowSchedule: TuyaRaw.hex(MowerScheduleCodec.encodeByDay(_week())),
    });
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pump();
    expect(find.byKey(const Key('mower-plan-slot-2-1')), findsOneWidget);

    // 周二时段 1（10:00–12:00）：点色块进编辑，关掉「启用时段1」，保存。
    await tester.tap(find.byKey(const Key('mower-plan-slot-2-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mower-plan-edit-slot-enabled')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mower-plan-edit-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mower-plan-slot-2-1')), findsNothing);
    expect(find.text('总工作时间：3小时23分钟'), findsOneWidget);
    // 下发里这一段有效位 0（设备不执行），起止照写。
    final sent = repository.publishedDps.last.$2[MowerDp.mowSchedule]!;
    final bytes = TuyaRaw.bytes(sent)!;
    const tuesday = 2 * MowerScheduleCodec.groupSize;
    expect(bytes[tuesday + 9], 0);
    expect(bytes[tuesday] | (bytes[tuesday + 1] << 8), 600);
    expect(bytes[tuesday + 2] | (bytes[tuesday + 3] << 8), 720);

    // 设备 RAW 回显：界面按回显重解，这一段还是「停用」，照样不画。
    repository.rawDpsByDevice[_mowerId]![MowerDp.mowSchedule] = sent;
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(_mower(), changedDps: <int>{MowerDp.mowSchedule}),
    );
    await tester.pump();
    await tester.pump();
    final parked = MowerDevice.instance.schedule[2].slotOne;
    expect(parked?.enabled, isFalse);
    expect(parked?.startMinutes, 600);
    expect(parked?.endMinutes, 720);
    expect(find.byKey(const Key('mower-plan-slot-2-1')), findsNothing);

    // 点周二空白：直接开在停用的时段 1 上，时间还是 10:00–12:00；打开开关保存就回到图上。
    await tester.tap(find.byKey(const Key('mower-plan-column-2')));
    await tester.pumpAndSettle();
    expect(find.text('时段1（已关闭）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-plan-edit-slot-enabled')));
    await tester.pump();
    expect(find.text('时长 2 小时 0 分'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-plan-edit-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mower-plan-slot-2-1')), findsOneWidget);
    expect(find.text('总工作时间：5小时23分钟'), findsOneWidget);
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('「恢复默认」确认后发 DP110=true，本地不改；设备回报 DP101 后界面按它刷新', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.mowSchedule: TuyaRaw.hex(MowerScheduleCodec.encodeByDay(_week())),
    });
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('mower-plan-restore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mower-plan-restore-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-plan-restore-confirm')));
    await tester.pumpAndSettle();

    expect(_sentDps(repository), <int>[MowerDp.scheduleReset]);
    expect(repository.publishedDps.single.$2[MowerDp.scheduleReset], isTrue);
    expect(find.text('总工作时间：5小时23分钟'), findsOneWidget, reason: '等设备回报，不先本地改');

    // 协议 V2.3 §5.4：设备写入默认计划（组 0）→ 上报 DP101 → 回写 DP110=false
    final defaults = Uint8List(MowerScheduleCodec.bytes)
      ..setRange(0, 11, <int>[
        0x1C,
        0x02,
        0xB2,
        0x02,
        0x2A,
        0x03,
        0x1A,
        0x04,
        0,
        1,
        1,
      ]);
    repository.rawDpsByDevice[_mowerId]!
      ..[MowerDp.mowSchedule] = TuyaRaw.hex(defaults)
      ..[MowerDp.scheduleReset] = false;
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(
        _mower(),
        changedDps: <int>{MowerDp.mowSchedule, MowerDp.scheduleReset},
      ),
    );
    await tester.pump();
    await tester.pump();

    final monday = MowerDevice.instance.schedule[1];
    expect(monday.slotOne?.startMinutes, 540);
    expect(monday.slotOne?.endMinutes, 690);
    expect(monday.slotTwo?.startMinutes, 810);
    expect(monday.slotTwo?.endMinutes, 1050);
    expect(MowerDevice.instance.scheduleRawSource, '设备上报');
    expect(find.byKey(const Key('mower-plan-debug-window')), findsOneWidget);
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('消息通知：三栏可点击且日期可选，移除所有调试区域', (tester) async {
    await _pumpMowerHome(tester, <int, Object?>{});
    await tester.tap(find.byKey(const Key('mower-nav-settings')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('mower-settings-消息通知')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mower-settings-消息通知')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(Key('mower-messages-tab-$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('mower-messages-date')), findsOneWidget);
    expect(find.text('全部日期'), findsOneWidget);
    expect(find.byKey(const Key('mower-nav-home')), findsNothing);
    expect(find.byKey(const Key('mower-nav-plan')), findsNothing);
    expect(find.byKey(const Key('mower-nav-settings')), findsNothing);
    expect(find.text('暂无日志'), findsOneWidget);
    expect(find.textContaining('根据本机接收的 DP 上报生成'), findsNothing);
    expect(find.byKey(const Key('message-monitor-console')), findsNothing);
    expect(find.text('云端推送调试'), findsNothing);
    expect(find.textContaining('当前等级'), findsNothing);
    expect(find.byKey(const Key('mower-messages-debug-panel')), findsNothing);
    for (var category = 0; category < 3; category++) {
      await tester.tap(find.byKey(Key('mower-messages-tab-$category')));
      await tester.pumpAndSettle();
      expect(find.text(['暂无日志', '暂无提醒', '暂无告警'][category]), findsOneWidget);
    }
    await tester.tap(find.byType(AppBackButton).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mower-nav-settings')), findsOneWidget);
    expect(find.byKey(const Key('mower-settings-消息通知')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('区域设置：占比滑条 5% 一档；设备报的旧值不是 5 的倍数时照原值显示', (tester) async {
    await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.zoneConfig: TuyaRaw.hex(
        MowerZoneCodec.encode(const <MowerZoneConfig>[
          MowerZoneConfig(index: 1, percent: 33, meters: 20),
        ]),
      ),
    });
    await tester.tap(find.byKey(const Key('mower-nav-settings')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mower-settings-区域设置')));
    await tester.pumpAndSettle();

    expect(find.text('33%'), findsOneWidget);
    Slider slider() =>
        tester.widget<Slider>(find.byKey(const Key('mower-zone-slider-1')));
    expect(MowerZonesPage.percentStep, 5);
    expect(slider().divisions, 20);

    // 滑条交上来的值不管是多少，落到页面上的都是 5 的倍数。
    slider().onChanged!(42);
    await tester.pump();
    expect(find.text('40%'), findsOneWidget);
    slider().onChanged!(43);
    await tester.pump();
    expect(find.text('45%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页：重新配网隐藏；「设备参数」进花盆同一页「更多设备信息」', (tester) async {
    await _pumpMowerHome(
      tester,
      <int, Object?>{},
      setup: (repository) => repository.productName = 'YS 智能割草机',
    );
    await tester.tap(find.byKey(const Key('mower-nav-settings')));
    await tester.pump();

    expect(find.byKey(const Key('mower-settings-区域设置')), findsOneWidget);
    expect(find.byKey(const Key('mower-settings-delete')), findsOneWidget);
    expect(find.byKey(const Key('mower-settings-重新配网')), findsNothing);
    expect(find.byKey(const Key('mower-settings-设备升级')), findsOneWidget);

    await tester.tap(find.byKey(const Key('mower-settings-设备参数')));
    await tester.pumpAndSettle();

    expect(find.text('更多设备信息'), findsOneWidget);
    expect(find.text('割草机-联调'), findsWidgets);
    // 软件：固件版本；硬件：设备型号（涂鸦产品名）、设备devId、mac地址、硬件版本
    expect(find.text('固件版本'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    expect(find.text('设备型号'), findsOneWidget);
    expect(find.text('YS 智能割草机'), findsOneWidget);
    expect(find.text('设备devId'), findsOneWidget);
    expect(find.text(_mowerId), findsOneWidget);
    expect(find.text('mac地址'), findsOneWidget);
    expect(find.text('AABBCC000031'), findsOneWidget);
    expect(find.text('硬件版本'), findsOneWidget);
    // 去掉的：SN、APP版本、两个 UUID；花盆专属的陪伴天数和 DP162 联调按钮也不出现
    for (final gone in <String>['SN', 'APP版本', '设备UUID', '花托UUID']) {
      expect(find.text(gone), findsNothing);
    }
    expect(find.textContaining('已陪伴'), findsNothing);
    expect(find.byKey(const Key('device-info-dp162-probe')), findsNothing);
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });
}

const String _mowerId = 'mower-1';

/// 稿子上那一周（原来是端上写死的演示计划，现在当作「设备报上来的」喂进去）：
/// 周日 08:00–09:00 + 14:00–15:00（修边），周二 10:00–12:00，周四 15:00–16:23（修边）。
List<MowerScheduleDay> _week() {
  final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
  week[0] = const MowerScheduleDay(
    slotOne: MowerScheduleSlot(startMinutes: 480, endMinutes: 540),
    slotTwo: MowerScheduleSlot(startMinutes: 840, endMinutes: 900),
    edge: true,
  );
  week[2] = const MowerScheduleDay(
    slotOne: MowerScheduleSlot(startMinutes: 600, endMinutes: 720),
  );
  week[4] = const MowerScheduleDay(
    slotOne: MowerScheduleSlot(startMinutes: 900, endMinutes: 983),
    edge: true,
  );
  return week;
}

/// 交给 SDK 的下发，按顺序列出 DP 号。
List<int> _sentDps(MockTuyaRepository repository) => <int>[
  for (final entry in repository.publishedDps) ...entry.$2.keys,
];

SmartPlanterDevice _mower() => SmartPlanterDevice(
  id: _mowerId,
  productId: MowerDp.productId,
  name: '割草机-联调',
  online: true,
  signal: 80,
  battery: 0,
  charging: false,
  boundAt: DateTime(2026, 9, 23),
  plant: PlantCatalog.items.first,
  sensors: const SensorSnapshot(
    waterLevel: 0,
    soilMoisture: 0,
    illuminance: 0,
    ppfd: 0,
    airTemperature: 0,
    relativeHumidity: 0,
  ),
  settings: const DeviceControlSettings(),
  firmwareVersion: '1.0.0',
  macAddress: 'AA:BB:CC:00:00:31',
);

/// 设备列表里只有一台割草机；其余照 Mock。
class _MowerRepository extends MockTuyaRepository {
  bool echoSchedules = true;

  @override
  Future<Map<String, Object?>> deviceMessages({
    required String deviceId,
    String msgType = 'MSG_REPORT',
    int offset = 0,
    int limit = 50,
  }) async => {'ok': true, 'items': <Object?>[], 'totalCount': 0};

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    await super.publishDps(deviceId, dps);
    if (echoSchedules && dps.containsKey(MowerDp.mowSchedule)) {
      rawDpsByDevice.putIfAbsent(deviceId, () => {})[MowerDp.mowSchedule] =
          dps[MowerDp.mowSchedule];
      pushDeviceUpdate(
        DeviceUpdate.changed(
          _mower(),
          changedDps: {MowerDp.mowSchedule},
          reportedDps: {MowerDp.mowSchedule: dps[MowerDp.mowSchedule]},
        ),
      );
    }
  }

  _MowerRepository() : super(latency: Duration.zero, seedDevice: false);

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    _mower(),
  ];
}

Future<MockTuyaRepository> _pumpMowerHome(
  WidgetTester tester,
  Map<int, Object?> snapshot, {
  void Function(MockTuyaRepository repository)? setup,
  MockTuyaRepository? repositoryOverride,
  DateTime Function()? now,
}) async {
  // 发送队列必须在 testWidgets 的假时钟区域内创建，setUp 的外层 Future 不会被 pump 推进。
  MowerDevice.instance.resetForTest();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 812);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = repositoryOverride ?? _MowerRepository();
  repository.rawDpsByDevice[_mowerId] = snapshot;
  setup?.call(repository);
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.initialize();
  await state.refreshDevices();
  // 这些页面用例通过主动推送更新设备，不需要在线轮询，避免测试体结束时遗留 Timer。
  state.pauseDeviceWatch();
  // ⚠️ 必须套 FlowerpotScope：割草机各页进页面都会往联调日志里记一条。
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: buildAppTheme(),
        home: MowerHomePage(
          deviceId: _mowerId,
          now: now ?? () => DateTime(2026, 10, 10, 12, 30),
        ),
        onGenerateRoute: (settings) =>
            AppRoutes.onGenerateRoute(settings, authenticated: true),
      ),
    ),
  );
  // 首帧之后 bind → 读设备快照 → 页面按快照重画
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return repository;
}

Future<void> _pumpSearchPage(WidgetTester tester) async {
  PairingGate.apEnabled = true;
  addTearDown(PairingGate.reset);
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: buildAppTheme(),
        navigatorObservers: <NavigatorObserver>[AppRoutes.routeObserver],
        home: const DeviceSearchPage(),
      ),
    ),
  );
  await tester.pump();
}

class _FailingMowerRepository extends _MowerRepository {
  int rssiReads = 0;
  @override
  Future<Map<String, Object?>> readDeviceBleRssi(String deviceId) async {
    rssiReads++;
    throw StateError('SDK RSSI failed');
  }
}

Future<void> _confirmStart(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('我已确认，周围安全'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认启动'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

class _DelayedOperatingTimeRepository extends _MowerRepository {
  final delay = Completer<void>();

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    if (dps.containsKey(MowerDp.operatingTime)) await delay.future;
    await super.publishDps(deviceId, dps);
  }
}

class _ResultMowerRepository extends _MowerRepository {
  int code = 26;
  bool autoResult = true;
  Object? freshAlarm = '{"device":0,"error":2,"function":0,"circularize":0}';
  int? resultDp;
  int? resultVal;

  void pushRaw(Object raw) {
    final payload = <int, Object?>{
      MowerDp.commandResults: raw,
      if (freshAlarm != null) MowerDp.faultAlarm: freshAlarm,
    };
    rawDpsByDevice[_mowerId]!.addAll(payload);
    pushDeviceUpdate(
      DeviceUpdate.changed(
        _mower(),
        changedDps: payload.keys.toSet(),
        reportedDps: payload,
      ),
    );
  }

  void pushResult(int code, int dp, int val, {int seq = 0}) =>
      pushRaw(jsonEncode({'code': code, 'seq': seq, 'dp': dp, 'val': val}));

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) async {
    await super.publishDps(deviceId, dps);
    final dp = dps.keys.single;
    if (dp != MowerDp.switchGo && dp != MowerDp.mode) return;
    resultDp = dp;
    resultVal = dp == MowerDp.switchGo
        ? (dps[dp] == true ? 1 : 0)
        : MowerMode.values.firstWhere((mode) => mode.code == dps[dp]).value;
    if (autoResult) pushResult(code, dp, resultVal!);
  }
}
