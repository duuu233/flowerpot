import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../state.dart';
import '../../tuya/tuya_raw.dart';
import 'mower_dp.dart';

/// 割草机这一台设备的当前 DP 值 + 下发/上报的唯一入口。
///
/// ## 只接真机（2026-09-23 起）
///
/// 下发走涂鸦 SDK（`FlowerpotState.publishMowerDps`，和花盆同一道离线门禁），界面先本地回显；
/// 设备上报从 `FlowerpotState.mowerReports` 进来，按原始 DP 值解（[_applyReported]）。
/// V2.2 §1「设备校验不通过时不回显，App 控件约 3~5 秒后超时回弹」：下发后
/// [echoTimeout] 内这条 DP 没有上报，就按设备快照里的值画回去（[_armEchoCheck]）。
/// 下发失败（离线、SDK 报错）同样画回去，并经 [failures] 交给页面弹提示。
///
/// ⚠️ 2026-09-23 开始联调，**静态演示模式整个删掉**（写死的割草机入口、稿子上的初值、
/// 长按电量环的模拟上报、端上「默认计划」模板）。没绑设备时下发一律不发、只记一条日志。
///
/// ⚠️ **单例**：同一时间只会开着一套割草机页面，外壳（`MowerHomePage`）进来时 [bind]、
/// 退出时 [release]，页面散在各处都读 [instance]。要同时开两台再按 deviceId 分实例。
class MowerDevice extends ChangeNotifier {
  MowerDevice._() {
    _loadLiveDefaults();
  }

  static final MowerDevice instance = MowerDevice._();

  /// 下发后等设备回显的时长（V2.2 §1：App 控件约 3~5 秒后超时回弹）。
  static const Duration echoTimeout = Duration(seconds: 5);

  // ── 控制类 ──────────────────────────────────────────────
  /// DP2：true=运行中（按钮显示「停止」），false=已暂停（按钮显示「继续」）。
  late bool switchGo;

  /// DP3：当前工作模式。
  late MowerMode mode;

  /// **上一次下发过的作业模式**，用于「记忆」：停止之后再启动，设备按最后一次
  /// DP3 启动（V2.2 §3.2「启动=true(待机态)：按 App 最后下发的 DP3 模式启动」）。
  /// 没点过就是 null——这时启动只发 DP2，设备按它自己记的来。
  MowerMode? lastCommandedMode;

  // ── 只上报类 ────────────────────────────────────────────
  /// DP5：工作状态。
  late MowerStatus status;

  /// DP13：电量。
  late int battery;

  /// DP18：故障位图。0 = 无故障。
  late int faultBitmap;

  /// DP117：充电状态。
  late MowerChargingStatus charging;

  /// DP118：盖子。true=合盖（可启动）。
  late bool coverClosed;

  // ── 设置类 ──────────────────────────────────────────────
  /// DP104 / DP105 / DP102：雨淋检测、雨后延迟（分钟）、雨滴延时开关。
  late bool rainDetectEnable;
  late int rainDelayMinutes;
  late bool rainDelaySwitch;

  /// DP106 / DP107 / DP108 / DP114：时间自动同步、时区枚举序、夏令时、上次对时。
  late bool timeSyncEnable;
  late int timezoneIndex;
  late bool dstEnable;
  String? deviceTimeUtcSeconds;

  /// DP109：机器语言。null = 设备还没报过，界面按手机语言显示默认值。
  MowerLanguage? language;

  /// DP101：一周计划（界面序，0=周日）。**不存数据库，显示依赖 DP 解析**
  /// （2026-09-18 用户明确）——这里存的就是最后一次下发/上报解析出来的那份。
  ///
  /// 按设备上报；没报过就是空周。
  late List<MowerScheduleDay> schedule;

  /// DP101 最近一次的**原始 88 字节**与来源（「设备上报」/「本机下发」）、时间。
  /// 计划页底部的临时窗口和联调日志拿它逐字节解析（[MowerScheduleCodec.describe]）。
  Uint8List? scheduleRaw;
  String scheduleRawSource = '';
  DateTime? scheduleRawAt;

