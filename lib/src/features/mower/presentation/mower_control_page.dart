import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../mower_ui.dart';
import '../mower_device.dart';
import '../mower_dp.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_status_card.dart';

/// 割草机首页（`docs/UI/v2/割草机/割草机-控制.png` 及其三张状态图）。
///
/// ## 这一页的 DP（2026-09-18 接线）
///
/// | 元素 | DP |
/// | --- | --- |
/// | 电量环 | DP13 battery_percentage（充电态看 DP117） |
/// | 状态胶囊 | DP5 status |
/// | 黄色提醒 | DP18 fault（位图 → 文案，见 [MowerFault.messages]） |
/// | 今日计划 | DP101 mow_schedule 解析出来的今天那一组（**不存数据库**） |
/// | 停止 / 继续 | DP2 switch_go |
/// | 自动 / 定点 / 回归 | DP3 mode = smart / spot / goto_charge |
///
/// ## 四颗按钮的规矩（2026-09-18 用户口径，逐条）
///
/// 1. **启动/停止优先级最高**：按下「停止」、设备报 DP5=paused 时，左边三颗不能点，「继续」后恢复；
///    其余时候（包括刚开机的待机，DP2=false）DP3 不等于这颗就能点（2026-09-23 更正）；
/// 2. 按钮文案按 DP2 值：true 显示「停止」（点了下发 false），false 显示「继续」（点了下发 true）；
/// 3. 左边三颗**不能重复点**：`DP3 == 这颗` 就置灰；
/// 4. **记忆**：启动 → 点「定点」→ 停止 → 再启动，设备按最后一次 DP3 起，界面跟着回到「定点」
///    （V2.2 §3.2：`true(待机态)` = 按 App 最后下发的 DP3 模式启动）；
/// 5. 点左边三颗前先看 **DP118 盖子**：没合盖就弹窗、**不下发**。
///
/// 2026-09-23 起只接真机：只读 DP（盖子/故障/电量/充电）全部以设备上报为准，
/// 原来长按电量环的模拟上报面板已删。标题是设备在涂鸦里的名字。
class MowerControlPage extends StatefulWidget {
  const MowerControlPage({super.key});

  @override
  State<MowerControlPage> createState() => _MowerControlPageState();
}

class _MowerControlPageState extends State<MowerControlPage> {
  MowerDevice get _device => MowerDevice.instance;

  /// 每 3 秒按涂鸦的分通道状态刷新两个图标；蓝牙掉了顺带后台重连（节流见 MowerDevice）。
  Timer? _linkTimer;

  /// 控制前检查正在跑的那颗按钮（`MowerMode.name` 或 `switch`）；null = 没在检查。
  /// 这颗按钮画成转圈（2026-09-23 产品：「连接蓝牙的 loading 做到按钮那个位置，把按钮替换为转圈」），
  /// 检查期间再点任何一颗都不理（连蓝牙最长 15 秒）。
  String? _checking;

