import 'package:flutter/material.dart';

import '../../mower_ui.dart';
import '../../mower_dp.dart';
import 'mower_form.dart';

/// 编辑弹窗里一整天的草稿（对应 DP101 的一组 11 字节）。
class MowerPlanDraft {
  const MowerPlanDraft({
    required this.day,
    required this.one,
    required this.two,
    this.activeSlot = 1,
    this.edge = false,
    this.copyWeek = false,
  });

  /// 从 DP 解析出来的那一天开编辑器。
  ///
  /// 那天还没有时段：**不预填任何时间**（2026-09-23 产品：「没有数据时不能做假的数据渲染」）。
  /// 原来预填稿子上的 09:00–11:30 / 14:00–15:00 而且是开着的，点一下保存就把假时段发给了设备。
  /// 现在给 00:00–00:00 且**关着**的空时段——用户打开开关、选好时间才算数；关着的时段不写进 DP101。
  factory MowerPlanDraft.forDay(
    int day,
    List<MowerScheduleDay> week, {
    int activeSlot = 1,
  }) {
    final source = day < week.length ? week[day] : const MowerScheduleDay();
    return MowerPlanDraft(
      day: day,
      activeSlot: activeSlot,
      one: source.slotOne ?? _unset,
      two: source.slotTwo ?? _unset,
      edge: source.edge,
    );
  }

  /// 还没排的时段：没有时间、关着。
  static const MowerScheduleSlot _unset = MowerScheduleSlot(
    startMinutes: 0,
    endMinutes: 0,
    enabled: false,
  );

  final int day;
  final MowerScheduleSlot one;
  final MowerScheduleSlot two;
  final int activeSlot;

  /// 修边（沿边割草）。⚠️ DP101 里它是**每组一个字节**（整天一个开关），
  /// 不是每个时段一个——稿子把它画在时段编辑里，这里就按整天生效。
  final bool edge;

  /// 「复制整周」：保存时把这一天铺到七天。
  final bool copyWeek;

  MowerScheduleSlot get active => activeSlot == 1 ? one : two;

  MowerScheduleDay get day0 =>
      MowerScheduleDay(slotOne: one, slotTwo: two, edge: edge);

  /// 两个时段都开着且相交时给出提示；端点相接不算重叠。
  String? get overlapMessage => day0.overlapMessage;

  MowerPlanDraft copyWith({
    MowerScheduleSlot? one,
    MowerScheduleSlot? two,
    int? activeSlot,
    bool? edge,
    bool? copyWeek,
  }) => MowerPlanDraft(
    day: day,
    one: one ?? this.one,
    two: two ?? this.two,
    activeSlot: activeSlot ?? this.activeSlot,
    edge: edge ?? this.edge,
    copyWeek: copyWeek ?? this.copyWeek,
  );
}

/// 保存成功；[draft] 已过重叠与时长校验。
class MowerPlanEditSaved {
  const MowerPlanEditSaved(this.draft);

  final MowerPlanDraft draft;
}

/// 保存时撞上重叠：弹窗先关，由页面弹「时间段重叠」，点「返回修改」再带着同一份草稿开回来。
class MowerPlanEditOverlap {
  const MowerPlanEditOverlap(this.draft, this.message);

  final MowerPlanDraft draft;
  final String message;
}

/// 打开「编辑周X」弹窗。返回 [MowerPlanEditSaved] / [MowerPlanEditOverlap] / null。
Future<Object?> showMowerPlanEditSheet(
  BuildContext context, {
  required MowerPlanDraft draft,
}) {
  return showModalBottomSheet<Object?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x471A1F1F),
    builder: (_) => _MowerPlanEditSheet(draft: draft),
  );
}

class _MowerPlanEditSheet extends StatefulWidget {
  const _MowerPlanEditSheet({required this.draft});

  final MowerPlanDraft draft;

  @override
  State<_MowerPlanEditSheet> createState() => _MowerPlanEditSheetState();
}

class _MowerPlanEditSheetState extends State<_MowerPlanEditSheet> {
  late MowerPlanDraft _draft = widget.draft;

  MowerScheduleSlot get _active => _draft.active;

  void _updateActive(MowerScheduleSlot slot) {
    setState(() {
      _draft = _draft.activeSlot == 1
          ? _draft.copyWith(one: slot)
          : _draft.copyWith(two: slot);
    });
  }

