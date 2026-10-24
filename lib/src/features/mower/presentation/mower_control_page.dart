import 'dart:async';

import 'package:flutter/material.dart';

import '../../devices/presentation/device_online_guard.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../mower_ui.dart';
import '../mower_device.dart';
import '../mower_dp.dart';
import '../mower_command_result.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_status_card.dart';
import 'widgets/mower_start_dialog.dart';

/// 割草机首页（`docs/UI/v2/割草机/割草机-控制.png` 及其三张状态图）。
///
/// ## 这一页的 DP（2026-09-18 接线）
///
/// | 元素 | DP |
/// | --- | --- |
/// | 电量环 | DP13 battery_percentage（充电态看 DP117） |
/// | 状态胶囊 | DP5 status；设置过工作时间时后面跟本机倒计时（[MowerDevice.workEndsAt]） |
/// | 黄色提醒 | DP18 fault（位图 → 文案，见 [MowerFault.messages]）；没有故障时显示实时提醒：DP111 抬起位 / DP120 事件码 44·144 → 已抬起 / 已落地，DP5=12 → 正在脱困（[MowerDevice.liveNotice]） |
/// | 今日计划 | DP101 mow_schedule 解析出来的今天那一组（**不存数据库**） |
/// | 停止 / 继续 | DP2 switch_go |
/// | 自动 / 定点 / 回归 | DP3 mode = smart / spot / goto_charge |
/// | 自动/定点新任务的割草时间 | DP119 operating_time（整数小时）；继续不重写 |
///
/// ## 四颗按钮的规矩（2026-09-18 用户口径，逐条）
///
/// 1. **启动/停止优先级最高**：按下「停止」、设备报 DP5=paused 时，左边三颗不能点，「继续」后恢复；
///    其余时候（包括刚开机的待机，DP2=false）DP3 不等于这颗就能点（2026-09-23 更正）；
/// 2. 按钮文案按 DP2 值：true 显示「停止」（点了下发 false），false 显示「继续」（点了下发 true）；
/// 3. 左边三颗**不能重复点**：`DP3 == 这颗` 就置灰；
/// 4. 待机时「继续」置灰；停止/故障后恢复只发 DP2=true，不重写 DP119；
/// 5. 点左边三颗前先看 **DP118 盖子**：没合盖就弹窗、**不下发**；
/// 6. 设备报在桩等待充电/雨停（DP5=9/10 或 DP3=6/7）时「停止/继续」置灰（2026-10-22，V3.0 拒绝码 54/35/49）。
///
/// 2026-09-23 起只接真机：只读 DP（盖子/故障/电量/充电）全部以设备上报为准，
/// 原来长按电量环的模拟上报面板已删。标题是设备在涂鸦里的名字。
///
/// ## DP18 设备告警弹窗（2026-09-28 产品）
///
/// 这一页捕捉涂鸦上报的 DP18 故障位图：出现**新的**故障位就弹「设备告警」，内容是每个故障位对应的文案
/// （[MowerFault.messages]，一行一条），按钮「我知道了」。
/// - 同一组故障只弹一次：设备每 60 秒会重报同值（协议 V2.5 §4 周期兜底），不能每次都弹；
/// - 故障位清掉之后再出现，算新故障，再弹；弹窗开着时又来了新故障，关掉后接着弹；
/// - 只在用户看着这一页时弹：外壳是 IndexedStack，切到「计划 / 设置」这一页还活着（[active] 为 false），
///   上面压着二级页时也不弹；回到这一页后按当前故障补弹。
class MowerControlPage extends StatefulWidget {
  const MowerControlPage({
    super.key,
    this.active = true,
    this.now = DateTime.now,
  });

  final DateTime Function() now;

  /// 这一栏此刻是不是用户正看着的那一栏（外壳切走了页面还活着）。
  final bool active;

  @override
  State<MowerControlPage> createState() => _MowerControlPageState();
}

class _MowerControlPageState extends State<MowerControlPage> {
  MowerDevice get _device => MowerDevice.instance;

  /// 每 3 秒按涂鸦的分通道状态刷新两个图标；蓝牙掉了顺带后台重连（节流见 MowerDevice）。
  Timer? _linkTimer;

  /// 设置割草时间期间，被点击的按钮显示公共居中 loading。
  String? _checking;
  bool _operationInProgress = false;

