import 'dart:typed_data';

import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/pairing_gate.dart';
import 'package:flowerpot/src/features/devices/presentation/device_search_page.dart';
import 'package:flowerpot/src/features/mower/mower_device.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/presentation/mower_home_page.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_plan_edit_sheet.dart';
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

    // 空的那天开编辑框：两个时段都是关着的 00:00–00:00，不再是稿子上的 09:00–11:30
    final draft = MowerPlanDraft.forDay(1, MowerDevice.instance.schedule);
    expect(draft.one.enabled, isFalse);
    expect(draft.two.enabled, isFalse);
    expect(draft.one.startMinutes, 0);
    expect(draft.one.endMinutes, 0);
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

  testWidgets('割草计划页按设备报的计划合计工作时间，取消勾选就整周下发', (tester) async {
    final repository = await _pumpMowerHome(tester, <int, Object?>{
      MowerDp.mowSchedule: TuyaRaw.hex(
        MowerScheduleCodec.encodeByDay(_week()),
      ),
    });
    await tester.tap(find.byKey(const Key('mower-nav-plan')));
    await tester.pump();

    expect(find.text('总工作时间：5小时23分钟'), findsOneWidget);
    // 周日那两段（08:00–09:00、14:00–15:00）一取消勾选就从合计里去掉。
    await tester.tap(find.byKey(const Key('mower-plan-day-0')));
    await tester.pump();
    expect(find.text('总工作时间：3小时23分钟'), findsOneWidget);
    expect(_sentDps(repository), <int>[MowerDp.mowSchedule]);
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
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _MowerRepository()..rawDpsByDevice[_mowerId] = snapshot;
  setup?.call(repository);
  final state = FlowerpotState(repository: repository);
  addTearDown(state.dispose);
  await state.initialize();
  await state.refreshDevices();
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
