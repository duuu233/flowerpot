import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/config/debug_log_gate.dart';

import '../../devices/presentation/device_online_guard.dart';
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
  bool _deleteDialogOpen = false;

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

  /// DP 里的一周 → 图表要的色块。**只画启用中的时段**：在编辑弹窗里停用的时段不出现在图上，
  /// 再启用就原样回来（2026-10-08 用户；停用的起止时间照样写进 DP101，见 [MowerScheduleCodec]）。
  /// 修边不在色块上画，由星期下面那排勾表示。
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
          ),
        );
      }

      add(source.slotOne, 1);
      add(source.slotTwo, 2);
    }
    return slots;
  }

  /// 这一天有启用中的时段：星期字和底槽变色用。
  List<bool> get _enabledDays => <bool>[
    for (final day in _device.schedule)
      (day.slotOne?.enabled ?? false) || (day.slotTwo?.enabled ?? false),
  ];

  /// 星期下面那排勾 = 这天修不修边（DP101 沿边位）。
  List<bool> get _trimDays => <bool>[
    for (final day in _device.schedule) day.edge,
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

  List<MowerScheduleDay> get _week =>
      List<MowerScheduleDay>.of(_device.schedule);

  Future<void> _edit(int day, int? slot) async {
    final original = _device.schedule[day];
    var draft = MowerPlanDraft.forDay(
      day,
      _device.schedule,
      activeSlot: slot ?? _blankSlot(day),
    );
    // 重叠时先关弹窗、再弹提示，「返回修改」把同一份草稿原样开回去——
    // 稿子上那张提示图的背景就是计划页本身。
    while (true) {
      if (!mounted) return;
      final result = await showMowerPlanEditSheet(context, draft: draft);
      if (result is MowerPlanEditSaved) {
        if (!mounted) return;
        _apply(result.draft, original);
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

  void _apply(MowerPlanDraft draft, MowerScheduleDay original) {
    final week = _week;
    final edited = draft.day0;
    final current = week[draft.day];
    final day = MowerScheduleDay(
      slotOne: _mergeSlot(original.slotOne, edited.slotOne, current.slotOne),
      slotTwo: _mergeSlot(original.slotTwo, edited.slotTwo, current.slotTwo),
      edge: edited.edge == original.edge ? current.edge : edited.edge,
    );
    if (draft.copyWeek) {
      for (var index = 0; index < week.length; index++) {
        week[index] = day;
      }
    } else {
      week[draft.day] = day;
    }
    _publish(week);
  }

  MowerScheduleSlot? _mergeSlot(
    MowerScheduleSlot? original,
    MowerScheduleSlot? edited,
    MowerScheduleSlot? current,
  ) {
    if (original == null || edited == null || current == null) {
      final unchanged =
          original?.startMinutes == edited?.startMinutes &&
          original?.endMinutes == edited?.endMinutes &&
          original?.enabled == edited?.enabled;
      return unchanged ? current : edited;
    }
    return MowerScheduleSlot(
      startMinutes: edited.startMinutes == original.startMinutes
          ? current.startMinutes
          : edited.startMinutes,
      endMinutes: edited.endMinutes == original.endMinutes
          ? current.endMinutes
          : edited.endMinutes,
      enabled: edited.enabled == original.enabled
          ? current.enabled
          : edited.enabled,
    );
  }

  /// 点空白 = 添加：直接开在没启用的那个时段上（还没排的、或被停用的——停用的再打开就能原样启用），
  /// 两个都在用才开时段 1。
  int _blankSlot(int day) {
    final source = _device.schedule[day];
    if (!(source.slotOne?.enabled ?? false)) return 1;
    if (!(source.slotTwo?.enabled ?? false)) return 2;
    return 1;
  }

  /// 点星期下面那个勾：只翻这一天的修边（DP101 沿边位，整天一个），时段不动，照样整周下发。
  /// 那天还没有时段也能勾——先记着，排了时段就按修边跑。
  void _toggleTrim(int day) {
    final week = _week;
    week[day] = week[day].copyWith(edge: !week[day].edge);
    _publish(week);
  }

  Future<void> _deleteSlot(MowerPlanSlot target) async {
    if (_deleteDialogOpen) return;
    _deleteDialogOpen = true;
    final bool confirmed;
    try {
      confirmed = await showAppConfirmDialog(
        context,
        title: '删除计划时间',
        message: '计划时间是否要删除？',
        destructive: true,
      );
    } finally {
      _deleteDialogOpen = false;
    }
    if (!confirmed || !mounted) return;
    final week = _week;
    final source = week[target.day];
    final current = target.slot == 1 ? source.slotOne : source.slotTwo;
    // 确认期间设备可能改了这个时段，不能把另一个新计划误删掉。
    if (current == null) return;
    if (current.startMinutes != target.startMinutes ||
        current.endMinutes != target.endMinutes) {
      showAppMessage(context, '计划时间已更新，请重新长按删除');
      return;
    }
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
            _RestoreDefaultButton(
              onTap: _device.online && !_device.schedulePending
                  ? () => unawaited(_restoreDefault())
                  : null,
            ),
          ],
        ),
        body: DeviceOnlineBody(
          deviceId: MowerDevice.instance.deviceId,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              key: const Key('mower-plan-scroll-view'),
              padding: const EdgeInsets.fromLTRB(20, _topGap, 20, 24),
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
                  // 一周都没有会执行的时段（含设备还没报过 DP101）：说一句，图表只画空坐标，不填任何色块。
                  if (_chartSlots.isEmpty)
                    Padding(
                      key: const Key('mower-plan-empty'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.event_busy_outlined,
                            size: 18,
                            color: MowerColors.inkTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _device.scheduleRaw == null
                                ? '暂无割草计划（设备还没有上报）'
                                : '暂无割草计划，点某一天添加',
                            style: const TextStyle(
                              color: MowerColors.inkSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_device.schedulePending)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        '正在等待设备返回割草计划',
                        key: Key('mower-plan-pending'),
                      ),
                    ),
                  AbsorbPointer(
                    absorbing: _device.schedulePending,
                    child: MowerCard(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: SizedBox(
                        height: _chartHeight(constraints),
                        child: MowerPlanChart(
                          enabledDays: _enabledDays,
                          trimDays: _trimDays,
                          slots: _chartSlots,
                          onToggleTrim: _toggleTrim,
                          onEditDay: (day, slot) => unawaited(_edit(day, slot)),
                          onDeleteSlot: (slot) => unawaited(_deleteSlot(slot)),
                        ),
                      ),
                    ),
                  ),
                  if (DebugLogGate.enabled) ...<Widget>[
                    const SizedBox(height: 16),
                    _ScheduleDebugWindow(device: _device),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 图表卡片（不含卡片底边距 18）的高度：**撑满一屏、底下留一点缝**
  /// （2026-09-23 产品：「根据屏幕自适应一下高度，留有少许的间隔」）。
  ///
  /// 一屏 = 页面可用高度 − 上内边距 [_topGap] −「本周计划」那行约 20 − 间距 10 −（空周提示约 28）
  /// − 卡片底边距 18 − 底部留缝 [_bottomGap]。临时解析窗口在卡片下面，往下滚才看得到。
  /// 太矮的屏不再压：不低于 [_minChartHeight]，超出的部分滚动。
  double _chartHeight(BoxConstraints constraints) {
    if (!constraints.hasBoundedHeight) return _minChartHeight;
    final hint = _chartSlots.isEmpty ? 28.0 : 0.0;
    final height =
        constraints.maxHeight - _topGap - 20 - 10 - hint - 18 - _bottomGap;
    return height < _minChartHeight ? _minChartHeight : height;
  }

  static const double _bottomGap = 12;

  /// 标题栏下到「本周计划」的距离：稿子 561:2817 里「本周计划」在 y=108，正文从 90 起。
  static const double _topGap = 18;

  /// 图表的固定部分（星期、勾选、图例、说明）约 150，纵轴至少再留 280。
  static const double _minChartHeight = 430;
}

/// 标题栏右边那颗「恢复默认」。
class _RestoreDefaultButton extends StatelessWidget {
  const _RestoreDefaultButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 稿子里胶囊离屏幕右边 20；标题栏尾部自带 8，再补 12。
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Center(
        child: GestureDetector(
          key: const Key('mower-plan-restore'),
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? .45 : 1,
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
                  Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: MowerColors.brand,
                  ),
                  SizedBox(width: 5),
                  Text(
                    '恢复默认',
                    style: TextStyle(color: MowerColors.brand, fontSize: 13),
                  ),
                ],
              ),
            ),
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
    final lines = <String>[
      'DP101：组0=全部设置，组1~7=周一~周日；逐日设置组0全零；+8沿边，+9/+10时段有效',
      '显示来源：${device.hasScheduleReport ? '涂鸦返回DP101' : '尚未收到有效DP101'}',
      if (device.schedulePending) '下发状态：等待设备回读，页面尚未确认新计划',
      if (device.scheduleCommandResult case final result?)
        '本次DP115：dp=${result.dp}，code=${result.code}，seq=${result.seq}；${result.rejectionMessage ?? '已受理，显示仍以DP101为准'}',
    ];
    void append(Uint8List? raw, String source, DateTime? at) {
      lines.add('\n$source · ${at?.toIso8601String() ?? '无时间'}');
      if (raw == null) {
        lines.add('未收到数据');
        return;
      }
      lines.add('长度：${raw.length}字节（应为88）');
      lines.add('hex  ${MowerScheduleCodec.toHexGroups(raw)}');
      lines.add('base64  ${MowerScheduleCodec.toBase64(raw)}');
      if (raw.length != 88) {
        lines.add('异常长度：不更新页面计划，保留上一有效DP');
      }
      lines.addAll(MowerScheduleCodec.describe(raw));
    }

    append(
      device.scheduleRaw,
      device.scheduleRawSource.isEmpty ? '设备返回' : device.scheduleRawSource,
      device.scheduleRawAt,
    );
    append(device.scheduleSentRaw, '本机下发草稿（不是设备已确认）', device.scheduleSentAt);
    return lines.join('\n');
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
