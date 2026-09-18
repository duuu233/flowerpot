import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../state.dart';
import 'mower_demo.dart';
import 'mower_dp.dart';

/// 割草机这一台"设备"的当前 DP 值 + 下发/上报的唯一入口。
///
/// ## 这一轮的前提（2026-09-18 用户明确）
///
/// **没有真设备。** 要的是「点页面 / 点按钮就把对应的 DPID 下发、上报出来，
/// 在联调日志里看得见」。所以这里：
///
/// - **下发**：记一条日志（DP 号 + 标识符 + 值 + 这次操作是什么），然后**本地回显**
///   ——真设备是靠上报回显的，没有设备就由这里代劳，否则界面点完不动，什么都验不了；
/// - **上报**：只读 DP（DP5/DP13/DP18/DP117/DP118）没有设备会推，由
///   [report] 模拟，日志里**标了「模拟」**，别和真设备上报混为一谈；
/// - **接真设备时只改一处**：[_deliver]。把那一行换成
///   `FlowerpotState.publishDps(deviceId, {dp: value})` 即可，页面一行都不用动。
///
/// ⚠️ **单例**：这一轮只有一台写死的演示割草机（见 `MowerDemo`），页面散在各处、
/// 又没有设备列表可挂，单例是最省事且不会出错的做法。接了真设备之后要按 deviceId
/// 分实例，那时把这里换成 `FlowerpotState` 里的一张表。
class MowerDevice extends ChangeNotifier {
  MowerDevice._();

  static final MowerDevice instance = MowerDevice._();

  // ── 控制类（下发后本地回显） ────────────────────────────
  /// DP2：true=运行中（按钮显示「停止」），false=已暂停（按钮显示「继续」）。
  bool switchGo = false;

  /// DP3：当前工作模式。
  MowerMode mode = MowerMode.standby;

  /// **上一次下发过的作业模式**，用于「记忆」：停止之后再启动，设备按最后一次
  /// DP3 启动（V2.2 §3.2「启动=true(待机态)：按 App 最后下发的 DP3 模式启动」）。
  /// 没点过就是 null——这时启动只发 DP2，设备按它自己记的来。
  MowerMode? lastCommandedMode;

  // ── 只上报类（没有设备，由 [report] 模拟） ──────────────
  /// DP5：工作状态。
  MowerStatus status = MowerStatus.standby;

  /// DP13：电量。
  int battery = 78;

  /// DP18：故障位图。0 = 无故障。
  int faultBitmap = 0;

  /// DP117：充电状态。
  MowerChargingStatus charging = MowerChargingStatus.notCharging;

  /// DP118：盖子。true=合盖（可启动）。
  bool coverClosed = true;

  // ── 设置类（下发后本地回显） ────────────────────────────
  /// DP104 / DP105 / DP102：雨淋检测、雨后延迟（分钟）、雨滴延时开关。
  bool rainDetectEnable = true;
  int rainDelayMinutes = 180;
  bool rainDelaySwitch = true;

  /// DP106 / DP107 / DP108 / DP114：时间自动同步、时区枚举序、夏令时、上次对时。
  bool timeSyncEnable = true;
  int timezoneIndex = MowerTimezone.zeroIndex + 8;
  bool dstEnable = false;
  String? deviceTimeUtcSeconds;

  /// DP109：机器语言。null = 设备还没报过，界面按手机语言显示默认值。
  MowerLanguage? language;

  /// DP101：一周计划（界面序，0=周日）。**不存数据库，显示依赖 DP 解析**
  /// （2026-09-18 用户明确）——这里存的就是最后一次下发/上报解析出来的那份。
  ///
  /// ⚠️ **初值取的是端上默认模板**（[defaultSchedule]，就是稿子上画的那几块）：
  /// 没有真设备就没有 DP101 上报，真按"空"起页面上一根色块都没有，编辑/重叠/恢复默认
  /// 这几条动线全验不了。接了真机之后这里应当改成空、等设备上报填。
  List<MowerScheduleDay> schedule = defaultSchedule();