  /// DP103：五个区域的百分比与距离。
  late List<MowerZoneConfig> zones;

  // ── 绑定（真机） ────────────────────────────────────────
  String? _deviceId;
  Object? _owner;
  StreamSubscription<({String deviceId, Set<int> changedDps})>? _reportSub;

  /// 下发排队：每条按调用顺序等上一条发完再发。时间同步要求 DP106 → 107 → 108 → 114
  /// 的顺序（V2.2 §9.6），异步各发各的会乱序。
  Future<void> _queue = Future<void>.value();

  /// 已下发、还在等回显的 DP → 那次下发的序号（同一条 DP 又发了一次，旧的那次就不再回弹）。
  final Map<int, int> _awaitingEcho = <int, int>{};
  int _sendSeq = 0;
  final Set<Timer> _echoTimers = <Timer>{};

  final StreamController<String> _failures =
      StreamController<String>.broadcast();

  /// 当前绑的设备 ID；null = 还没绑（页面还没进来或已经退出）。
  String? get deviceId => _deviceId;

  /// 是不是绑着设备（下发走 SDK、上报来自设备）。
  bool get isLive => _deviceId != null;

  /// 下发失败时给页面看的一句话（外壳 `MowerHomePage` 订阅并弹提示）。
  Stream<String> get failures => _failures.stream;

  /// 进割草机页面时绑定：先摆一套「设备还没报」的中性初值，再从设备快照把已上报的 DP
  /// 全部解一遍，之后订阅这台设备的上报。
  Future<void> bind(
    FlowerpotState state, {
    required Object owner,
    required String deviceId,
  }) async {
    _owner = owner;
    _releaseLive();
    _deviceId = deviceId;
    _loadLiveDefaults();
    notifyListeners();
    _reportSub = state.mowerReports
        .where((report) => report.deviceId == deviceId)
        .listen(
          (report) => unawaited(_syncFromDevice(state, report.changedDps)),
        );
    await _syncFromDevice(state, null);
  }

  /// 退出割草机页面时解绑。[owner] 不是当前绑定者（已经被新进来的一套页面重绑过）就不动。
  void release(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _releaseLive();
  }

  void _releaseLive() {
    unawaited(_reportSub?.cancel());
    _reportSub = null;
    for (final timer in _echoTimers) {
      timer.cancel();
    }
    _echoTimers.clear();
    _awaitingEcho.clear();
    _deviceId = null;
  }

  /// 用例之间必须调一次：这是个单例，上一条用例改过的开关会漏到下一条。
  void resetForTest() {
    _owner = null;
    _releaseLive();
    _queue = Future<void>.value();
    _loadLiveDefaults();
    notifyListeners();
  }

  /// 真机「设备还没报」时的中性初值：**不编数**。快照里有的 DP 随后由 [_applyReported] 覆盖。
  ///
  /// - 计划为空周、五个区都是 0%（未配置）——真机上不能再画稿子上的演示色块；
  /// - 盖子按合盖（没报就不拦启动，设备自己会拒）；
  /// - 时区按手机当前时区（DP107 没报时时间同步页的默认选中项）。
  void _loadLiveDefaults() {
    switchGo = false;
    mode = MowerMode.standby;
    lastCommandedMode = null;
    status = MowerStatus.standby;
    battery = 0;
    faultBitmap = 0;
    charging = MowerChargingStatus.notCharging;
    coverClosed = true;
    rainDetectEnable = false;
    rainDelayMinutes = 0;
    rainDelaySwitch = false;
    timeSyncEnable = false;
    timezoneIndex = MowerTimezone.fromDeviceOffset(DateTime.now().timeZoneOffset);
    dstEnable = false;
    deviceTimeUtcSeconds = null;
    language = null;
    schedule = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
    scheduleRaw = null;
    scheduleRawSource = '';
    scheduleRawAt = null;
    zones = <MowerZoneConfig>[
      for (var index = 1; index <= 5; index++)
        MowerZoneConfig(index: index, percent: 0, meters: 0),
    ];
  }

  /// 首页黄色提醒那一行：有故障时是 DP18 的文案，没有故障是安全提示。
  String? get faultMessage => MowerFault.firstMessage(faultBitmap);

