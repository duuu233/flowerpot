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
/// 1. **启动/停止优先级最高**：只有 DP2=true 时，左边三颗才能点；
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

  @override
  void initState() {
    super.initState();
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
          'DP${MowerDp.fault}=${_device.faultBitmap}，'
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

  void _toggleSwitch() {
    final state = FlowerpotScope.of(context);
    _device.setSwitch(state, on: !_device.switchGo);
  }

  /// 左边三颗。点之前的两道闸：DP2 必须是启动态（按钮此时才可点），DP118 必须合盖。
  Future<void> _sendMode(MowerMode target) async {
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
        body: SingleChildScrollView(
          key: const Key('mower-control-scroll-view'),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MowerStatusCard(
                tone: _tone,
                percent: _device.battery,
                statusLabel: _device.status.label,
              ),
              const SizedBox(height: 24),
              _NoticeBar(fault: _device.faultMessage),
              const SizedBox(height: 8),
              _TodayPlanCard(schedule: _device.schedule),
              const SizedBox(height: 8),
              _ActionPanel(
                device: _device,
                onMode: (mode) => unawaited(_sendMode(mode)),
                onToggleSwitch: _toggleSwitch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 没有故障时那句安全提示（稿子上的固定文案，不是数据）。
const String _safetyTip = '开始割草前，请清理草坪中的障碍物';

/// 黄色提醒条：有故障（DP18）就画故障文案，没有就画那句安全提示。
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.fault});

  final String? fault;

  @override
  Widget build(BuildContext context) {
    final text = fault ?? _safetyTip;
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
    final one = day.slotOne;
    final two = day.slotTwo;
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                one == null
                    ? '今日无计划'
                    : '${_hhmm(one.startMinutes)}  →  ${_hhmm(one.endMinutes)}',
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
          const SizedBox(height: 4),
          Text(
            two == null
                ? '今日没有第二个时段'
                : '下一任务 ${_hhmm(two.startMinutes)} - ${_hhmm(two.endMinutes)}',
            style: const TextStyle(
              color: MowerColors.brand,
              fontSize: 12,
              height: 1.5,
            ),
          ),
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
    required this.onMode,
    required this.onToggleSwitch,
  });

  final MowerDevice device;
  final ValueChanged<MowerMode> onMode;
  final VoidCallback onToggleSwitch;

  @override
  Widget build(BuildContext context) {
    // 左三：DP2 停着时一律不可点；当前模式那一颗置灰不给重复下发。
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
  });

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
          child: Column(
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
