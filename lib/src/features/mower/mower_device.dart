import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../state.dart';
import '../../tuya/tuya_raw.dart';
import 'mower_dp.dart';
import 'mower_command_result.dart';
import 'mower_fault_alarm.dart';

/// 割草机这一台设备的当前 DP 值 + 下发/上报的唯一入口。
///
/// ## 只接真机（2026-09-23 起）
///
/// 下发走涂鸦 SDK（`FlowerpotState.publishMowerDps`，和花盆同一道离线门禁），界面先本地回显；
/// 设备上报从 `FlowerpotState.mowerReports` 进来，按原始 DP 值解（[_applyReported]）。
/// V2.2 §1「设备校验不通过时不回显，App 控件约 3~5 秒后超时回弹」：下发后
/// [echoTimeout] 内这条 DP 没有上报，就按设备快照里的值画回去（[_armEchoCheck]）。
/// 下发失败（离线、SDK 报错）同样画回去，并经 [failures] 交给页面弹提示。
/// V2.6 的 DP115 新回执通过 [commandResults] 通知控制页；仅关联本会话
/// 实际发送的 DP2/DP3，设备 seq 独立于发送队列序号。
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

  /// 蓝牙掉了之后后台自动重连的最短间隔（不弹框；点按钮时的连接不受它限制）。
  static const Duration autoReconnectEvery = Duration(seconds: 30);

  // ── 连接状态（2026-09-23：首页蓝牙 / Wi-Fi 图标各亮各的，读涂鸦的分通道状态） ──
  /// 手机和设备的蓝牙连着（涂鸦 `isBleLocalOnline`）。
  bool bleLinked = false;

  /// 设备经 Wi-Fi 在线（涂鸦 MQTT / 局域网 / 云端在线任一）。
  bool wifiLinked = false;

  DateTime? _lastAutoConnect;
  bool _autoConnecting = false;

  /// 绑定期间监听状态层（设备在线变化由涂鸦 `onStatusChanged` 推到那里），
  /// ⚠️ 涂鸦答复里说的「监听 onDeviceOffline」在 App SDK 7.5.1 里**没有这个方法**（全模块 0 命中）；
  /// 等价的是设备监听 `IDevListener.onStatusChanged(devId, online)`，online=false 即离线——原生对账号下
  /// 每台设备都注册了（`MainActivity.watchDevices`），事件 → 状态层 `device.online` → 这里。另有每 3 秒
  /// 的主动查询兜底（`refreshLink`）。
  /// Wi-Fi 一掉线就**主动降级连蓝牙**（2026-09-23 产品：「设备离线后，需要主动通过监听降级为蓝牙连接」）。
  FlowerpotState? _watchedState;
  bool? _lastOnline;
  bool _lastShutdown = false;
  Object? _lastDeviceSnapshot;
  int _snapshotSequence = 0;
  final Map<int, int> _appliedDpReads = {};

  // ── 控制类 ──────────────────────────────────────────────
  /// DP2：true=运行中（按钮显示「停止」），false=已暂停（按钮显示「继续」）。
  late bool switchGo;

  /// DP119：设备最后上报的工作时长（整数小时），未上报为 null。
  int? operatingTimeHours;

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
  bool hasBatteryReport = false;

  /// DP18：故障位图。0 = 无故障。
  ///
  /// null = 设备还没报过（这时不显示任何故障文案，见 [faultMessage]）。
  int? faultBitmap;
  MowerFaultAlarm? faultAlarm;
  Completer<MowerFaultAlarm?>? _freshFaultWaiter;
  Timer? _faultReadTimer;
  Future<MowerFaultAlarm?>? _commandFaultRead;

  /// DP117：充电状态。
  late MowerChargingStatus charging;
  bool _chargingReported = false;

  /// 只展示有效DP117返回的含义，未上报时不把默认枚举当成设备状态。
  String? get chargingLabel =>
      _chargingReported && charging != MowerChargingStatus.notCharging
      ? charging.label
      : null;

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
  /// （2026-09-18 用户明确）——这里只保存最后有效设备返回，下发草稿不改变显示。
  ///
  /// 按设备上报；没报过就是空周。
  late List<MowerScheduleDay> schedule;

  /// DP101 最近一次返回的**原始字节**与来源（「设备快照」/「设备上报」）、时间。
  /// 计划页底部的临时窗口和联调日志拿它逐字节解析（[MowerScheduleCodec.describe]）；下发另存。
  Uint8List? scheduleRaw;
  String scheduleRawSource = '';
  DateTime? scheduleRawAt;

  /// 最近一次下发的草稿，不能替代设备快照或上报。
  Uint8List? scheduleSentRaw;
  DateTime? scheduleSentAt;
  bool hasScheduleReport = false;
  MowerCommandResult? scheduleCommandResult;
  int _scheduleReadSequence = 0;
  bool get schedulePending => _awaitingEcho.containsKey(MowerDp.mowSchedule);

  /// DP103：五个区域的百分比与距离。
  late List<MowerZoneConfig> zones;

  // ── 绑定（真机） ────────────────────────────────────────
  String? _deviceId;
  Object? _owner;
  // 设备 ID 相同也可能是退出后重进；旧会话的回调不能写进新页面。
  int _bindingGeneration = 0;
  Future<void>? _linkRefresh;

  bool _isCurrent(String id, int generation) =>
      _deviceId == id && _bindingGeneration == generation;
  StreamSubscription<
    ({String deviceId, Set<int> changedDps, Map<int, Object?> reportedDps})
  >?
  _reportSub;

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

  /// 区分退出后重进同一设备的会话，防止旧弹窗启动新会话。
  int get bindingGeneration => _bindingGeneration;

  /// 是不是绑着设备（下发走 SDK、上报来自设备）。
  bool get isLive => _deviceId != null;

  /// 下发失败时给页面看的一句话（外壳 `MowerHomePage` 订阅并弹提示）。
  Stream<String> get failures => _failures.stream;

  MowerCommandResult? _lastCommandResult;
  final Map<int, _PendingMowerCommand> _pendingCommands = {};
  final StreamController<({MowerCommandResult result, int generation})>
  _commandResults = StreamController.broadcast();

  /// 仅本会话实际下发的 DP2/3 的新回执；快照旧值和无关 DP 不通知页面。
  Stream<({MowerCommandResult result, int generation})> get commandResults =>
      _commandResults.stream;

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
    final generation = _bindingGeneration;
    _loadLiveDefaults();
    notifyListeners();
    // 进页面就把蓝牙连上（2026-09-23 产品：「我进来设备正常情况下 wifi 和蓝牙图标应该都是亮的」）。
    unawaited(refreshLink(state, autoConnect: true));
    _watchedState = state;
    _lastDeviceSnapshot = state.deviceById(deviceId);
    _lastOnline = state.deviceById(deviceId)?.online;
    _lastShutdown = state.isMowerShutdown(deviceId);
    state.addListener(_onStateChanged);
    _reportSub = state.mowerReports
        .where((report) => _isCurrent(report.deviceId, generation))
        .listen(
          (report) => unawaited(
            _syncFromDevice(
              state,
              report.changedDps,
              reported: report.reportedDps,
            ),
          ),
          onError: (Object error) {
            if (!_isCurrent(deviceId, generation)) return;
            state.logMowerInteraction('设备上报监听失败 ✗ 割草机：$error');
          },
        );
    await _syncFromDevice(state, null);
  }

  /// 退出割草机页面时解绑。[owner] 不是当前绑定者（已经被新进来的一套页面重绑过）就不动。
  void release(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _releaseLive();
  }

  /// 设备在线状态从 true 变 false：立刻降级连蓝牙（不受 [autoReconnectEvery] 节流）。
  /// 已关机（DP113）的那次离线是预期的：不降级、不报掉线（协议 V2.5 §9.9）。
  void _onStateChanged() {
    final state = _watchedState;
    final id = _deviceId;
    if (state == null || id == null) return;
    final snapshot = state.deviceById(id);
    if (!identical(snapshot, _lastDeviceSnapshot)) {
      _lastDeviceSnapshot = snapshot;
      unawaited(_syncFromDevice(state, const <int>{}));
    }
    final online = state.deviceById(id)?.online;
    final was = _lastOnline;
    _lastOnline = online;
    final off = state.isMowerShutdown(id);
    if (online != was || off != _lastShutdown) {
      _lastShutdown = off;
      notifyListeners();
    }
    if (was == true && online == false) {
      if (off) {
        state.logMowerInteraction('离线 · 割草机已关机（DP113），断电离线属预期，不降级蓝牙');
        return;
      }
      state.logMowerInteraction('离线 ⚠ 割草机 Wi-Fi 掉线，主动降级连接蓝牙');
      unawaited(refreshLink(state, autoConnect: true, force: true));
    }
  }

  void _releaseLive() {
    _bindingGeneration++;
    _linkRefresh = null;
    _queue = Future<void>.value();
    _watchedState?.removeListener(_onStateChanged);
    _watchedState = null;
    _lastDeviceSnapshot = null;
    _appliedDpReads.clear();
    _lastOnline = null;
    _lastShutdown = false;
    unawaited(_reportSub?.cancel());
    _reportSub = null;
    for (final timer in _echoTimers) {
      timer.cancel();
    }
    _echoTimers.clear();
    _awaitingEcho.clear();
    _pendingCommands.clear();
    _lastCommandResult = null;
    _faultReadTimer?.cancel();
    _faultReadTimer = null;
    if (_freshFaultWaiter != null && !_freshFaultWaiter!.isCompleted) {
      _freshFaultWaiter!.complete(null);
    }
    _freshFaultWaiter = null;
    _commandFaultRead = null;
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
    operatingTimeHours = null;
    switchGo = false;
    mode = MowerMode.standby;
    lastCommandedMode = null;
    status = MowerStatus.standby;
    battery = 0;
    hasBatteryReport = false;
    faultBitmap = null;
    faultAlarm = null;
    charging = MowerChargingStatus.notCharging;
    _chargingReported = false;
    coverClosed = true;
    rainDetectEnable = false;
    rainDelayMinutes = 0;
    rainDelaySwitch = false;
    timeSyncEnable = false;
    timezoneIndex = MowerTimezone.fromDeviceOffset(
      DateTime.now().timeZoneOffset,
    );
    dstEnable = false;
    deviceTimeUtcSeconds = null;
    language = null;
    schedule = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
    scheduleRaw = null;
    scheduleRawSource = '';
    scheduleRawAt = null;
    scheduleSentRaw = null;
    scheduleSentAt = null;
    hasScheduleReport = false;
    scheduleCommandResult = null;
    _scheduleReadSequence = 0;
    bleLinked = false;
    wifiLinked = false;
    _lastAutoConnect = null;
    _autoConnecting = false;
    zones = <MowerZoneConfig>[
      for (var index = 1; index <= 5; index++)
        MowerZoneConfig(index: index, percent: 0, meters: 0),
    ];
  }

  /// 按涂鸦的分通道状态刷新两个图标；[autoConnect] 时蓝牙没连就在后台连一次（不弹框，
  /// 最多每 [autoReconnectEvery] 一次）。状态变了才记日志，免得每几秒刷一屏。
  ///
  /// [force]：不看节流（Wi-Fi 刚掉线时的主动降级）。Wi-Fi 从亮变灭也按 force 处理。
  Future<void> refreshLink(
    FlowerpotState state, {
    bool autoConnect = false,
    bool force = false,
  }) {
    final id = _deviceId;
    if (id == null) return Future<void>.value();
    final existing = _linkRefresh;
    if (existing != null) return existing;
    final generation = _bindingGeneration;
    late final Future<void> pending;
    pending =
        _refreshLink(
              state,
              id,
              generation,
              autoConnect: autoConnect,
              force: force,
            )
            .catchError((Object error) {
              if (!_isCurrent(id, generation)) return;
              state.logMowerInteraction('读取连接状态失败 ✗ 割草机：$error');
            })
            .whenComplete(() {
              if (identical(_linkRefresh, pending)) _linkRefresh = null;
            });
    _linkRefresh = pending;
    return pending;
  }

  Future<void> _refreshLink(
    FlowerpotState state,
    String id,
    int generation, {
    required bool autoConnect,
    required bool force,
  }) async {
    final wifiBefore = wifiLinked;
    _applyLink(state, await state.deviceLinkState(id), id, generation);
    if (!autoConnect ||
        bleLinked ||
        _autoConnecting ||
        !_isCurrent(id, generation)) {
      return;
    }
    // 已关机 = 断电了，蓝牙也连不上，别每几秒去连一次。
    if (state.isMowerShutdown(id)) return;
    final wifiDropped = wifiBefore && !wifiLinked;
    if (wifiDropped) {
      state.logMowerInteraction('离线 ⚠ 割草机 Wi-Fi 通道断开，主动降级连接蓝牙');
    }
    final now = DateTime.now();
    final last = _lastAutoConnect;
    if (!force &&
        !wifiDropped &&
        last != null &&
        now.difference(last) < autoReconnectEvery) {
      return;
    }
    _lastAutoConnect = now;
    _autoConnecting = true;
    state.logMowerInteraction('蓝牙 ⚠ 割草机蓝牙未连接，后台自动连接（不弹框）');
    try {
      await state.connectDeviceBle(id);
    } finally {
      if (_isCurrent(id, generation)) _autoConnecting = false;
    }
    if (!_isCurrent(id, generation)) return;
    _applyLink(state, await state.deviceLinkState(id), id, generation);
  }

  void _applyLink(
    FlowerpotState state,
    Map<String, Object?> link,
    String id,
    int generation,
  ) {
    if (!_isCurrent(id, generation)) return;
    final ble = link['ble'] == true;
    final wifi = link['wifi'] == true;
    if (ble == bleLinked && wifi == wifiLinked) return;
    bleLinked = ble;
    wifiLinked = wifi;
    final parts = <String>[
      for (final key in <String>[
        'bleManager',
        'bleChannel',
        'mqtt',
        'lan',
        'cloud',
        // SDK 自动切蓝牙的依据：-2 未连蓝牙；0 / 1 = 设备经蓝牙报 Wi-Fi 断了 → Auto 下发走蓝牙。
        'bleNodeFirst',
      ])
        if (link.containsKey(key)) '$key=${link[key]}',
    ];
    state.logMowerInteraction(
      '图标 ← 蓝牙${ble ? '亮' : '灭'}、Wi-Fi${wifi ? '亮' : '灭'}'
      '${parts.isEmpty ? '' : '（${parts.join(' ')}）'}',
    );
    notifyListeners();
  }

  /// 首页黄色提醒那一行：有故障时是 DP18 的文案，没有故障是安全提示。
  ///
  /// 按协议 V2.3 §4.3 的**位图**解（2026-09-23 产品最终口径：「按协议 V2.3 的来，0 表示正常就隐藏」）：
  /// 0 = 正常 → null（首页黄条隐藏）；有故障位取位序最低的那条文案。没报过（null）同样隐藏。
  /// （同日曾按「上报值 = 文案编号」改过一版，已撤回。）
  String? get faultMessage {
    final value = faultBitmap;
    return value == null ? null : MowerFault.firstMessage(value);
  }

  /// 左边三颗（自动/定点/回归）此刻能不能点——**不含**「当前模式置灰」那条（[isCurrentMode]
  /// 是单独判断，见页面）。点之前还要过盖子那道预检（[coverClosed]，在页面里弹窗）。
  ///
  /// 口径：
  /// - 2026-09-18：按下「停止」之后三颗不可点，「继续」后恢复；
  /// - 2026-09-23 更正：「DP3 不等于这颗按钮时就应该能正常点」。原来写成 `switchGo`，
  ///   待机态设备报的 DP2 也是 false，结果刚开机连「自动」都点不了、没法启动
  ///   （协议 §9.2：待机启动就是发 DP3=smart）。所以「停止」改按设备真的**暂停了**来认：
  ///   DP5 = paused（协议 §9.3：停止发 DP2=false → 设备报 DP5=paused）。
  ///
  /// 已关机（[shutdown]）时也不可点。
  bool get online =>
      _deviceId != null && (_watchedState?.isDeviceOnline(_deviceId!) ?? false);

  bool get commandsEnabled =>
      _deviceId != null && status != MowerStatus.paused && !shutdown;

  /// 待机没有可恢复的工作点，不能通过 DP2 启动新任务。
  /// 在桩等待充电（DP5=9 或 DP3=6）也置灰：机器小于 70% 电量发割草会被拒 54 并进入这个状态，
  /// 这时 DP2=true 只是幂等回弹、DP2=false 会被拒 49（V3.0 §2.1），停止/继续都没有效果。
  bool get switchEnabled =>
      _deviceId != null &&
      !shutdown &&
      !waitingCharge &&
      (switchGo || status != MowerStatus.standby);

  /// 设备报的是「在桩等待充电」：DP5=wait_charge（9）或 DP3=wait_charge（6），两套枚举任一即算。
  bool get waitingCharge =>
      status == MowerStatus.waitCharge || mode == MowerMode.waitCharge;

  bool _canWrite(FlowerpotState state) {
    final id = _deviceId;
    if (id != null && state.isDeviceOnline(id) && !shutdown) return true;
    _failures.add(shutdown ? '割草机已关机，请开机后再操作' : '设备已离线');
    return false;
  }

  /// 已关机：DP113 报过 true（非在桩关机）、还没再开机。判定只有一份，在状态层
  /// （`FlowerpotState.isMowerShutdown`，设备列表也用它）；这里只是转一下，没绑设备时为 false。
  bool get shutdown {
    final id = _deviceId;
    return id != null && (_watchedState?.isMowerShutdown(id) ?? false);
  }

  /// 这个模式是不是当前 DP3 的值——是就置灰，不给重复下发。
  bool isCurrentMode(MowerMode target) => mode == target;

  // ── 下发 ────────────────────────────────────────────────

  /// 工作时长（DP119）：下发成功后才允许页面继续启动，不改变每次弹窗的默认值。
  Future<bool> setOperatingTime(FlowerpotState state, int hours) {
    if (!_canWrite(state)) return Future<bool>.value(false);
    if (hours < 1 || hours > 24) {
      throw RangeError.range(hours, 1, 24, 'hours');
    }
    final identifier = MowerDp.identifiers[MowerDp.operatingTime];
    state.logMowerInteraction('下发 → 割草机 DP119 $identifier=$hours（割草时长）');
    return _publish(state, <int, Object>{
      MowerDp.operatingTime: hours,
    }, label: 'DP119 $identifier=$hours');
  }

  /// 工作开关（DP2）。[on]=true 启动/继续，false 停止/暂停。
  void setSwitch(FlowerpotState state, {required bool on}) {
    if (!_canWrite(state) ||
        waitingCharge ||
        (on && status == MowerStatus.standby)) {
      return;
    }
    _deliver(state, MowerDp.switchGo, on, action: on ? '继续/启动' : '停止');
    switchGo = on;
    // DP3 / DP5 以设备上报为准（启动后设备按最后一次 DP3 跑，会自己报上来）。
    notifyListeners();
  }

  /// 工作模式（DP3）。只允许 [MowerMode.sendable] 的四个。
  void setMode(FlowerpotState state, MowerMode target) {
    if (!_canWrite(state)) return;
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
    if (!_canWrite(state)) return;
    if (schedulePending) {
      _failures.add('正在等待设备返回割草计划，请稍后再操作');
      return;
    }
    if (week.length != 7) {
      _failures.add('割草计划需要包含完整七天，未下发');
      return;
    }
    for (final day in week) {
      if (day.overlapMessage != null) {
        _failures.add('割草时段不能重叠，未下发');
        return;
      }
      for (final slot in [day.slotOne, day.slotTwo]) {
        if (slot == null) continue;
        if (slot.startMinutes < 0 ||
            slot.startMinutes > 1440 ||
            slot.endMinutes < 0 ||
            slot.endMinutes > 1440 ||
            (slot.enabled && !slot.validForDevice)) {
          _failures.add('割草时段需在当天范围内且超过10分钟，未下发');
          return;
        }
      }
    }
    final data = MowerScheduleCodec.encodeByDay(week);
    _deliverRaw(
      state,
      MowerDp.mowSchedule,
      data,
      hex: MowerScheduleCodec.toHexGroups(data),
      action: '割草计划（全量替换，8 组 × 11 字节）',
    );
    scheduleSentRaw = Uint8List.fromList(data);
    scheduleSentAt = DateTime.now();
    state.logMowerInteraction('待确认 · 割草计划只在收到有效DP101后更新显示');
    notifyListeners();
  }

  /// 恢复默认割草计划（DP110 = true，V2.3）。**本地不改计划**：设备写入默认计划后会自己上报 DP101，
  /// 界面等那条上报再刷（执行成功的依据就是它）；设备随后把 DP110 回写 false，这条回写正好消掉回显等待。
  void resetSchedule(FlowerpotState state) {
    if (!_canWrite(state)) return;
    _deliver(
      state,
      MowerDp.scheduleReset,
      true,
      action: '恢复默认割草计划，等设备回报 DP${MowerDp.mowSchedule}',
    );
  }

  /// 区域配置（DP103，raw 25 字节）。**全量替换**，5 个区一起发。
  void setZones(FlowerpotState state, List<MowerZoneConfig> next) {
    if (!_canWrite(state)) return;
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
    if (!_canWrite(state)) return;
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
    if (!_canWrite(state)) return;
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
      final seconds = (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000)
          .toString();
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
    if (!_canWrite(state)) return;
    _deliver(
      state,
      MowerDp.language,
      target.code,
      action: '机器语言 ${target.label}',
    );
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
  Future<void> _syncFromDevice(
    FlowerpotState state,
    Set<int>? changed, {
    Map<int, Object?>? reported,
  }) async {
    final id = _deviceId;
    if (id == null) return;
    final generation = _bindingGeneration;
    try {
      await _readSnapshot(state, changed, id, generation, reported: reported);
    } catch (error) {
      if (!_isCurrent(id, generation)) return;
      state.logMowerInteraction('读取设备信息失败 ✗ 割草机：$error');
      if (changed == null) _failures.add('设备信息读取失败，请返回后重试');
    }
  }

  Future<void> _readSnapshot(
    FlowerpotState state,
    Set<int>? changed,
    String id,
    int generation, {
    Map<int, Object?>? reported,
  }) async {
    final readsSchedule =
        changed == null ||
        changed.isEmpty ||
        changed.contains(MowerDp.mowSchedule);
    final scheduleRead = readsSchedule ? ++_scheduleReadSequence : null;
    final read = ++_snapshotSequence;
    final completeReport =
        changed != null &&
        changed.isNotEmpty &&
        reported != null &&
        changed.every(reported.containsKey);
    final snapshot = completeReport ? null : await state.mowerDps(id);
    if ((snapshot == null && reported == null) || !_isCurrent(id, generation)) {
      return;
    }
    final dps = <int, Object?>{...?snapshot, ...?reported};
    dps.removeWhere((dp, _) => (_appliedDpReads[dp] ?? 0) > read);
    for (final dp in dps.keys) {
      if (changed == null || changed.isEmpty || changed.contains(dp)) {
        _appliedDpReads[dp] = read;
      }
    }
    if (readsSchedule && scheduleRead != _scheduleReadSequence) {
      dps.remove(MowerDp.mowSchedule);
    }
    // 这一次有没有把 DP101 刷进来：有就逐字节解析打进日志（下面三个分支口径各不相同）。
    final scheduleTouched = changed == null
        ? dps.containsKey(MowerDp.mowSchedule)
        : changed.isEmpty
        ? dps.containsKey(MowerDp.mowSchedule) &&
              scheduleRead == _scheduleReadSequence
        : changed.contains(MowerDp.mowSchedule);
    if (changed == null) {
      _applyReported(dps);
      state.logMowerInteraction(
        '读取 ← 割草机设备快照 ${dps.length} 个 DP：'
        '${dps.keys.toList()..sort()}',
      );
    } else if (changed.isEmpty) {
      // 整包快照（`onDevInfoUpdate`，报文里没有逐条 DP）：全部刷一遍，但**跳过还在等回显的**——
      // DP101不乐观显示，始终读取设备返回；其它参数仍跳过等待中的旧快照。
      _applyReported(
        dps,
        only: dps.keys.where(
          (dp) => dp == MowerDp.mowSchedule || !_awaitingEcho.containsKey(dp),
        ),
      );
    } else {
      _applyReported(dps, only: changed);
      for (final dp in changed) {
        if (dp != MowerDp.mowSchedule ||
            TuyaRaw.bytes(dps[dp])?.length == MowerScheduleCodec.bytes) {
          _awaitingEcho.remove(dp);
        }
        final identifier = MowerDp.identifiers[dp] ?? 'dp$dp';
        final note = dp == MowerDp.fault
            ? ' → 黄条「${faultMessage ?? '无对应文案'}」'
            : '';
        state.logMowerInteraction('上报 ← 割草机 DP$dp $identifier=${dps[dp]}$note');
      }
    }
    if (changed == null && dps.containsKey(MowerDp.commandResults)) {
      _lastCommandResult = MowerCommandResult.parse(
        dps[MowerDp.commandResults],
      );
    } else if (changed != null && changed.contains(MowerDp.commandResults)) {
      _acceptCommandResult(
        dps[MowerDp.commandResults],
        generation,
        freshAlarm: changed.contains(MowerDp.faultAlarm)
            ? MowerFaultAlarm.parse(reported?[MowerDp.faultAlarm])
            : null,
      );
    }
    if (changed != null && changed.contains(MowerDp.faultAlarm)) {
      final fresh = MowerFaultAlarm.parse(reported?[MowerDp.faultAlarm]);
      if (fresh != null &&
          _freshFaultWaiter != null &&
          !_freshFaultWaiter!.isCompleted) {
        _freshFaultWaiter!.complete(fresh);
        _faultReadTimer?.cancel();
      }
    }
    // DP116 ota_status（协议 V2.3 §7.2，只上报）：设备拒绝 / 升级失败时说一句。
    // 只看实时上报（changed 里有它），刚进页面读快照时那条旧值不弹。
    if (changed != null && changed.contains(MowerDp.otaStatus)) {
      final code = '${dps[MowerDp.otaStatus] ?? ''}'.trim();
      final message = switch (code) {
        '7' => '割草机不在待机，拒绝了固件升级，请先停到待机再升级',
        '20' => '割草机固件升级失败',
        _ => null,
      };
      if (message != null && !_failures.isClosed) _failures.add(message);
    }
    if (scheduleTouched && dps.containsKey(MowerDp.mowSchedule)) {
      final bytes = TuyaRaw.bytes(dps[MowerDp.mowSchedule]);
      if (bytes != null) {
        _rememberSchedule(
          state,
          Uint8List.fromList(bytes),
          changed != null && changed.contains(MowerDp.mowSchedule)
              ? '设备上报'
              : '设备快照',
        );
      } else {
        state.logMowerInteraction(
          '解析 ✗ 割草机 DP${MowerDp.mowSchedule} 认不出的值：${dps[MowerDp.mowSchedule]}',
        );
      }
    }
    notifyListeners();
  }

  void _acceptCommandResult(
    Object? raw,
    int generation, {
    MowerFaultAlarm? freshAlarm,
  }) {
    final result = MowerCommandResult.parse(raw);
    if (result == null || result.seq == _lastCommandResult?.seq) return;
    _lastCommandResult = result;
    final pending = _pendingCommands[result.dp];
    if (pending == null ||
        result.seq == pending.previousSeq ||
        (result.dp != MowerDp.mowSchedule &&
            result.value != null &&
            result.value != pending.value)) {
      return;
    }
    _pendingCommands.remove(result.dp);
    if (result.dp == MowerDp.mowSchedule) {
      scheduleCommandResult = result;
      if (result.rejectionMessage != null) {
        _awaitingEcho.remove(MowerDp.mowSchedule);
        _failures.add('割草计划未生效：${result.rejectionMessage}');
      }
      return;
    }
    if (result.code == 26) {
      _faultReadTimer?.cancel();
      if (_freshFaultWaiter != null && !_freshFaultWaiter!.isCompleted) {
        _freshFaultWaiter!.complete(null);
      }
      if (freshAlarm != null) {
        _commandFaultRead = Future.value(freshAlarm);
      } else {
        // 协议允许等下一条变化即报，不拿快照旧值解释本次拒绝。
        final waiter = Completer<MowerFaultAlarm?>();
        _freshFaultWaiter = waiter;
        _commandFaultRead = waiter.future;
        _faultReadTimer = Timer(const Duration(seconds: 3), () {
          if (!waiter.isCompleted) waiter.complete(null);
        });
      }
    }
    _commandResults.add((result: result, generation: generation));
  }

  Future<String> commandFaultMessage(MowerCommandResult result) async {
    if (result.code != 26) return result.rejectionMessage ?? '';
    final fresh = await _commandFaultRead;
    return fresh?.recoveryMessage ?? '故障尚未排除，暂未收到最新故障详情，请检查设备后重试。';
  }

  /// 在真正发送前登记，兼容设备回执早于 SDK 完成回调。
  _PendingMowerCommand? _watchCommand(Map<int, Object> dps) {
    final dp = dps.keys.single;
    if (dp != MowerDp.switchGo &&
        dp != MowerDp.mode &&
        dp != MowerDp.mowSchedule) {
      return null;
    }
    final raw = dps[dp];
    final value = dp == MowerDp.mowSchedule
        ? 0
        : dp == MowerDp.switchGo
        ? (raw == true ? 1 : 0)
        : MowerDp.enumOf(MowerMode.values, (item) => item.code, raw)?.value;
    if (value == null) return null;
    // 一次只跟踪最后实际发送的控制/计划命令；DP101 raw不使用val匹配。
    _pendingCommands.clear();
    final pending = _PendingMowerCommand(value, _lastCommandResult?.seq);
    _pendingCommands[dp] = pending;
    if (dp == MowerDp.mowSchedule) scheduleCommandResult = null;
    return pending;
  }

  void _forgetCommand(Map<int, Object> dps, _PendingMowerCommand? pending) {
    if (pending == null) return;
    final dp = dps.keys.single;
    if (identical(_pendingCommands[dp], pending)) _pendingCommands.remove(dp);
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
        case MowerDp.operatingTime:
          if (value is num &&
              (!value.isFinite || value != value.truncateToDouble())) {
            break;
          }
          final hours = _asInt(value);
          if (hours != null && hours >= 1 && hours <= 24) {
            operatingTimeHours = hours;
          }
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
          final level = _asInt(value);
          if (level != null && level >= 0 && level <= 100) {
            battery = level;
            hasBatteryReport = true;
          }
        case MowerDp.fault:
          faultBitmap = MowerFault.parseBitmap(value) ?? faultBitmap;
        case MowerDp.faultAlarm:
          faultAlarm = MowerFaultAlarm.parse(value) ?? faultAlarm;
        case MowerDp.chargingStatus:
          final reported = MowerDp.enumOf(
            MowerChargingStatus.values,
            (item) => item.code,
            value,
          );
          if (reported != null) {
            charging = reported;
            _chargingReported = true;
          }
        case MowerDp.coverStatus:
          coverClosed = _asBool(value) ?? coverClosed;
        case MowerDp.mowSchedule:
          final scheduleBytes = TuyaRaw.bytes(value);
          if (scheduleBytes != null &&
              scheduleBytes.length == MowerScheduleCodec.bytes) {
            schedule = MowerScheduleCodec.decode(
              Uint8List.fromList(scheduleBytes),
            );
            hasScheduleReport = true;
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
              MowerDp.enumOf(
                MowerLanguage.values,
                (item) => item.code,
                value,
              ) ??
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
    _publish(state, <int, Object>{
      dp: value,
    }, label: 'DP$dp $identifier=$value');
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
      ..logMowerInteraction('下发 → 割草机 DP$dp $identifier=${data.length}B$suffix')
      ..logMowerInteraction('　　raw hex: $hex')
      // 涂鸦 raw 型 DP 在设备侧就是这串 base64，联调时要拿它和平台日志对
      ..logMowerInteraction('　　base64: ${base64Encode(data)}');
    // App 侧交给 SDK 的是**十六进制串**，SDK 的 DevUtil.encodeRaw 自己转成 base64
    // （与花盆纪念日 154 等 raw 下发同一口径，见 TuyaRaw）。
    _publish(state, <int, Object>{
      dp: TuyaRaw.hex(data),
    }, label: 'DP$dp $identifier=${data.length}B');
  }

  /// 真机下发：排进队列按顺序发；失败就把界面画回设备快照并报给页面，成功就等回显。
  Future<bool> _publish(
    FlowerpotState state,
    Map<int, Object> dps, {
    required String label,
  }) {
    final id = _deviceId;
    if (id == null) {
      state.logMowerInteraction('下发跳过 ⚠ 割草机 $label：还没绑定设备');
      return Future<bool>.value(false);
    }
    final generation = _bindingGeneration;
    final seq = ++_sendSeq;
    for (final dp in dps.keys) {
      _awaitingEcho[dp] = seq;
    }
    _PendingMowerCommand? command;
    final pending = _queue
        .then<bool>((_) async {
          if (!_isCurrent(id, generation)) return false;
          // 排队期间可能收到 DP113；SDK 的 Wi-Fi 缓存仍在线也不能继续下发。
          if (state.isMowerShutdown(id)) {
            for (final dp in dps.keys) {
              if (_awaitingEcho[dp] == seq) _awaitingEcho.remove(dp);
            }
            state.logMowerInteraction('下发被拦 ✗ 割草机 $label：设备已关机');
            _failures.add('割草机已关机，请开机后再操作');
            await _revertToDevice(state, id, dps.keys, generation);
            return false;
          }
          command = _watchCommand(dps);
          final result = await state.publishMowerDps(id, dps);
          if (!_isCurrent(id, generation)) return false;
          if (!result.success) {
            _forgetCommand(dps, command);
            for (final dp in dps.keys) {
              if (_awaitingEcho[dp] == seq) _awaitingEcho.remove(dp);
            }
            state.logMowerInteraction('下发失败 ✗ 割草机 $label：${result.message}');
            if (!_failures.isClosed) {
              _failures.add(
                state.isMowerShutdown(id)
                    ? '割草机已关机，请开机后再操作'
                    : result.code == 'device_offline'
                    ? result.message
                    : '指令没有发出去：${result.message}',
              );
            }
            await _revertToDevice(state, id, dps.keys, generation);
            return false;
          }
          _armEchoCheck(
            state,
            id,
            dps.keys.toList(growable: false),
            seq,
            generation,
          );
          return true;
        })
        .catchError((Object error) {
          if (!_isCurrent(id, generation)) return false;
          _forgetCommand(dps, command);
          state.logMowerInteraction('下发失败 ✗ 割草机 $label：$error');
          if (!_failures.isClosed) _failures.add('设备操作失败，请稍后重试');
          return false;
        });
    _queue = pending.then<void>((_) {});
    return pending.whenComplete(() {
      if (_isCurrent(id, generation) && dps.containsKey(MowerDp.mowSchedule)) {
        notifyListeners();
      }
    });
  }

  /// 下发成功后 [echoTimeout] 内这几条 DP 还没有上报，就按设备快照画回去（V2.2 §1 超时回弹）。
  void _armEchoCheck(
    FlowerpotState state,
    String id,
    List<int> dps,
    int seq,
    int generation,
  ) {
    late final Timer timer;
    timer = Timer(echoTimeout, () {
      _echoTimers.remove(timer);
      if (!_isCurrent(id, generation)) return;
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
      notifyListeners();
      unawaited(_revertToDevice(state, id, missing, generation));
    });
    _echoTimers.add(timer);
  }

  /// 把这几条 DP 画回设备快照里的值。快照里没有的（设备从没报过）就保持现状。
  Future<void> _revertToDevice(
    FlowerpotState state,
    String id,
    Iterable<int> dps,
    int generation,
  ) async {
    try {
      final readsSchedule = dps.contains(MowerDp.mowSchedule);
      final sequence = readsSchedule ? ++_scheduleReadSequence : null;
      final snapshot = await state.mowerDps(id);
      if (snapshot == null || !_isCurrent(id, generation)) return;
      final targets = dps.where(
        (dp) => dp != MowerDp.mowSchedule || sequence == _scheduleReadSequence,
      );
      _applyReported(snapshot, only: targets);
      if (targets.contains(MowerDp.mowSchedule)) {
        final bytes = TuyaRaw.bytes(snapshot[MowerDp.mowSchedule]);
        if (bytes != null) {
          _rememberSchedule(state, Uint8List.fromList(bytes), '设备快照');
        }
      }
      notifyListeners();
    } catch (error) {
      if (!_isCurrent(id, generation)) return;
      state.logMowerInteraction('回弹读取失败 ✗ 割草机：$error');
    }
  }
}

class _PendingMowerCommand {
  _PendingMowerCommand(this.value, this.previousSeq);

  final int value;
  final int? previousSeq;
}