  /// 左边三颗（自动/定点/回归）此刻能不能点——**不含**「当前模式置灰」那条（[isCurrentMode]
  /// 是单独判断，见页面）。点之前还要过盖子那道预检（[coverClosed]，在页面里弹窗）。
  ///
  /// 口径：
  /// - 2026-09-18：按下「停止」之后三颗不可点，「继续」后恢复；
  /// - 2026-09-23 更正：「DP3 不等于这颗按钮时就应该能正常点」。原来写成 `switchGo`，
  ///   待机态设备报的 DP2 也是 false，结果刚开机连「自动」都点不了、没法启动
  ///   （协议 §9.2：待机启动就是发 DP3=smart）。所以「停止」改按设备真的**暂停了**来认：
  ///   DP5 = paused（协议 §9.3：停止发 DP2=false → 设备报 DP5=paused）。
  bool get commandsEnabled => status != MowerStatus.paused;

  /// 这个模式是不是当前 DP3 的值——是就置灰，不给重复下发。
  bool isCurrentMode(MowerMode target) => mode == target;

  // ── 下发 ────────────────────────────────────────────────

  /// 工作开关（DP2）。[on]=true 启动/继续，false 停止/暂停。
  void setSwitch(FlowerpotState state, {required bool on}) {
    _deliver(state, MowerDp.switchGo, on, action: on ? '继续/启动' : '停止');
    switchGo = on;
    // DP3 / DP5 以设备上报为准（启动后设备按最后一次 DP3 跑，会自己报上来）。
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
    _rememberSchedule(state, data, '本机下发');
    schedule = List<MowerScheduleDay>.of(week);
    notifyListeners();
  }

