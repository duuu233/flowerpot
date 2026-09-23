import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../mower_ui.dart';
import '../mower_device.dart';
import '../mower_dp.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_plan_chart.dart';
import 'widgets/mower_plan_dialogs.dart';
import 'widgets/mower_plan_edit_sheet.dart';

/// 割草计划页（`割草机-割草计划.png` 及编辑弹窗、两张提示弹窗）。
///
/// ## 数据从哪来（2026-09-18 用户明确）
///
/// **不存数据库，显示依赖 DP 解析。** 这一页画的就是 `MowerDevice.schedule`——
/// 最后一次下发/上报的 DP101 解出来的那份（88 字节 = 8 组 × 11 字节，见 [MowerScheduleCodec]）。
///
/// ⚠️ **每次保存都是全量替换**：设备收到 DP101 会清空重建，所以任何一次改动都要把
/// **整周七天**一起发下去，不能只发改的那一天（V2.2 §5.1）。
class MowerPlanPage extends StatefulWidget {
  const MowerPlanPage({super.key});

  @override
  State<MowerPlanPage> createState() => _MowerPlanPageState();
}

class _MowerPlanPageState extends State<MowerPlanPage> {
  MowerDevice get _device => MowerDevice.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = FlowerpotScope.of(context);
      state
        ..logPageEntry('割草机-割草计划')
        ..logMowerInteraction(
          '读取 ← 割草机-割草计划 DP${MowerDp.mowSchedule} mow_schedule '
          '= ${MowerScheduleCodec.toHexGroups(MowerScheduleCodec.encodeByDay(_device.schedule))}',
        );
    });
  }

  /// DP 里的一周 → 图表要的色块。修边是**整天**一个标志（DP101 每组一个字节），
  /// 所以那天的两个时段都画成修边样式。
  List<MowerPlanSlot> get _chartSlots {
    final slots = <MowerPlanSlot>[];
    for (var day = 0; day < _device.schedule.length; day++) {
      final source = _device.schedule[day];
      void add(MowerScheduleSlot? slot, int index) {
        if (slot == null || !slot.enabled) return;
        slots.add(
          MowerPlanSlot(
            day: day,
            startMinutes: slot.startMinutes,
            endMinutes: slot.endMinutes,
            slot: index,
            trim: source.edge,
          ),
        );
      }

      add(source.slotOne, 1);
      add(source.slotTwo, 2);
    }
    return slots;
  }

  /// 勾选＝这一天有启用中的时段。取消勾选＝把这天两个时段的有效位清掉（时间留着）。
  List<bool> get _enabledDays => <bool>[
    for (final day in _device.schedule)
      (day.slotOne?.enabled ?? false) || (day.slotTwo?.enabled ?? false),
  ];

  /// 合计只算启用中的时段——关掉的时段设备不会跑。
  String get _totalLabel {
    var minutes = 0;
    for (final day in _device.schedule) {
      for (final slot in <MowerScheduleSlot?>[day.slotOne, day.slotTwo]) {
        if (slot != null && slot.enabled && slot.durationMinutes > 0) {
          minutes += slot.durationMinutes;
        }
      }
    }
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (minutes == 0) return '总工作时间：未设置';
    if (hours == 0) return '总工作时间：$rest分钟';
    if (rest == 0) return '总工作时间：$hours小时';
    return '总工作时间：$hours小时$rest分钟';
  }

  void _publish(List<MowerScheduleDay> week) {
    final state = FlowerpotScope.of(context);
    setState(() => _device.setSchedule(state, week));
  }

  List<MowerScheduleDay> get _week => List<MowerScheduleDay>.of(_device.schedule);

  Future<void> _edit(int day, int? slot) async {
    var draft = MowerPlanDraft.forDay(
      day,
      _device.schedule,
      activeSlot: slot ?? 1,
    );
    // 重叠时先关弹窗、再弹提示，「返回修改」把同一份草稿原样开回去——
    // 稿子上那张提示图的背景就是计划页本身。
    while (true) {
      if (!mounted) return;
      final result = await showMowerPlanEditSheet(context, draft: draft);
      if (result is MowerPlanEditSaved) {
        if (!mounted) return;
        _apply(result.draft);
        return;
      }
      if (result is! MowerPlanEditOverlap) return;
      if (!mounted) return;
      final retry = await showMowerOverlapDialog(
        context,
        message: result.message,
      );
      if (retry != true) return;
      draft = result.draft;
    }
  }

  void _apply(MowerPlanDraft draft) {
    final week = _week;
    final day = draft.day0;
    if (draft.copyWeek) {
      for (var index = 0; index < week.length; index++) {
        week[index] = day;
      }
    } else {
      week[draft.day] = day;
    }
    _publish(week);
  }

  void _toggleDay(int day) {
    final week = _week;
    final source = week[day];
    final next = !((source.slotOne?.enabled ?? false) ||
        (source.slotTwo?.enabled ?? false));
    // 那天一个时段都没有：没什么可开的，直接把编辑器打开让用户排一个。
    if (next && source.slotOne == null && source.slotTwo == null) {
      unawaited(_edit(day, 1));
      return;
    }
    week[day] = source.copyWith(
      slotOne: source.slotOne?.copyWith(enabled: next),
      slotTwo: source.slotTwo?.copyWith(enabled: next),
    );
    _publish(week);
  }

  void _deleteSlot(MowerPlanSlot target) {
    final week = _week;
    final source = week[target.day];
    week[target.day] = MowerScheduleDay(
      slotOne: target.slot == 1 ? null : source.slotOne,
      slotTwo: target.slot == 2 ? null : source.slotTwo,
      edge: source.edge,
    );
    _publish(week);
  }

  /// 「恢复默认」：先问一句，确认后下发 **DP110 schedule_reset = true**（协议 V2.3 新增）。
  ///
  /// 默认计划由**设备**决定（每天 09:00–11:30 + 13:30–17:30），App 不自己编、也不先本地改——
  /// 设备写好后会上报 DP101，界面随那条上报刷新，下面的临时窗口也会打出解析。
  /// （2026-09-23 上午曾因 V2.2 没有这条而改成只提示；此前下发的是设计稿上的四块，是假数据。）
  Future<void> _restoreDefault() async {
    final confirmed = await showMowerRestoreDefaultDialog(context);
    if (confirmed != true || !mounted) return;
    MowerDevice.instance.resetSchedule(FlowerpotScope.of(context));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _device,
      builder: (context, _) => AppPageScaffold(
        appBar: AppPageHeader(
          title: '割草计划',
          leading: const AppBackButton(),
          actions: <Widget>[
            _RestoreDefaultButton(onTap: () => unawaited(_restoreDefault())),
          ],
        ),
        body: SingleChildScrollView(
          key: const Key('mower-plan-scroll-view'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Text(
                    '本周计划',
                    style: TextStyle(
                      color: MowerColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _totalLabel,
                    key: const Key('mower-plan-total'),
                    style: const TextStyle(
                      color: MowerColors.brand,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              MowerCard(
                padding: const EdgeInsets.only(bottom: 18),
                child: MowerPlanChart(
                  enabledDays: _enabledDays,
                  slots: _chartSlots,
                  onToggleDay: _toggleDay,
                  onEditDay: (day, slot) => unawaited(_edit(day, slot)),
                  onDeleteSlot: _deleteSlot,
                ),
              ),
              const SizedBox(height: 16),
              _ScheduleDebugWindow(device: _device),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标题栏右边那颗「恢复默认」。
class _RestoreDefaultButton extends StatelessWidget {
  const _RestoreDefaultButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        key: const Key('mower-plan-restore'),
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: MowerColors.softFill,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.history_rounded, size: 16, color: MowerColors.brand),
              SizedBox(width: 5),
              Text(
                '恢复默认',
                style: TextStyle(color: MowerColors.brand, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// DP101 解析的**临时窗口**（2026-09-23 联调：「割草计划你把数据解析出来打印在日志上，我要对比一下，
/// 可以在页面下方搞个临时窗口」）。**联调设施，不是产品功能**，联调完删掉。
///
/// 画的是最近一次的原始 88 字节（设备上报或本机下发，哪个晚用哪个），逐组逐字段解析
/// （[MowerScheduleCodec.describe]）；同样的内容也打进了联调日志。点「复制」整段进剪贴板。
class _ScheduleDebugWindow extends StatelessWidget {
  const _ScheduleDebugWindow({required this.device});

  final MowerDevice device;

  String get _text {
    final raw = device.scheduleRaw;
    if (raw == null) {
      return 'DP${MowerDp.mowSchedule} 还没有数据：设备没报过、本机也没下发过';
    }
    final at = device.scheduleRawAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = at == null
        ? ''
        : ' ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
    return <String>[
      'DP${MowerDp.mowSchedule} mow_schedule · ${device.scheduleRawSource}$time · ${raw.length} 字节',
      'hex  ${MowerScheduleCodec.toHexGroups(raw)}',
      'base64  ${MowerScheduleCodec.toBase64(raw)}',
      ...MowerScheduleCodec.describe(raw),
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return Container(
      key: const Key('mower-plan-debug-window'),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2A2B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '临时 · 割草计划解析（联调用）',
                  style: TextStyle(
                    color: Color(0xFFB8E3DE),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                key: const Key('mower-plan-debug-copy'),
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: text)));
                  showAppMessage(context, '已复制（${text.length} 字）');
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB8E3DE),
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('复制', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          SelectableText(
            text,
            style: const TextStyle(
              color: Color(0xFFE8F1F0),
              fontSize: 11,
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