  @override
  void dispose() {
    _linkTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
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
    });
  }

  /// 电量环的视觉态：充电中看 DP117，其余按 DP13 的阈值分档。
  MowerPowerState get _tone {
    if (_device.charging != MowerChargingStatus.notCharging) {
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

  /// 四颗按钮（自动 / 定点 / 回归 / 停止·继续）下发前的蓝牙检查（2026-09-23 产品）：
  ///
  /// 1. 蓝牙没连 → 先连；连不上 → 「无法连接设备蓝牙，请检查设备或靠近设备10米内」，不下发；
  /// 2. 连着 → 读信号，弱于 [MowerDevice.minBleRssi]（-90 dBm）或读不到 →
  ///    「因安全要求必须在10米内控制设备」，不下发；
  /// 3. 都过了返回 null，否则返回要弹的那句话（弹框放在按钮恢复原样之后，见 [_guarded]）。
  /// 每一步都记进联调日志。
  Future<({String message, IconData icon})?> _bleProblem() async {
    const cannotConnect = (
      message: '无法连接设备蓝牙，请检查设备或靠近设备10米内',
      icon: Icons.bluetooth_disabled_rounded,
    );
    final state = FlowerpotScope.of(context);
    final id = _device.deviceId;
    if (id == null) return cannotConnect;
    final link = await state.deviceLinkState(id);
    if (!mounted) return null;
    if (link['ble'] != true) {
      state.logMowerInteraction('控制前检查 ⚠ 蓝牙未连接，先连接');
      final connected = await state.connectDeviceBle(id);
      if (!mounted) return null;
      unawaited(_device.refreshLink(state));
      if (connected['connected'] != true) {
        state.logMowerInteraction('控制前检查 ✗ 蓝牙连不上，指令不下发');
        return cannotConnect;
      }
    }
    final signal = await state.readDeviceBleRssi(id);
    if (!mounted) return null;
    final rssi = (signal['rssi'] as num?)?.toInt();
    if (signal['ok'] != true || rssi == null || rssi < MowerDevice.minBleRssi) {
      state.logMowerInteraction(
        '控制前检查 ✗ 蓝牙信号 ${rssi == null ? '读不到' : '$rssi dBm'}'
        '（要求不弱于 ${MowerDevice.minBleRssi} dBm），指令不下发',
      );
      return (
        message: '因安全要求必须在10米内控制设备',
        icon: Icons.social_distance_rounded,
      );
    }
    state.logMowerInteraction('控制前检查 ✓ 蓝牙已连接，信号 $rssi dBm');
    return null;
  }

  /// 按钮点击统一入口：检查中不重入；检查期间被点的那颗画成转圈；检查不过先把按钮恢复、
  /// 再弹提示，不下发。[button] 是被点的那颗。
  Future<void> _guarded(String button, Future<void> Function() action) async {
    if (_checking != null) return;
    setState(() => _checking = button);
    ({String message, IconData icon})? problem;
    try {
      problem = await _bleProblem();
    } finally {
      if (mounted) setState(() => _checking = null);
    }
    if (!mounted) return;
    if (problem != null) {
      await showAppNoticeDialog(
        context,
        title: '提示',
        message: problem.message,
        icon: problem.icon,
      );
      return;
    }
    await action();
  }

  Future<void> _toggleSwitch() => _guarded('switch', () async {
    final state = FlowerpotScope.of(context);
    _device.setSwitch(state, on: !_device.switchGo);
  });

  /// 左边三颗。先过蓝牙检查（[_bleReady]），再看 DP118 盖子。
  Future<void> _sendMode(MowerMode target) =>
      _guarded(target.name, () => _sendModeChecked(target));

  Future<void> _sendModeChecked(MowerMode target) async {
    final state = FlowerpotScope.of(context);
    if (!_device.coverClosed) {
      state.logMowerInteraction(
        '下发被拦 ✗ 割草机 DP${MowerDp.mode}=${target.code}：'
        'DP${MowerDp.coverStatus} cover_status=false（盖子未合）',
      );
      await showAppNoticeDialog(
        context,
        title: '盖子未合上',
        message: '请先合上盖子再启动割草机。\n（DP${MowerDp.coverStatus} cover_status = false）',
        icon: Icons.info_outline_rounded,
      );
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
        // **多出来的高度只给最上面的电量环**——环在剩下的空间里居中，屏幕矮时整块等比缩小。
        // 之前是把余量平分到各块之间，结果中间拉出两段空白。
        // 太矮（连缩到 80% 都放不下）才退回可滚动的按稿子尺寸排。
        body: LayoutBuilder(
          builder: (context, constraints) {
            final lower = <Widget>[
              // DP18 = 0（正常）或没报过：整条隐藏（协议 V2.3 位图口径，2026-09-23 产品）。
              if (_device.faultMessage case final fault?) ...<Widget>[
                _NoticeBar(fault: fault),
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
                percent: _device.battery,
                statusLabel: _device.status.label,
                wifiLinked: _device.wifiLinked,
                bleLinked: _device.bleLinked,
              ),
            );
            final fits = constraints.hasBoundedHeight &&
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
                  Expanded(
                    child: Center(
                      child: FittedBox(fit: BoxFit.scaleDown, child: card),
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
    );
  }
}

/// 状态卡（电量环）的设计宽度：稿子卡片 335 宽。
const double _cardWidth = 335;

/// 电量环缩到 80% 时整页需要的最小高度（环 292×0.8 + 提醒 38 + 计划 110 + 按钮面板 104 + 间距 / 边距）。
const double _minFittedHeight = 520;

/// 黄色提醒条：只在 DP18 有故障位时出现，画那条故障文案（位序最低的一条）。
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
                Text(
                  '${_hhmm(one.startMinutes)}  →  ${_hhmm(one.endMinutes)}',
                  key: const Key('mower-today-range'),
                  style: const TextStyle(
                    color: MowerColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    height: 1.56,
                  ),
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (final entry in _modeButtons)
            _ActionButton(
              buttonKey: Key('mower-action-${entry.$1.name}'),
              icon: entry.$2,
              label: entry.$3,
              active: device.isCurrentMode(entry.$1),
              busy: checking == entry.$1.name,
              enabled: running && !device.isCurrentMode(entry.$1),
              onTap: () => onMode(entry.$1),
            ),
          _ActionButton(
            buttonKey: const Key('mower-action-switch'),
            // DP2=true ⇒ 正在跑，按钮是「停止」；false ⇒ 已停，按钮是「继续」。
            icon: device.switchGo
                ? MowerAssets.actionStopIcon
                : MowerAssets.actionResumeIcon,
            label: device.switchGo ? '停止' : '继续',
            active: false,
            busy: checking == 'switch',
            enabled: true,
            onTap: onToggleSwitch,
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

  /// 控制前检查中：整颗换成转圈（图标 + 文字的位置），尺寸不变。
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
          child: busy
              ? const SizedBox.square(
                  key: Key('mower-action-busy'),
                  dimension: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: MowerColors.brand,
                  ),
                )
              : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Image.asset(
                icon,
                width: 40,
                height: 40,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
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