  /// 恢复默认割草计划（DP110 = true，V2.3）。**本地不改计划**：设备写入默认计划后会自己上报 DP101，
  /// 界面等那条上报再刷（执行成功的依据就是它）；设备随后把 DP110 回写 false，这条回写正好消掉回显等待。
  void resetSchedule(FlowerpotState state) {
    _deliver(
      state,
      MowerDp.scheduleReset,
      true,
      action: '恢复默认割草计划，等设备回报 DP${MowerDp.mowSchedule}',
    );
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

  // ── 上报 ────────────────────────────────────────────────

  /// 从设备快照同步。[changed] 为 null = 刚绑定时整份解一遍；否则只解这条报文带的 DP
  /// （并把它们从「等回显」里划掉）。
  Future<void> _syncFromDevice(FlowerpotState state, Set<int>? changed) async {
    final id = _deviceId;
    if (id == null) return;
    final dps = await state.mowerDps(id);
    if (dps == null || _deviceId != id) return;
    // 这一次有没有把 DP101 刷进来：有就逐字节解析打进日志（下面三个分支口径各不相同）。
    final scheduleTouched = changed == null
        ? dps.containsKey(MowerDp.mowSchedule)
        : changed.isEmpty
        ? dps.containsKey(MowerDp.mowSchedule) &&
              !_awaitingEcho.containsKey(MowerDp.mowSchedule)
        : changed.contains(MowerDp.mowSchedule);
    if (changed == null) {
      _applyReported(dps);
      state.logMowerInteraction(
        '读取 ← 割草机设备快照 ${dps.length} 个 DP：'
        '${dps.keys.toList()..sort()}',
      );
    } else if (changed.isEmpty) {
      // 整包快照（`onDevInfoUpdate`，报文里没有逐条 DP）：全部刷一遍，但**跳过还在等回显的**——
      // 快照里还是下发前的旧值，这时刷回去界面会先闪回旧值、再被回显拉回来。
      _applyReported(
        dps,
        only: dps.keys.where((dp) => !_awaitingEcho.containsKey(dp)),
      );
    } else {
      _applyReported(dps, only: changed);
      for (final dp in changed) {
        _awaitingEcho.remove(dp);
        final identifier = MowerDp.identifiers[dp] ?? 'dp$dp';
        state.logMowerInteraction('上报 ← 割草机 DP$dp $identifier=${dps[dp]}');
      }
    }
    if (scheduleTouched) {
      final bytes = TuyaRaw.bytes(dps[MowerDp.mowSchedule]);
      if (bytes != null) {
        _rememberSchedule(state, Uint8List.fromList(bytes), '设备上报');
      } else {
        state.logMowerInteraction(
          '解析 ✗ 割草机 DP${MowerDp.mowSchedule} 认不出的值：${dps[MowerDp.mowSchedule]}',
        );
      }
    }
    notifyListeners();
  }

  /// 按设备快照里的原始值刷新字段。[only] 给了就只刷这几条。
  ///
  /// 值的形态按涂鸦：bool 型给 bool、value 型给整数、enum 型给**字符串**（个别桥接给序号，
  /// 也认）、raw 型给 SDK 转好的**十六进制串**（`TuyaRaw.bytes` 同时兼容 base64）。
  /// 认不出的值不动原字段——宁可停在上一个值，也不要画一个猜出来的。
  void _applyReported(Map<int, Object?> dps, {Iterable<int>? only}) {
    final targets = only ?? dps.keys;
    for (final dp in targets) {
      if (!dps.containsKey(dp)) continue;
      final value = dps[dp];
      switch (dp) {
        case MowerDp.switchGo:
          switchGo = _asBool(value) ?? switchGo;
        case MowerDp.mode:
          mode =
              MowerDp.enumOf(MowerMode.values, (item) => item.code, value) ??
              mode;
        case MowerDp.status:
          status =
              MowerDp.enumOf(MowerStatus.values, (item) => item.code, value) ??
              status;
        case MowerDp.battery:
          battery = (_asInt(value) ?? battery).clamp(0, 100);
        case MowerDp.fault:
          faultBitmap = _asInt(value) ?? faultBitmap;
        case MowerDp.chargingStatus:
          charging =
              MowerDp.enumOf(
                MowerChargingStatus.values,
                (item) => item.code,
                value,
              ) ??
              charging;
        case MowerDp.coverStatus:
          coverClosed = _asBool(value) ?? coverClosed;
        case MowerDp.mowSchedule:
          final scheduleBytes = TuyaRaw.bytes(value);
          if (scheduleBytes != null &&
              scheduleBytes.length >= MowerScheduleCodec.bytes) {
            schedule = MowerScheduleCodec.decode(
              Uint8List.fromList(scheduleBytes),
            );
          }
        case MowerDp.zoneConfig:
          final zoneBytes = TuyaRaw.bytes(value);
          if (zoneBytes != null && zoneBytes.length >= MowerZoneCodec.bytes) {
            zones = MowerZoneCodec.decode(zoneBytes);
          }
        case MowerDp.rainDelaySwitch:
          rainDelaySwitch = _asBool(value) ?? rainDelaySwitch;
        case MowerDp.rainDetectEnable:
          rainDetectEnable = _asBool(value) ?? rainDetectEnable;
        case MowerDp.rainDelay:
          rainDelayMinutes = _asInt(value) ?? rainDelayMinutes;
        case MowerDp.timeSyncEnable:
          timeSyncEnable = _asBool(value) ?? timeSyncEnable;
        case MowerDp.timezone:
          timezoneIndex = MowerTimezone.indexOfCode(value) ?? timezoneIndex;
        case MowerDp.dstEnable:
          dstEnable = _asBool(value) ?? dstEnable;
        case MowerDp.deviceTime:
          final timeText = '${value ?? ''}'.trim();
          if (timeText.isNotEmpty) deviceTimeUtcSeconds = timeText;
        case MowerDp.language:
          language =
              MowerDp.enumOf(MowerLanguage.values, (item) => item.code, value) ??
              language;
        default:
          break;
      }
    }
  }

  /// 记下 DP101 原始字节并逐行解析进联调日志。
  void _rememberSchedule(FlowerpotState state, Uint8List data, String source) {
    scheduleRaw = data;
    scheduleRawSource = source;
    scheduleRawAt = DateTime.now();
    state.logMowerInteraction(
      '解析 · 割草机 DP${MowerDp.mowSchedule} mow_schedule（$source，${data.length} 字节）',
    );
    for (final line in MowerScheduleCodec.describe(data)) {
      state.logMowerInteraction('　　$line');
    }
  }

  static bool? _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = '$value'.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value'.trim());
  }