  void _save() {
    final message = _draft.overlapMessage;
    Navigator.of(context).pop(
      message == null
          ? MowerPlanEditSaved(_draft)
          : MowerPlanEditOverlap(_draft, message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration = _active.durationMinutes;
    final enabled = _active.enabled;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '编辑周${MowerPlanAxis.dayLabels[_draft.day]}',
                    key: const Key('mower-plan-edit-title'),
                    style: const TextStyle(
                      color: MowerColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '上下滑动选择小时与分钟',
                    style: TextStyle(
                      color: MowerColors.inkSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const ColoredBox(
              color: MowerColors.divider,
              child: SizedBox(height: 1, width: double.infinity),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        for (final slot in <int>[1, 2])
                          Expanded(
                            child: _SlotTab(
                              slot: slot,
                              active: _draft.activeSlot == slot,
                              // 关掉的时段在标签上就看得出来，不用切进去才发现是灰的
                              enabled: slot == 1
                                  ? _draft.one.enabled
                                  : _draft.two.enabled,
                              onTap: () => setState(
                                () => _draft = _draft.copyWith(activeSlot: slot),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // 时段总开关（2026-09-18 用户要求：在修边上面加，分别管时段 1 / 2；
                    // 关着时下面整块置灰禁用；默认开启）。对应 DP101 每组的「时段 N 有效」字节。
                    _SheetSwitchCard(
                      title: '启用时段${_draft.activeSlot}',
                      subtitle: '关闭后该时段不下发（DP101 有效位=0）',
                      value: enabled,
                      switchKey: const Key('mower-plan-edit-slot-enabled'),
                      onChanged: (value) =>
                          _updateActive(_active.copyWith(enabled: value)),
                    ),
                    const SizedBox(height: 12),
                    // 关掉之后整块变灰且点不动——这是"置灰禁用"，不是藏起来：
                    // 用户要能看见自己关掉的是哪一段时间。
                    IgnorePointer(
                      ignoring: !enabled,
                      child: Opacity(
                        opacity: enabled ? 1 : .4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _TimePickers(
                              key: ValueKey<int>(_draft.activeSlot),
                              slot: _active,
                              onChanged: _updateActive,
                            ),
                            const SizedBox(height: 14),
                            // 稿子 673:7897 时长条 36 高（原 56，整张弹层比稿子高约 110，要内部滚动）。
                            Container(
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: MowerColors.brand.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              // 时长是**端上自己算的**（2026-09-18 用户明确），不是设备给的。
                              // ⚠️ 设备只认 >10 分钟的时段，短了会被丢弃，所以这里直接说出来。
                              child: Text(
                                _durationText(duration),
                                key: const Key('mower-plan-edit-duration'),
                                style: TextStyle(
                                  color: duration > 10
                                      ? MowerColors.brand
                                      : MowerColors.danger,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SheetSwitchCard(
                      title: '修边',
                      subtitle: '先绕边再割草（DP101 沿边位，整天生效）',
                      value: _draft.edge,
                      switchKey: const Key('mower-plan-edit-trim'),
                      onChanged: (value) =>
                          setState(() => _draft = _draft.copyWith(edge: value)),
                    ),
                    const SizedBox(height: 10),
                    _SheetSwitchCard(
                      title: '复制整周',
                      subtitle: '将当前时段与修边设置应用到整周',
                      value: _draft.copyWeek,
                      switchKey: const Key('mower-plan-edit-copy-week'),
                      onChanged: (value) => setState(
                        () => _draft = _draft.copyWith(copyWeek: value),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _SheetButton(
                      label: '取消',
                      buttonKey: const Key('mower-plan-edit-cancel'),
                      background: MowerColors.softFill,
                      foreground: MowerColors.brand,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _SheetButton(
                      label: '保存',
                      buttonKey: const Key('mower-plan-edit-save'),
                      background: MowerColors.brand,
                      foreground: Colors.white,
                      onTap: _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 时长文案。⚠️ 结束早于开始、或不足 10 分钟都要当场说清楚——
  /// 前者是用户拨错了，后者会被设备直接丢掉（V2.2 §5.1）。
  static String _durationText(int minutes) {
    if (minutes <= 0) return '结束时间需晚于开始时间';
    if (minutes <= 10) return '时长 $minutes 分（不足 10 分，设备会丢弃）';
    return '时长 ${minutes ~/ 60} 小时 ${minutes % 60} 分';
  }
}

class _SlotTab extends StatelessWidget {
  const _SlotTab({
    required this.slot,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final int slot;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('mower-plan-edit-tab-$slot'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: <Widget>[
          Text(
            '时段$slot${enabled ? '' : '（已关闭）'}',
            style: TextStyle(
              color: active
                  ? MowerColors.brand
                  : (enabled ? MowerColors.ink : MowerColors.inkTertiary),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 3,
            width: 72,
            decoration: BoxDecoration(
              color: active ? MowerColors.brand : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 开始 / 结束两组滚轮。
///
/// ⚠️ **分钟是 1 分一格，稿子上画的是 10 分一格**——稿子自己的图表里有 16:23 这种时间，
/// 10 分一格根本选不出来。版式一样，只是相邻两行的数字不同。
class _TimePickers extends StatefulWidget {
  const _TimePickers({
    required this.slot,
    required this.onChanged,
    super.key,
  });

  final MowerScheduleSlot slot;
  final ValueChanged<MowerScheduleSlot> onChanged;

  @override
  State<_TimePickers> createState() => _TimePickersState();
}

class _TimePickersState extends State<_TimePickers> {
  static const int _minuteStep = 1;
  static const double _itemExtent = 40;

  late final FixedExtentScrollController _startHour;
  late final FixedExtentScrollController _startMinute;
  late final FixedExtentScrollController _endHour;
  late final FixedExtentScrollController _endMinute;

  @override
  void initState() {
    super.initState();
    _startHour = FixedExtentScrollController(
      initialItem: widget.slot.startMinutes ~/ 60,
    );
    _startMinute = FixedExtentScrollController(
      initialItem: widget.slot.startMinutes % 60 ~/ _minuteStep,
    );
    _endHour = FixedExtentScrollController(
      initialItem: widget.slot.endMinutes ~/ 60,
    );
    _endMinute = FixedExtentScrollController(
      initialItem: widget.slot.endMinutes % 60 ~/ _minuteStep,
    );
  }

  @override
  void dispose() {
    _startHour.dispose();
    _startMinute.dispose();
    _endHour.dispose();
    _endMinute.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            Expanded(
              child: _PickerSide(
                label: '开始时间',
                hourController: _startHour,
                minuteController: _startMinute,
                minutes: slot.startMinutes,
                itemExtent: _itemExtent,
                minuteStep: _minuteStep,
                onChanged: (value) =>
                    widget.onChanged(slot.copyWith(startMinutes: value)),
              ),
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: MowerColors.divider,
              indent: 8,
              endIndent: 8,
            ),
            Expanded(
              child: _PickerSide(
                label: '结束时间',
                hourController: _endHour,
                minuteController: _endMinute,
                minutes: slot.endMinutes,
                itemExtent: _itemExtent,
                minuteStep: _minuteStep,
                onChanged: (value) =>
                    widget.onChanged(slot.copyWith(endMinutes: value)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerSide extends StatelessWidget {
  const _PickerSide({
    required this.label,
    required this.hourController,
    required this.minuteController,
    required this.minutes,
    required this.itemExtent,
    required this.minuteStep,
    required this.onChanged,
  });

  final String label;
  final FixedExtentScrollController hourController;
  final FixedExtentScrollController minuteController;
  final int minutes;
  final double itemExtent;
  final int minuteStep;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: MowerColors.inkSecondary,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: <Widget>[
            Expanded(child: _PickerHeader(text: '小时')),
            Expanded(child: _PickerHeader(text: '分钟')),
          ],
        ),
        SizedBox(
          height: itemExtent * 3,
          child: Stack(
            children: <Widget>[
              Center(
                child: Container(
                  height: itemExtent + 6,
                  decoration: BoxDecoration(
                    color: MowerColors.brand.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: MowerWheel(
                      controller: hourController,
                      count: 24,
                      selected: hour,
                      itemExtent: itemExtent,
                      activeFontSize: 24,
                      onSelected: (value) => onChanged(value * 60 + minute),
                    ),
                  ),
                  Expanded(
                    child: MowerWheel(
                      controller: minuteController,
                      count: 60 ~/ minuteStep,
                      selected: minute ~/ minuteStep,
                      itemExtent: itemExtent,
                      activeFontSize: 24,
                      onSelected: (value) =>
                          onChanged(hour * 60 + value * minuteStep),
                    ),
                  ),
                ],
              ),
              const Center(
                child: Text(
                  ':',
                  style: TextStyle(
                    color: MowerColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: MowerColors.inkTertiary, fontSize: 13),
    );
  }
}

class _SheetSwitchCard extends StatelessWidget {
  const _SheetSwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.switchKey,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key switchKey;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: MowerSwitchRow(
        title: title,
        subtitle: subtitle,
        value: value,
        switchKey: switchKey,
        onChanged: onChanged,
        // 稿子开关卡 48 高。
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    required this.buttonKey,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        key: buttonKey,
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }
}