  /// 已经弹过、而且还在报的故障位（DP18）。清掉的位会从这里拿掉，再出现就重新弹。
  final Set<int> _faultShown = <int>{};
  bool _faultDialogOpen = false;
  bool _faultCheckScheduled = false;
  StreamSubscription<({MowerCommandResult result, int generation})>?
  _commandSub;
  final List<({MowerCommandResult result, int generation})> _commandNotices =
      [];

  @override
  void dispose() {
    _linkTimer?.cancel();
    unawaited(_commandSub?.cancel());
    _device.removeListener(_scheduleFaultCheck);
    super.dispose();
  }

  @override
  void didUpdateWidget(MowerControlPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切回这一栏：按当前故障补弹
    if (widget.active && !oldWidget.active) _scheduleFaultCheck();
  }

  /// 设备一有变化（包括 DP18 上报）就在这一帧画完后看一眼故障位——不在通知回调里直接弹，
  /// 免得撞上正在构建的页面。
  void _scheduleFaultCheck() {
    if (_faultCheckScheduled) return;
    _faultCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _faultCheckScheduled = false;
      _checkFault();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _checkFault() {
    if (!mounted ||
        !widget.active ||
        _faultDialogOpen ||
        _operationInProgress) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _commandNotices.removeWhere(
      (event) => event.generation != _device.bindingGeneration,
    );
    if (_commandNotices.isNotEmpty) {
      final event = _commandNotices.removeAt(0);
      unawaited(_showCommandNotice(event.result));
      return;
    }
    // 已关机（DP113）：关机前留下的故障位不弹，开机后按新上报再判。
    if (_device.shutdown) return;
    final bitmap = _device.faultBitmap;
    if (bitmap == null) return;
    final active = MowerFault.activeBits(bitmap).toSet();
    _faultShown.retainAll(active);
    if (active.difference(_faultShown).isEmpty) return;
    unawaited(_showFaultDialog(bitmap, active));
  }

  Future<void> _showCommandNotice(MowerCommandResult result) async {
    _faultDialogOpen = true;
    try {
      final generation = _device.bindingGeneration;
      final message = await _device.commandFaultMessage(result);
      if (!mounted ||
          !widget.active ||
          generation != _device.bindingGeneration ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      await showAppNoticeDialog(
        context,
        title: '设备异常',
        message: message,
        confirmLabel: '我已处理',
        icon: Icons.warning_amber_rounded,
        tone: AppDialogTone.danger,
        barrierDismissible: false,
      );
    } finally {
      _faultDialogOpen = false;
      if (mounted) _scheduleFaultCheck();
    }
  }

  Future<void> _showFaultDialog(int bitmap, Set<int> active) async {
    _faultDialogOpen = true;
    _faultShown.addAll(active);
    final bits = active.toList()..sort();
    final lines = <String>[
      for (final bit in bits) MowerFault.messages[bit] ?? '未知故障（第 $bit 位）',
    ];
    FlowerpotScope.of(context).logMowerInteraction(
      '弹窗 → 设备告警 DP${MowerDp.fault}=$bitmap'
      '（${MowerFault.activeIdentifiers(bitmap).join('、')}）',
    );
    await showAppNoticeDialog(
      context,
      title: '设备告警',
      message: lines.join('\n'),
      icon: Icons.warning_amber_rounded,
      tone: AppDialogTone.danger,
      barrierDismissible: false,
    );
    _faultDialogOpen = false;
    // 弹窗开着时又来了新故障 → 接着弹
    if (mounted) _scheduleFaultCheck();
  }

  @override
  void initState() {
    super.initState();
    _device.addListener(_scheduleFaultCheck);
    _commandSub = _device.commandResults.listen((event) {
      if (!mounted ||
          !widget.active ||
          event.generation != _device.bindingGeneration ||
          event.result.rejectionMessage == null) {
        return;
      }
      _commandNotices.add(event);
      _scheduleFaultCheck();
    });
    _linkTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      unawaited(
        _device.refreshLink(FlowerpotScope.of(context), autoConnect: true),
      );
    });
    // 进页面把这一页读到的 DP 摊在日志里（对齐花盆的 logSettingsSnapshot 口径：
    // 「刚进来就要知道读了哪些 DPID、值是什么」）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = FlowerpotScope.of(context);
      state
        ..logPageEntry('割草机-控制')
        ..logMowerInteraction(
          '读取 ← 割草机-控制 '
          'DP${MowerDp.switchGo}=${_device.switchGo}，'
          'DP${MowerDp.mode}=${_device.mode.code}，'
          'DP${MowerDp.status}=${_device.status.code}，'
          'DP${MowerDp.battery}=${_device.battery}，'
          'DP${MowerDp.fault}=${_device.faultBitmap ?? '未上报'}'
          '（${_device.faultMessage ?? '无故障文案'}），'
          'DP${MowerDp.chargingStatus}=${_device.charging.code}，'
          'DP${MowerDp.coverStatus}=${_device.coverClosed}',
        );
      // 进页面时已经有故障，也告诉用户一次
      _scheduleFaultCheck();
    });
  }

  /// 电量环的视觉态：充电动效看DP117及电量，其余按DP13分档；文字单独读取DP117。
  MowerPowerState get _tone {
    if (!_device.hasBatteryReport) return MowerPowerState.idle;
    if (_device.battery < 100 &&
        _device.charging == MowerChargingStatus.charging) {
      return MowerPowerState.charging;
    }
    if (_device.battery <= MowerPowerState.lowPercent) {
      return MowerPowerState.batteryLow;
    }
    if (_device.battery <= MowerPowerState.warningPercent) {
      return MowerPowerState.batteryWarning;
    }
    return MowerPowerState.idle;
  }

  /// 按钮点击统一入口：操作期间不重入，异常时恢复按钮并提示。
  /// [button] 是被点的那颗。
  Future<void> _guarded(String button, Future<void> Function() action) async {
    if (_operationInProgress || _device.shutdown) return;
    final id = _device.deviceId;
    if (id == null || !ensureDeviceOnline(context, id)) return;
    _operationInProgress = true;
    final state = FlowerpotScope.of(context);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      state.logMowerInteraction('控制失败 ✗ 割草机 $button：$error');
      if (_checking != null) setState(() => _checking = null);
      await showAppNoticeDialog(
        context,
        title: '提示',
        message: '设备操作失败，请稍后重试',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      _operationInProgress = false;
      if (mounted) {
        if (_checking != null) setState(() => _checking = null);
        _scheduleFaultCheck();
      }
    }
  }

  Future<void> _toggleSwitch() => _guarded('switch', () async {
    final state = FlowerpotScope.of(context);
    if (_device.switchGo) {
      _device.setSwitch(state, on: false);
    } else {
      if (!_device.switchEnabled) return;
      final id = _device.deviceId;
      final generation = _device.bindingGeneration;
      final confirmed = await showMowerSafetyDialog(context);
      if (!mounted ||
          !confirmed ||
          !widget.active ||
          _device.deviceId != id ||
          _device.bindingGeneration != generation ||
          ModalRoute.of(context)?.isCurrent == false ||
          !_device.switchEnabled) {
        return;
      }
      // 恢复原任务，不覆盖设备已有的 DP119 时长。
      _device.setSwitch(state, on: true);
    }
  });

  Future<void> _sendMode(MowerMode target) => _guarded(target.name, () async {
    if (target == MowerMode.gotoCharge) {
      await _sendModeChecked(target);
    } else {
      await _startWithTime(
        target.name,
        () => _device.setMode(FlowerpotScope.of(context), target),
        checkCover: true,
      );
    }
  });

  Future<void> _startWithTime(
    String button,
    VoidCallback start, {
    bool checkCover = false,
  }) async {
    final state = FlowerpotScope.of(context);
    final id = _device.deviceId;
    final generation = _device.bindingGeneration;
    bool current() =>
        mounted &&
        widget.active &&
        _device.deviceId == id &&
        _device.bindingGeneration == generation &&
        ModalRoute.of(context)?.isCurrent != false;
    if (id == null) return;
    final confirmed = await showMowerSafetyDialog(context);
    if (!mounted || !confirmed || !current()) return;
    final maxHours = mowerStartMaxHours(widget.now());
    if (maxHours == 0) {
      await _showTimeUnavailable();
      return;
    }
    final hours = await showMowerDurationDialog(context, maxHours);
    if (!mounted || hours == null || !current()) return;
    if (!await _validStartHours(hours) || !mounted || !current()) return;
    if (checkCover && !_device.coverClosed) {
      await _showCoverNotice();
      return;
    }
    if ((checkCover && !_device.commandsEnabled) || _device.shutdown) return;
    setState(() => _checking = button);
    final sent = await _device.setOperatingTime(state, hours);
    if (!sent || !current() || _device.shutdown) return;
    if (!await _validStartHours(hours) || !mounted || !current()) return;
    if (checkCover && (!_device.coverClosed || !_device.commandsEnabled)) {
      if (!_device.coverClosed) await _showCoverNotice();
      return;
    }
    start();
  }

  Future<void> _showTimeUnavailable() => showAppNoticeDialog(
    context,
    title: '暂时无法启动',
    message: mowerStartUnavailableMessage(widget.now()),
    icon: Icons.schedule_rounded,
  );

  Future<bool> _validStartHours(int hours) async {
    final maxHours = mowerStartMaxHours(widget.now());
    if (mowerStartHoursValid(widget.now(), hours)) return true;
    if (hours <= 0) {
      await showAppNoticeDialog(
        context,
        title: '请重新设置割草时间',
        message: '割草时长必须大于0小时，请重新设置。',
        icon: Icons.schedule_rounded,
      );
      return false;
    }
    if (maxHours == 0) {
      await _showTimeUnavailable();
    } else {
      await showAppNoticeDialog(
        context,
        title: '请重新设置割草时间',
        message: '当前距离今天18:00最多可割草 $maxHours 小时，请重新选择时长。',
        icon: Icons.schedule_rounded,
      );
    }
    return false;
  }

  Future<void> _showCoverNotice() => showAppNoticeDialog(
    context,
    title: '盖子未合上',
    message: '请先合上盖子再启动割草机。\n（DP${MowerDp.coverStatus} cover_status = false）',
    icon: Icons.info_outline_rounded,
  );

  Future<void> _sendModeChecked(MowerMode target) async {
    final state = FlowerpotScope.of(context);
    if (!_device.coverClosed) {
      state.logMowerInteraction(
        '下发被拦 ✗ 割草机 DP${MowerDp.mode}=${target.code}：'
        'DP${MowerDp.coverStatus} cover_status=false（盖子未合）',
      );
      await _showCoverNotice();
      return;
    }
    _device.setMode(state, target);
  }

  String _deviceName(BuildContext context) {
    final id = _device.deviceId;
    if (id == null) return '';
    return FlowerpotScope.of(context).deviceById(id)?.name ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _device,
      builder: (context, _) => AppPageScaffold(
        appBar: AppPageHeader(
          // 设备在涂鸦里的名字；还没读到就空着，不再画稿子上的 YSmower-01。
          title: _deviceName(context),
          leading: const AppBackButton(),
        ),
        // 按 Figma「割草机-控制」#784:3844 重排（2026-09-23 产品：「整体适配，不要出现过多的白色空白区域」）：
        // 按钮面板贴底（离底部导航 14），今日计划、黄色提醒按稿子的间距（8 / 8 / 4）紧跟在上面；
        // **多出来的高度只给最上面的电量环**——环按剩余空间等比缩放撑满（宽屏放大、矮屏缩小）。
        // 之前是把余量平分到各块之间，结果中间拉出两段空白。
        // 太矮（连缩到 80% 都放不下）才退回可滚动的按稿子尺寸排。
        body: DeviceOnlineBody(
          deviceId: MowerDevice.instance.deviceId,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // DP18 = 0（正常）或没报过：整条隐藏（协议 V2.3 位图口径，2026-09-23 产品）。
              // 已关机（DP113）时这一条换成关机提示，顶掉故障文案。
              // 没有故障时显示实时提醒（设备已抬起 / 已落地、正在脱困，2026-10-22）；
              // 故障照旧优先，抬起超时报的 DP18 抬起故障按原规则显示并弹框。
              final notice = _device.shutdown
                  ? _shutdownNotice
                  : _device.faultMessage ?? _device.liveNotice;
              final lower = <Widget>[
                if (notice != null) ...<Widget>[
                  _NoticeBar(fault: notice),
                  const SizedBox(height: 8),
                ],
                _TodayPlanCard(schedule: _device.schedule),
                const SizedBox(height: 8),
                _ActionPanel(
                  device: _device,
                  checking: _checking,
                  onMode: (mode) => unawaited(_sendMode(mode)),
                  onToggleSwitch: () => unawaited(_toggleSwitch()),
                ),
              ];
              final card = SizedBox(
                width: _cardWidth,
                child: MowerStatusCard(
                  tone: _tone,
                  percent: _device.hasBatteryReport ? _device.battery : null,
                  chargingLabel: _device.chargingLabel,
                  statusLabel: _device.shutdown ? '已关机' : _device.status.label,
                  wifiLinked: _device.wifiLinked,
                  bleLinked: _device.bleLinked,
                  workEndsAt: _device.workEndsAt,
                  now: widget.now,
                ),
              );
              final fits =
                  constraints.hasBoundedHeight &&
                  constraints.maxHeight >= _minFittedHeight;
              if (!fits) {
                return SingleChildScrollView(
                  key: const Key('mower-control-scroll-view'),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      FittedBox(fit: BoxFit.scaleDown, child: card),
                      const SizedBox(height: 4),
                      ...lower,
                    ],
                  ),
                );
              }
              return Padding(
                key: const Key('mower-control-scroll-view'),
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // 电量环按剩余的宽、高**等比缩放撑满**（2026-09-23 产品：「圈的直径再大一点，结合 UI 看
                    // 实际明显小一圈」）。原来是只缩不放（scaleDown）：宽屏上还是稿子的 263，比稿子占屏比例小；
                    // 高度被下面几块吃掉时还会再缩。稿子 375 宽屏上环 263 ≈ 屏宽 70%，这里按宽撑满后比例一致。
                    Expanded(
                      child: Align(
                        key: const Key('mower-status-viewport'),
                        alignment: Alignment.center,
                        child: FittedBox(fit: BoxFit.contain, child: card),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...lower,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 已关机（DP113 非在桩关机，协议 V2.5 §9.9）时黄条上的那句话。
const String _shutdownNotice = '割草机已关机，开机后可继续操作';

/// 状态卡（电量环）的设计宽度：稿子卡片 335 宽。
const double _cardWidth = 335;

/// 电量环缩到 80% 时整页需要的最小高度（环 292×0.8 + 提醒 38 + 计划 110 + 按钮面板 104 + 间距 / 边距）。
const double _minFittedHeight = 520;

/// 黄色提醒条：DP18 有故障位时画那条故障文案（位序最低的一条）；没有故障时画实时提醒。
/// DP18 = 0（正常）或没报过时整条不画（协议 V2.3，2026-09-23 产品）——原来那句稿子上的
/// 安全提示「开始割草前，请清理草坪中的障碍物」不再显示。
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.fault});

  final String fault;

  @override
  Widget build(BuildContext context) {
    final text = fault;
    return Container(
      key: const Key('mower-safety-notice'),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: BoxDecoration(
        color: MowerColors.noticeFill,
        border: Border.all(color: MowerColors.noticeBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Image.asset(
            MowerAssets.safetyTipIcon,
            width: 17,
            height: 16,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              key: const Key('mower-notice-text'),
              style: const TextStyle(
                color: MowerColors.noticeText,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 今日计划卡。**数据来自 DP101 解析**（2026-09-18 用户：割草计划不存数据库）。
class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard({required this.schedule});

  final List<MowerScheduleDay> schedule;

  static const List<String> _weekdayLabels = <String>[
    '周日',
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // DateTime.weekday 是 1=周一…7=周日，界面序是 0=周日…6=周六。
    final weekday = now.weekday % 7;
    final day = weekday < schedule.length
        ? schedule[weekday]
        : const MowerScheduleDay();
    // 只认设备会执行的时段（有效位 + 时长 > 10 分钟）。一个都没有（包括设备还没报过 DP101）
    // 就画缺省态，不编（2026-09-23 产品：「图标 + 暂无割草计划」，日期和星期保留）。
    final slots = <MowerScheduleSlot>[
      for (final slot in <MowerScheduleSlot?>[day.slotOne, day.slotTwo])
        if (slot != null && slot.validForDevice) slot,
    ];
    final one = slots.isEmpty ? null : slots.first;
    final two = slots.length > 1 ? slots[1] : null;
    final dateText =
        '${now.year}.${_two(now.month)}.${_two(now.day)} · ${_weekdayLabels[weekday]}';
    return MowerCard(
      key: const Key('mower-today-plan'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                '今日计划',
                style: TextStyle(
                  color: MowerColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.54,
                ),
              ),
              Text(
                dateText,
                style: const TextStyle(
                  color: MowerColors.inkSecondary,
                  fontSize: 12,
                  height: 1.33,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (one == null)
            const Padding(
              key: Key('mower-today-empty'),
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.event_busy_outlined,
                    size: 20,
                    color: MowerColors.inkTertiary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '暂无割草计划',
                    style: TextStyle(
                      color: MowerColors.inkSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else ...<Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_hhmm(one.startMinutes)}  →  ${_hhmm(one.endMinutes)}',
                      key: const Key('mower-today-range'),
                      style: const TextStyle(
                        color: MowerColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        height: 1.56,
                      ),
                    ),
                  ),
                ),
                if (day.edge) const SizedBox(width: 8),
                if (day.edge)
                  Container(
                    width: 54,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: MowerColors.softFill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '修边',
                      style: TextStyle(color: MowerColors.brand, fontSize: 12),
                    ),
                  ),
              ],
            ),
            if (two != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '下一任务 ${_hhmm(two.startMinutes)} - ${_hhmm(two.endMinutes)}',
                style: const TextStyle(
                  color: MowerColors.brand,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _hhmm(int minutes) =>
      '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
}

/// 四颗操作按钮。左三 = DP3，最右 = DP2。
class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.device,
    required this.checking,
    required this.onMode,
    required this.onToggleSwitch,
  });

  final MowerDevice device;

  /// 正在做控制前检查的那颗（`MowerMode.name` / `switch`），画成转圈。
  final String? checking;
  final ValueChanged<MowerMode> onMode;
  final VoidCallback onToggleSwitch;

  @override
  Widget build(BuildContext context) {
    // 左三：设备暂停（DP5=paused，按过「停止」）时一律不可点；其余时候只有
    // DP3 == 这颗的那一颗置灰，别的都能点（2026-09-23 用户更正）。
    final running = device.commandsEnabled;
    return MowerCard(
      key: const Key('mower-action-panel'),
      radius: 14,
      // 稿子面板 104 高（按钮 86 + 上下 9）。
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (final entry in _modeButtons)
            Flexible(
              child: _ActionButton(
                buttonKey: Key('mower-action-${entry.$1.name}'),
                icon: entry.$2,
                label: entry.$3,
                active: device.isCurrentMode(entry.$1),
                busy: checking == entry.$1.name,
                enabled: running && !device.isCurrentMode(entry.$1),
                onTap: () => onMode(entry.$1),
              ),
            ),
          Flexible(
            child: _ActionButton(
              buttonKey: const Key('mower-action-switch'),
              // DP2=true ⇒ 正在跑，按钮是「停止」；false ⇒ 已停，按钮是「继续」。
              icon: device.switchGo
                  ? MowerAssets.actionStopIcon
                  : MowerAssets.actionResumeIcon,
              label: device.switchGo ? '停止' : '继续',
              active: false,
              busy: checking == 'switch',
              // 已关机（DP113）时发不出去，置灰。
              enabled: device.switchEnabled,
              onTap: onToggleSwitch,
            ),
          ),
        ],
      ),
    );
  }

  /// 左边三颗：界面文案 ↔ DP3 枚举。⚠️「自动」对应的是 **smart（随机割草）**
  /// （2026-09-18 用户明确），不是别的什么自动模式。
  static const List<(MowerMode, String, String)> _modeButtons =
      <(MowerMode, String, String)>[
        (MowerMode.smart, MowerAssets.actionAutoIcon, '自动'),
        (MowerMode.spot, MowerAssets.actionSpotIcon, '定点'),
        (MowerMode.gotoCharge, MowerAssets.actionReturnIcon, '回归'),
      ];
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
    this.busy = false,
  });

  /// 控制前检查中：图标槽位显示转圈，文字和按钮尺寸不变。
  final bool busy;

  final Key buttonKey;
  final String icon;
  final String label;

  /// 当前就是这个模式：底色高亮（同时也不可点，见 [enabled]）。
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: buttonKey,
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        // 不可点就整颗压暗——稿子没给禁用态，置灰是最不容易误解的画法。
        opacity: enabled ? 1 : .4,
        child: Container(
          width: 70,
          height: 86,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? MowerColors.softFill : null,
            borderRadius: BorderRadius.circular(12),
          ),
          // 检查中**只把图标那 40×40 的位置换成转圈**，文字照旧——四颗的图标行、文字行都对齐
          // （2026-09-23 产品：转圈没和其它几个对齐。之前是整颗内容换成一个圈，圈在 86 高里居中，
          // 落在图标和文字之间）。
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox.square(
                dimension: 40,
                child: Center(
                  child: busy
                      ? const CircularProgressIndicator(
                          key: Key('mower-action-busy'),
                          constraints: BoxConstraints.tightFor(
                            width: 24,
                            height: 24,
                          ),
                          padding: EdgeInsets.zero,
                          strokeWidth: 2.6,
                          color: MowerColors.brand,
                        )
                      : Image.asset(
                          icon,
                          width: 40,
                          height: 40,
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
                        ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                style: const TextStyle(
                  color: MowerColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