  // ── 内部 ────────────────────────────────────────────────

  /// **唯一的下发出口**：记日志，再经 SDK 发给设备（[_publish]）。
  void _deliver(FlowerpotState state, int dp, Object value, {String? action}) {
    final identifier = MowerDp.identifiers[dp] ?? 'dp$dp';
    final suffix = action == null ? '' : '（$action）';
    state.logMowerInteraction('下发 → 割草机 DP$dp $identifier=$value$suffix');
    _publish(state, <int, Object>{dp: value}, label: 'DP$dp $identifier=$value');
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
      // 涂鸦 raw 型 DP 在设备侧就是这串 base64，联调时要拿它和平台日志对
      ..logMowerInteraction('　　base64: ${base64Encode(data)}');
    // App 侧交给 SDK 的是**十六进制串**，SDK 的 DevUtil.encodeRaw 自己转成 base64
    // （与花盆纪念日 154 等 raw 下发同一口径，见 TuyaRaw）。
    _publish(
      state,
      <int, Object>{dp: TuyaRaw.hex(data)},
      label: 'DP$dp $identifier=${data.length}B',
    );
  }

  /// 真机下发：排进队列按顺序发；失败就把界面画回设备快照并报给页面，成功就等回显。
  void _publish(
    FlowerpotState state,
    Map<int, Object> dps, {
    required String label,
  }) {
    final id = _deviceId;
    if (id == null) {
      state.logMowerInteraction('下发跳过 ⚠ 割草机 $label：还没绑定设备');
      return;
    }
    final seq = ++_sendSeq;
    for (final dp in dps.keys) {
      _awaitingEcho[dp] = seq;
    }
    _queue = _queue
        .then((_) async {
          if (_deviceId != id) return;
          final result = await state.publishMowerDps(id, dps);
          if (_deviceId != id) return;
          if (!result.success) {
            for (final dp in dps.keys) {
              if (_awaitingEcho[dp] == seq) _awaitingEcho.remove(dp);
            }
            state.logMowerInteraction('下发失败 ✗ 割草机 $label：${result.message}');
            if (!_failures.isClosed) {
              _failures.add(
                result.code == 'device_offline'
                    ? '割草机已离线，指令没有发出去'
                    : '指令没有发出去：${result.message}',
              );
            }
            await _revertToDevice(state, id, dps.keys);
            return;
          }
          _armEchoCheck(state, id, dps.keys.toList(growable: false), seq);
        })
        .catchError((Object error) {
          state.logMowerInteraction('下发失败 ✗ 割草机 $label：$error');
        });
  }

  /// 下发成功后 [echoTimeout] 内这几条 DP 还没有上报，就按设备快照画回去（V2.2 §1 超时回弹）。
  void _armEchoCheck(FlowerpotState state, String id, List<int> dps, int seq) {
    late final Timer timer;
    timer = Timer(echoTimeout, () {
      _echoTimers.remove(timer);
      if (_deviceId != id) return;
      final missing = <int>[
        for (final dp in dps)
          if (_awaitingEcho[dp] == seq) dp,
      ];
      if (missing.isEmpty) return;
      for (final dp in missing) {
        _awaitingEcho.remove(dp);
      }
      state.logMowerInteraction(
        '回弹 ⚠ 割草机 DP${missing.join('/')} 下发 ${echoTimeout.inSeconds} 秒没有上报，'
        '按设备当前值显示（设备可能拒绝了这条指令）',
      );
      unawaited(_revertToDevice(state, id, missing));
    });
    _echoTimers.add(timer);
  }

  /// 把这几条 DP 画回设备快照里的值。快照里没有的（设备从没报过）就保持现状。
  Future<void> _revertToDevice(
    FlowerpotState state,
    String id,
    Iterable<int> dps,
  ) async {
    final snapshot = await state.mowerDps(id);
    if (snapshot == null || _deviceId != id) return;
    _applyReported(snapshot, only: dps);
    notifyListeners();
  }
}
