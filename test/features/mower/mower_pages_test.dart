import 'dart:typed_data';

import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/pairing_gate.dart';
import 'package:flowerpot/src/features/devices/presentation/device_search_page.dart';
import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/presentation/mower_home_page.dart';
import 'package:flowerpot/src/features/mower/presentation/mower_zones_page.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_plan_edit_sheet.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/time_edit_sheet.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_raw.dart';
import 'package:flutter/material.dart';
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
  // ⚠️ MowerDevice 是单例：上一条用例改过的开关会漏到下一条，每条前后都要复位。
  setUp(MowerDevice.instance.resetForTest);
  tearDown(MowerDevice.instance.resetForTest);

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

  testWidgets('蓝牙检查关着（默认）：蓝牙连不上也照常下发，不弹提示', (tester) async {
    final repository = await _pumpMowerHome(
      tester,
      <int, Object?>{MowerDp.switchGo: true, MowerDp.mode: 'standby'},
      setup: (repository) => repository
        ..bleLinked = false
        ..bleConnectSucceeds = false,
    );

    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pump();

    expect(find.text('无法连接设备蓝牙，请检查设备或靠近设备10米内'), findsNothing);
    expect(_sentDps(repository), <int>[MowerDp.mode]);
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('蓝牙没连、进来自动连也连不上：图标灭；点按钮再连不上就弹提示、不下发', (tester) async {
    // 蓝牙检查默认关着（MowerBleGate，2026-09-23），这两条专门验它，自己打开。
    MowerBleGate.enabled = true;
    addTearDown(MowerBleGate.reset);
    final repository = await _pumpMowerHome(
      tester,
      <int, Object?>{MowerDp.switchGo: true, MowerDp.mode: 'standby'},
      setup: (repository) => repository
        ..bleLinked = false
        ..bleConnectSucceeds = false,
    );
    expect(find.byKey(const Key('mower-link-ble-off')), findsOneWidget);
    expect(repository.bleConnectCalls, 1, reason: '进页面后台自动连了一次');

    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pumpAndSettle();

    expect(find.text('无法连接设备蓝牙，请检查设备或靠近设备10米内'), findsOneWidget);
    expect(repository.bleConnectCalls, 2, reason: '点按钮时再连一次');
    expect(_sentDps(repository), isEmpty);
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('蓝牙信号弱于 -90：提示必须在 10 米内、不下发；-85 就放行', (tester) async {
    // 蓝牙检查默认关着（MowerBleGate，2026-09-23），这两条专门验它，自己打开。
    MowerBleGate.enabled = true;
    addTearDown(MowerBleGate.reset);
    final repository = await _pumpMowerHome(
      tester,
      <int, Object?>{MowerDp.switchGo: true, MowerDp.mode: 'standby'},
      setup: (repository) => repository.bleRssi = -95,
    );

    await tester.tap(find.byKey(const Key('mower-action-switch')));
    await tester.pumpAndSettle();
    expect(find.text('因安全要求必须在10米内控制设备'), findsOneWidget);
    expect(_sentDps(repository), isEmpty);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();

    repository.bleRssi = -85;
    await tester.tap(find.byKey(const Key('mower-action-switch')));
    await tester.pump();
    expect(_sentDps(repository), <int>[MowerDp.switchGo]);
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
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
    await tester.pump();
    await tester.pump();

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
    await tester.pump();
    await tester.pump();
    expect(find.text('设备告警'), findsNothing);

    // 又多了一位（第 4 位抬起）：算新故障，再弹，两条文案都列出来
    repository.rawDpsByDevice[_mowerId]![MowerDp.fault] = 1 | (1 << 4);
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(_mower(), changedDps: <int>{MowerDp.fault}),
    );
    await tester.pump();
    await tester.pump();
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
      DeviceUpdate.changed(
        _mower(),
        changedDps: <int>{MowerDp.shutdownReport},
      ),
    );
    await tester.pump();
    await tester.pump();

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
    await tester.pump();
    await tester.pump();
    expect(find.text('设备告警'), findsNothing);
    expect(find.text('割草机已关机，开机后可继续操作'), findsOneWidget);

    // 下次开机首报 DP113=false：复位，故障位按新上报再弹
    repository.rawDpsByDevice[_mowerId]![MowerDp.shutdownReport] = false;
    repository.pushDeviceUpdate(
      DeviceUpdate.changed(
        _mower(),
        changedDps: <int>{MowerDp.shutdownReport},
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('已关机'), findsNothing);
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('mower-action-switch')))
          .onTap,
      isNotNull,
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

  testWidgets('长按确认删掉时段后再新建：滚轮停在默认时间，不打开开关不下发，打开就按默认时间排上', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.mowSchedule: TuyaRaw.hex(
        MowerScheduleCodec.encodeByDay(_week()),
      ),
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
      tester.widget<Switch>(find.byKey(const Key('mower-plan-edit-slot-enabled'))).value,
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
    const tuesday = 2 * MowerScheduleCodec.groupSize;
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

  testWidgets('刚开机待机（DP2=false、DP3=standby）：「自动」能点，发 DP3=smart', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.switchGo: false,
      MowerDp.mode: 'standby',
      MowerDp.status: 'standby',
    });

    expect(find.text('继续'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mower-action-smart')));
    await tester.pump();

    expect(_sentDps(repository), <int>[MowerDp.mode]);
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
    await tester.pump();
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
    await tester.pump();
    expect(_sentDps(repository), <int>[MowerDp.switchGo, MowerDp.mode]);
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
    await tester.pump();
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
    await tester.pumpAndSettle();

    expect(find.text('盖子未合上'), findsOneWidget);
    expect(_sentDps(repository), isNot(contains(MowerDp.mode)));
    MowerDevice.instance.resetForTest();
    expect(tester.takeException(), isNull);
  });

  testWidgets('割草计划页按设备报的计划合计工作时间；星期下面那排勾是修边，点了只翻沿边位、整周下发', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.mowSchedule: TuyaRaw.hex(
        MowerScheduleCodec.encodeByDay(_week()),
      ),
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
      MowerDp.mowSchedule: TuyaRaw.hex(
        MowerScheduleCodec.encodeByDay(_week()),
      ),
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
      DeviceUpdate.changed(
        _mower(),
        changedDps: <int>{MowerDp.mowSchedule},
      ),
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
      MowerDp.mowSchedule: TuyaRaw.hex(
        MowerScheduleCodec.encodeByDay(_week()),
      ),
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
      ..setRange(0, 11, <int>[0x1C, 0x02, 0xB2, 0x02, 0x2A, 0x03, 0x1A, 0x04, 0, 1, 1]);
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

  testWidgets('消息通知：列表是和花盆共用的那套（三栏 + 日期筛选），底下照旧有调试板', (tester) async {
    await _pumpMowerHome(tester, <int, Object?>{});
    await tester.tap(find.byKey(const Key('mower-nav-settings')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('mower-settings-消息通知')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mower-settings-消息通知')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      expect(find.byKey(Key('mower-messages-tab-$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('mower-messages-date')), findsOneWidget);
    expect(find.text('全部日期'), findsOneWidget);
    // Mock 没有消息中心：如实写取不到
    expect(find.textContaining('没有取到：'), findsOneWidget);
    expect(find.byKey(const Key('mower-messages-debug-panel')), findsOneWidget);
    // 2026-09-28：花盆那套写死参数的调试台照搬过来，参数换成这台割草机 + 最近 7 天
    expect(find.byKey(const Key('message-monitor-console')), findsOneWidget);
    final params = tester
        .widget<SelectableText>(find.byKey(const Key('message-monitor-params')))
        .data;
    expect(params, contains('按设备取：$_mowerId'));
    expect(params, contains('最近 7 天'));
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
}) async {
  // 发送队列必须在 testWidgets 的假时钟区域内创建，setUp 的外层 Future 不会被 pump 推进。
  MowerDevice.instance.resetForTest();
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _MowerRepository()..rawDpsByDevice[_mowerId] = snapshot;
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
        theme: buildAppTheme(),
        home: const MowerHomePage(deviceId: _mowerId),
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
        theme: buildAppTheme(),
        navigatorObservers: <NavigatorObserver>[AppRoutes.routeObserver],
        home: const DeviceSearchPage(),
      ),
    ),
  );
  await tester.pump();
}
