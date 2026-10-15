import 'package:flutter/material.dart';

import '../../mower_ui.dart';
import '../../mower_dp.dart';
import 'mower_form.dart';
import 'time_edit_sheet.dart';

/// 编辑弹窗里一整天的草稿（对应 DP101 的一组 11 字节）。
class MowerPlanDraft {
  const MowerPlanDraft({
    required this.day,
    required this.one,
    required this.two,
    this.activeSlot = 1,
    this.edge = false,
    this.copyWeek = false,
    this.oneFromDevice = false,
    this.twoFromDevice = false,
  });

  /// 从 DP 解析出来的那一天开编辑器。
  ///
  /// 那个时段还没排（含长按删掉的）：滚轮停在**默认时间**——时段一 08:30–12:00、时段二 14:00–18:00
  /// （2026-10-08 用户：「删除计划时间后，要默认时间，不是 00」「新建计划给默认时间」）。
  /// 开关仍然**关着**（2026-09-23 产品：「没有数据时不能做假的数据渲染」——当时预填稿子时间又开着，
  /// 点一下保存就把假时段发给了设备）：用户打开开关才算数，关着的空时段不写进 DP101（见 [day0]）。
  factory MowerPlanDraft.forDay(
    int day,
    List<MowerScheduleDay> week, {
    int activeSlot = 1,
  }) {
    final source = day < week.length ? week[day] : const MowerScheduleDay();
    return MowerPlanDraft(
      day: day,
      activeSlot: activeSlot,
      one: source.slotOne ?? defaultOne,
      two: source.slotTwo ?? defaultTwo,
      edge: source.edge,
      oneFromDevice: source.slotOne != null,
      twoFromDevice: source.slotTwo != null,
    );
  }

  /// 还没排的时段一：08:30–12:00，关着。
  static const MowerScheduleSlot defaultOne = MowerScheduleSlot(
    startMinutes: 8 * 60 + 30,
    endMinutes: 12 * 60,
    enabled: false,
  );

  /// 还没排的时段二：14:00–18:00，关着。
  static const MowerScheduleSlot defaultTwo = MowerScheduleSlot(
    startMinutes: 14 * 60,
    endMinutes: 18 * 60,
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

  /// 设备已报过的停用时段不能因为恰好等于编辑器默认时间而被清空。
  final bool oneFromDevice;
  final bool twoFromDevice;

  MowerScheduleSlot get active => activeSlot == 1 ? one : two;

  /// 保存时仅去除从未存在且未改动的停用占位时间。
  /// 设备已报的停用起止即使与默认时间相同，也必须保留，不能凭值猜为空。
  MowerScheduleDay get day0 => MowerScheduleDay(
    slotOne: !oneFromDevice && _untouched(one, defaultOne) ? null : one,
    slotTwo: !twoFromDevice && _untouched(two, defaultTwo) ? null : two,
    edge: edge,
  );

  static bool _untouched(MowerScheduleSlot slot, MowerScheduleSlot fallback) =>
      !slot.enabled &&
      slot.startMinutes == fallback.startMinutes &&
      slot.endMinutes == fallback.endMinutes;

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
    oneFromDevice: oneFromDevice,
    twoFromDevice: twoFromDevice,
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
///
/// 外壳、滚轮、时长条和花盆行为页的时段弹层是同一份（`time_edit_sheet.dart`）。
Future<Object?> showMowerPlanEditSheet(
  BuildContext context, {
  required MowerPlanDraft draft,
}) {
  return showTimeEditSheet<Object?>(
    context,
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
    return TimeEditSheet(
      title: '编辑周${MowerPlanAxis.dayLabels[_draft.day]}',
      titleKey: const Key('mower-plan-edit-title'),
      cancelKey: const Key('mower-plan-edit-cancel'),
      saveKey: const Key('mower-plan-edit-save'),
      onSave: _save,
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
            subtitle: '关闭后该时段不执行割草',
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
                  TimeRangeWheels(
                    key: ValueKey<int>(_draft.activeSlot),
                    startMinutes: _active.startMinutes,
                    endMinutes: _active.endMinutes,
                    onStartChanged: (value) =>
                        _updateActive(_active.copyWith(startMinutes: value)),
                    onEndChanged: (value) =>
                        _updateActive(_active.copyWith(endMinutes: value)),
                  ),
                  const SizedBox(height: 14),
                  // 稿子 673:7897 时长条 36 高（原 56，整张弹层比稿子高约 110，要内部滚动）。
                  // 时长是**端上自己算的**（2026-09-18 用户明确），不是设备给的。
                  // ⚠️ 设备只认 >10 分钟的时段，短了会被丢弃，所以这里直接说出来。
                  TimeDurationBar(
                    text: _durationText(duration),
                    textKey: const Key('mower-plan-edit-duration'),
                    color: duration > 10
                        ? MowerColors.brand
                        : MowerColors.danger,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SheetSwitchCard(
            title: '修边',
            subtitle: '先绕边再割草，当天所有时段生效',
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
            onChanged: (value) =>
                setState(() => _draft = _draft.copyWith(copyWeek: value)),
          ),
        ],
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
