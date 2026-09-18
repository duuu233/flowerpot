import 'package:flutter/material.dart';

import '../../mower_demo.dart';
import 'mower_form.dart';

/// 编辑弹窗里一个时段的草稿。
class MowerSlotDraft {
  const MowerSlotDraft({
    required this.startMinutes,
    required this.endMinutes,
    this.trim = false,
  });

  final int startMinutes;
  final int endMinutes;
  final bool trim;

  int get durationMinutes => endMinutes - startMinutes;

  MowerSlotDraft copyWith({int? startMinutes, int? endMinutes, bool? trim}) {
    return MowerSlotDraft(
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      trim: trim ?? this.trim,
    );
  }

  String get rangeLabel =>
      '${MowerPlanSlot.formatMinutes(startMinutes)}–'
      '${MowerPlanSlot.formatMinutes(endMinutes)}';
}

/// 一整天两个时段的草稿。弹窗一次编辑一天，两个时段在两个标签页里。
class MowerPlanDraft {
  const MowerPlanDraft({
    required this.day,
    required this.one,
    required this.two,
    this.activeSlot = 1,
    this.copyWeek = false,
  });

  /// 那一天还没有任何时段时，弹窗按稿子给的默认值开：时段 1 是 09:00–11:30。
  factory MowerPlanDraft.forDay(
    int day,
    List<MowerPlanSlot> slots, {
    int activeSlot = 1,
  }) {
    MowerSlotDraft draftFor(int slot, MowerSlotDraft fallback) {
      for (final item in slots) {
        if (item.day == day && item.slot == slot) {
          return MowerSlotDraft(
            startMinutes: item.startMinutes,
            endMinutes: item.endMinutes,
            trim: item.trim,
          );
        }
      }
      return fallback;
    }

    return MowerPlanDraft(
      day: day,
      activeSlot: activeSlot,
      one: draftFor(
        1,
        const MowerSlotDraft(startMinutes: 540, endMinutes: 690),
      ),
      two: draftFor(
        2,
        const MowerSlotDraft(startMinutes: 840, endMinutes: 900),
      ),
    );
  }

  final int day;
  final MowerSlotDraft one;
  final MowerSlotDraft two;
  final int activeSlot;

  /// 「复制整周」：保存时把这一天的两个时段铺到七天。
  final bool copyWeek;

  MowerPlanDraft copyWith({
    MowerSlotDraft? one,
    MowerSlotDraft? two,
    int? activeSlot,
    bool? copyWeek,
  }) {
    return MowerPlanDraft(
      day: day,
      one: one ?? this.one,
      two: two ?? this.two,
      activeSlot: activeSlot ?? this.activeSlot,
      copyWeek: copyWeek ?? this.copyWeek,
    );
  }

  /// 两个时段重叠了就返回稿子上那句话，没重叠返回 null。
  ///
  /// 端点相接（前一段 11:30 结束、后一段 11:30 开始）**不算重叠**——设备是按
  /// 区间跑的，闭区间会让「接着干」这种排法永远保存不了。
  String? get overlapMessage {
    if (one.startMinutes < two.endMinutes &&
        two.startMinutes < one.endMinutes) {
      return '时段 2 与时段 1（${one.rangeLabel}）重叠';
    }
    return null;
  }
}

/// 保存成功；[draft] 已经过重叠校验。
class MowerPlanEditSaved {
  const MowerPlanEditSaved(this.draft);

  final MowerPlanDraft draft;
}

/// 保存时撞上重叠：弹窗先关掉，由页面弹「时间段重叠」提示，点「返回修改」再带着
/// 同一份草稿把弹窗开回来——稿子上那张图的背景就是计划页，不是这张弹窗。
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

  MowerSlotDraft get _active => _draft.activeSlot == 1 ? _draft.one : _draft.two;

  void _updateActive(MowerSlotDraft slot) {
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
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
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
                    '编辑周${MowerDemoPlan.dayLabels[_draft.day]}',
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
                              onTap: () => setState(
                                () => _draft = _draft.copyWith(
                                  activeSlot: slot,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _TimePickers(
                      // 换标签页要把滚轮重建：controller 在 initState 里按当时的
                      // 时段定位，不换 key 的话切过去看到的还是上一个时段的数字。
                      key: ValueKey<int>(_draft.activeSlot),
                      slot: _active,
                      onChanged: _updateActive,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MowerColors.brand.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        duration <= 0
                            ? '结束时间需晚于开始时间'
                            : '时长 ${duration ~/ 60} 小时 ${duration % 60} 分',
                        key: const Key('mower-plan-edit-duration'),
                        style: const TextStyle(
                          color: MowerColors.brand,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SheetSwitchCard(
                      title: '修边',
                      subtitle: '此时段执行沿边修剪',
                      value: _active.trim,
                      switchKey: const Key('mower-plan-edit-trim'),
                      onChanged: (value) =>
                          _updateActive(_active.copyWith(trim: value)),
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
}

class _SlotTab extends StatelessWidget {
  const _SlotTab({
    required this.slot,
    required this.active,
    required this.onTap,
  });

  final int slot;
  final bool active;
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
            '时段$slot',
            style: TextStyle(
              color: active ? MowerColors.brand : MowerColors.ink,
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
/// ⚠️ **分钟是 1 分一格，稿子上画的是 10 分一格。** 稿子自己的图表里有 16:23 这种
/// 时间，10 分一格根本选不出来——版式一模一样，只是相邻两行的数字不同。产品若坚持
/// 10 分一档，把 [_minuteStep] 改成 10 并同步图表里的数据即可。
class _TimePickers extends StatefulWidget {
  const _TimePickers({
    required this.slot,
    required this.onChanged,
    super.key,
  });

  final MowerSlotDraft slot;
  final ValueChanged<MowerSlotDraft> onChanged;

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
        Row(
          children: const <Widget>[
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
              // 选中那一行中间的冒号，压在两根滚轮之间。
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
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