  /// 「恢复默认」与首次进入用的那份计划：稿子上画的四块（见 [MowerDemoPlan.slots]）。
  ///
  /// ⚠️ 它是**端上的默认模板**，设备侧没有「默认计划」这个概念——恢复默认 =
  /// 把这份模板整周下发下去。
  static List<MowerScheduleDay> defaultSchedule() {
    final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
    for (final slot in MowerDemoPlan.slots) {
      final current = week[slot.day];
      final value = MowerScheduleSlot(
        startMinutes: slot.startMinutes,
        endMinutes: slot.endMinutes,
      );
      week[slot.day] = MowerScheduleDay(
        slotOne: slot.slot == 1 ? value : current.slotOne,
        slotTwo: slot.slot == 2 ? value : current.slotTwo,
        edge: current.edge || slot.trim,
      );
    }
    return week;
  }

  /// 用例之间必须调一次：这是个单例，上一条用例改过的开关会漏到下一条。
  void resetForTest() {
    switchGo = false;
    mode = MowerMode.standby;
    lastCommandedMode = null;
    status = MowerStatus.standby;
    battery = 78;
    faultBitmap = 0;
    charging = MowerChargingStatus.notCharging;
    coverClosed = true;
    rainDetectEnable = true;
    rainDelayMinutes = 180;
    rainDelaySwitch = true;
    timeSyncEnable = true;
    timezoneIndex = MowerTimezone.zeroIndex + 8;
    dstEnable = false;
    deviceTimeUtcSeconds = null;
    language = null;
    schedule = defaultSchedule();
    zones = const <MowerZoneConfig>[
      MowerZoneConfig(index: 1, percent: 10, meters: 30),
      MowerZoneConfig(index: 2, percent: 15, meters: 50),
      MowerZoneConfig(index: 3, percent: 20, meters: 80),
      MowerZoneConfig(index: 4, percent: 25, meters: 120),
      MowerZoneConfig(index: 5, percent: 30, meters: 60),
    ];
    notifyListeners();
  }

  /// DP103：五个区域的百分比与距离。
  List<MowerZoneConfig> zones = const <MowerZoneConfig>[
    MowerZoneConfig(index: 1, percent: 10, meters: 30),
    MowerZoneConfig(index: 2, percent: 15, meters: 50),
    MowerZoneConfig(index: 3, percent: 20, meters: 80),
    MowerZoneConfig(index: 4, percent: 25, meters: 120),
    MowerZoneConfig(index: 5, percent: 30, meters: 60),
  ];

  /// 首页黄色提醒那一行：有故障时是 DP18 的文案，没有故障是安全提示。
  String? get faultMessage => MowerFault.firstMessage(faultBitmap);

  /// 左边三颗（自动/定点/回归）此刻能不能点。
  ///
  /// 口径（2026-09-18 用户）：**启动/停止优先级最高**，只有启动（DP2=true）状态下
  /// 左边三颗才能点；同一个模式不能重复点（[isCurrentMode]），点之前还要过盖子那道
  /// 预检（[coverClosed]，在页面里弹窗）。
  bool get commandsEnabled => switchGo;

  /// 这个模式是不是当前 DP3 的值——是就置灰，不给重复下发。
  bool isCurrentMode(MowerMode target) => mode == target;

  // ── 下发 ────────────────────────────────────────────────

  /// 工作开关（DP2）。[on]=true 启动/继续，false 停止/暂停。
  void setSwitch(FlowerpotState state, {required bool on}) {
    _deliver(state, MowerDp.switchGo, on, action: on ? '继续/启动' : '停止');
    switchGo = on;
    if (on) {
      // 记忆：启动时设备按 App 最后下发的 DP3 模式跑，界面要跟着回到那个模式，
      // 否则用户点过「定点」、停一下再启动，界面上三颗按钮会全是可点的假象。
      final remembered = lastCommandedMode;
      if (remembered != null) {
        mode = remembered;
        _simulateReport(state, MowerDp.mode, remembered.code, note: '启动按记忆模式');
      }
      _applyStatusForMode();
    } else {
      status = MowerStatus.paused;
      _simulateReport(state, MowerDp.status, status.code);
    }
    notifyListeners();
  }

  /// 工作模式（DP3）。只允许 [MowerMode.sendable] 的四个。
  void setMode(FlowerpotState state, MowerMode target) {
    if (!target.sendable) {
      state.logMowerInteraction(
        '下发被拦 ✗ 割草机 DP${MowerDp.mode} mode=${target.code} 是设备自有状态，App 不可下发',
      );
      return;
    }
    _deliver(state, MowerDp.mode, target.code, action: target.label);
    mode = target;
    if (target != MowerMode.standby) {
      lastCommandedMode = target;
    }
    _applyStatusForMode();
    notifyListeners();
  }

  /// 割草计划（DP101，raw 88 字节）。**全量替换**，7 天一起发。
  void setSchedule(FlowerpotState state, List<MowerScheduleDay> week) {
    final data = MowerScheduleCodec.encodeByDay(week);
    _deliverRaw(
      state,
      MowerDp.mowSchedule,
      data,
      hex: MowerScheduleCodec.toHexGroups(data),
      action: '割草计划（全量替换，8 组 × 11 字节）',
    );
    schedule = List<MowerScheduleDay>.of(week);
    notifyListeners();
  }

  /// 区域配置（DP103，raw 25 字节）。**全量替换**，5 个区一起发。
  void setZones(FlowerpotState state, List<MowerZoneConfig> next) {
    final data = MowerZoneCodec.encode(next);
    _deliverRaw(
      state,
      MowerDp.zoneConfig,
      data,
      hex: MowerZoneCodec.toHexZones(data),
      action: '区域配置（全量替换，5 区 × 5 字节）',
    );
    zones = List<MowerZoneConfig>.of(next);
    notifyListeners();
  }

  /// 雨淋设置：检测开关（DP104）+ 延时开关（DP102）+ 雨后延迟（DP105）。
  void setRain(
    FlowerpotState state, {
    required bool detectEnable,
    required bool delaySwitch,
    required int delayMinutes,
  }) {
    _deliver(state, MowerDp.rainDetectEnable, detectEnable, action: '雨淋检测');
    _deliver(state, MowerDp.rainDelaySwitch, delaySwitch, action: '雨滴延时开关');
    final clamped = delayMinutes.clamp(0, 120);
    if (clamped != delayMinutes) {
      state.logMowerInteraction(
        '下发钳位 ⚠ 割草机 DP${MowerDp.rainDelay} 取值范围 0-120 分钟，$delayMinutes → $clamped',
      );
    }
    _deliver(state, MowerDp.rainDelay, clamped, action: '雨后延迟（分钟）');
    rainDetectEnable = detectEnable;
    rainDelaySwitch = delaySwitch;
    rainDelayMinutes = clamped;
    notifyListeners();
  }

  /// 时间同步：DP106 → DP107 → DP108 → DP114，顺序照 V2.2 §9.6 的对时流程。
  ///
  /// ⚠️ DP106 关着时设备会**拒掉 DP114**，所以关的时候就不发时间戳了，只把开关发下去。
  void setTimeSync(
    FlowerpotState state, {
    required bool enable,
    required int timezoneIndex,
    required bool dst,
  }) {
    _deliver(state, MowerDp.timeSyncEnable, enable, action: '时间自动同步');
    final index = timezoneIndex.clamp(0, MowerTimezone.count - 1);
    _deliver(
      state,
      MowerDp.timezone,
      MowerTimezone.codeOf(index),
      action: '时区 ${MowerTimezone.labelOf(index)}',
    );
    _deliver(state, MowerDp.dstEnable, dst, action: '夏令时');
    this.timezoneIndex = index;
    timeSyncEnable = enable;
    dstEnable = dst;
    if (enable) {
      final seconds =
          (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000).toString();
      _deliver(state, MowerDp.deviceTime, seconds, action: '对时（UTC 秒）');
      deviceTimeUtcSeconds = seconds;
    } else {
      state.logMowerInteraction(
        '跳过 ⚠ 割草机 DP${MowerDp.deviceTime} 未下发：DP${MowerDp.timeSyncEnable} 关闭时设备会拒绝对时',
      );
    }
    notifyListeners();
  }

  /// 机器语言（DP109）。
  void setLanguage(FlowerpotState state, MowerLanguage target) {
    _deliver(state, MowerDp.language, target.code, action: '机器语言 ${target.label}');
    language = target;
    notifyListeners();
  }

  /// 这一块功能还没有对应的 DPID（或本轮不接）：日志记一条，页面自己弹提示。
  void logUnsupported(FlowerpotState state, String feature) {
    state.logMowerInteraction('未接 ⚠ 割草机「$feature」当前还没有支持的 DPID');
  }

  // ── 上报（没有设备，模拟） ──────────────────────────────

  /// 模拟设备上报一条只读 DP。调试面板用（见 `MowerControlPage` 的长按入口）。
  void report(FlowerpotState state, int dp, Object value) {
    switch (dp) {
      case MowerDp.coverStatus:
        coverClosed = value == true;
      case MowerDp.fault:
        faultBitmap = value is int ? value : 0;
      case MowerDp.battery:
        battery = value is int ? value.clamp(0, 100) : battery;
      case MowerDp.chargingStatus:
        charging = MowerChargingStatus.values.firstWhere(
          (item) => item.code == value,
          orElse: () => charging,
        );
      case MowerDp.status:
        status = MowerStatus.values.firstWhere(
          (item) => item.code == value,
          orElse: () => status,
        );
      default:
        break;
    }
    _simulateReport(state, dp, value);
    notifyListeners();
  }

  // ── 内部 ────────────────────────────────────────────────

  /// 模式变了之后把 DP5 摆到对应的状态上（真设备是自己报的）。
  void _applyStatusForMode() {
    status = switch (mode) {
      MowerMode.standby => switchGo ? MowerStatus.standby : MowerStatus.paused,
      MowerMode.smart => MowerStatus.mowing,
      MowerMode.spot => MowerStatus.spotMowing,
      MowerMode.gotoCharge => MowerStatus.gotoCharge,
      MowerMode.edgeMowing => MowerStatus.edgeMowing,
      MowerMode.secondary => MowerStatus.secondary,
      MowerMode.waitCharge => MowerStatus.waitCharge,
      MowerMode.waitRain => MowerStatus.waitRain,
    };
  }

  /// **唯一的下发出口**。接真设备时把这里换成 `state.publishDps`，页面不用动。
  void _deliver(FlowerpotState state, int dp, Object value, {String? action}) {
    final identifier = MowerDp.identifiers[dp] ?? 'dp$dp';
    final suffix = action == null ? '' : '（$action）';
    state.logMowerInteraction('下发 → 割草机 DP$dp $identifier=$value$suffix');
  }

  void _deliverRaw(
    FlowerpotState state,
    int dp,
    Uint8List data, {
    required String hex,
    String? action,
  }) {
    final identifier = MowerDp.identifiers[dp] ?? 'dp$dp';
    final suffix = action == null ? '' : '（$action）';
    state
      ..logMowerInteraction(
        '下发 → 割草机 DP$dp $identifier=${data.length}B$suffix',
      )
      ..logMowerInteraction('　　raw hex: $hex')
      // 涂鸦 raw 型 DP 的下发值就是 base64，联调时要拿它和平台日志对
      ..logMowerInteraction('　　base64: ${base64Encode(data)}');
  }

  /// 本地回显 / 模拟上报都走这里，日志里明写「模拟」——没有真设备，
  /// 这一行不是设备报上来的，别让人对着日志误判固件行为。
  void _simulateReport(FlowerpotState state, int dp, Object value, {String? note}) {
    final identifier = MowerDp.identifiers[dp] ?? 'dp$dp';
    final suffix = note == null ? '' : '（$note）';
    state.logMowerInteraction('上报 ← 割草机 DP$dp $identifier=$value$suffix［模拟］');
  }
}
