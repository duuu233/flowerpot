import 'package:flutter/material.dart';

import '../../mower_demo.dart';

/// 周排程图表：七列 × 24 小时，时段画成色块。
///
/// **纵轴不是匀的。** 稿子上 08–18 那段拉开（约 26 px/小时），00–08 和 18–24 压扁
/// （约 5–7 px/小时）——白天才是用户真正排任务的区间，夜里那两段只是为了让轴完整。
/// [_anchors] 就是从稿子上量出来的那几个刻度位置，块的上下沿和左边的刻度用的是
/// 同一套映射，所以两边永远对得齐。
class MowerPlanChart extends StatelessWidget {
  const MowerPlanChart({
    required this.enabledDays,
    required this.slots,
    required this.onToggleDay,
    required this.onEditDay,
    required this.onDeleteSlot,
    super.key,
  });

  final List<bool> enabledDays;
  final List<MowerPlanSlot> slots;
  final ValueChanged<int> onToggleDay;

  /// 点色块（带上那一格的时段号）或点空白（null）都进编辑弹窗。
  final void Function(int day, int? slot) onEditDay;
  final void Function(MowerPlanSlot slot) onDeleteSlot;

  /// 刻度锚点：`分钟 -> 相对纵轴顶端的像素`，取自稿子（card 坐标 74…414）。
  static const List<(int, double)> _anchors = <(int, double)>[
    (0, 0.0),
    (8 * 60, 40.0),
    (18 * 60, 300.0),
    (24 * 60, 340.0),
  ];

  static const double _axisHeight = 340;

  /// 色块的最小高度：两行时间标签（各 16）加上下内边距就是这么高，
  /// 比它再矮字就叠一起了——稿子上 1 小时的块也是按这个高度画的。
  static const double _minBlockHeight = 38;

  /// 把「当天第几分钟」换算成纵轴上的位置（0…[_axisHeight]）。
  static double offsetForMinutes(int minutes) {
    final value = minutes.clamp(0, 24 * 60);
    for (var i = 0; i < _anchors.length - 1; i++) {
      final (startMinutes, startOffset) = _anchors[i];
      final (endMinutes, endOffset) = _anchors[i + 1];
      if (value <= endMinutes) {
        final ratio = (value - startMinutes) / (endMinutes - startMinutes);
        return startOffset + (endOffset - startOffset) * ratio;
      }
    }
    return _axisHeight;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 18, 20, 0),
          child: Row(
            children: <Widget>[
              for (var day = 0; day < MowerDemoPlan.dayLabels.length; day++)
                Expanded(
                  child: Text(
                    MowerDemoPlan.dayLabels[day],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: enabledDays[day]
                          ? MowerColors.brand
                          : const Color(0x662A2B2B),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 7, 20, 0),
          child: ColoredBox(
            color: Color(0x2470AFB5),
            child: SizedBox(height: 1, width: double.infinity),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 9, 20, 0),
          child: Row(
            children: <Widget>[
              for (var day = 0; day < MowerDemoPlan.dayLabels.length; day++)
                Expanded(
                  child: Center(
                    child: _DayCheckbox(
                      day: day,
                      checked: enabledDays[day],
                      onTap: () => onToggleDay(day),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 10, 20, 0),
          child: SizedBox(
            height: _axisHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                // 左边那列刻度：贴着纵轴外侧，用的是同一套锚点。
                for (final hour in MowerDemoPlan.axisHours)
                  Positioned(
                    left: -30,
                    top: offsetForMinutes(hour * 60) - 7,
                    child: SizedBox(
                      width: 24,
                      child: Text(
                        hour.toString().padLeft(2, '0'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: MowerColors.inkSecondary,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: <Widget>[
                    for (var day = 0; day < MowerDemoPlan.dayLabels.length; day++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _DayColumn(
                            day: day,
                            enabled: enabledDays[day],
                            slots: slots
                                .where((slot) => slot.day == day)
                                .toList(growable: false),
                            onEdit: onEditDay,
                            onDelete: onDeleteSlot,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        const _PlanLegend(),
        const SizedBox(height: 12),
        const Text(
          '＋ 点击空白添加 · 点击色块编辑·长按时段删除',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF8C9496), fontSize: 12),
        ),
      ],
    );
  }
}

/// 一天一列：底下是整日的底槽，上面浮着这一天的时段块。
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.enabled,
    required this.slots,
    required this.onEdit,
    required this.onDelete,
  });

  final int day;
  final bool enabled;
  final List<MowerPlanSlot> slots;
  final void Function(int day, int? slot) onEdit;
  final void Function(MowerPlanSlot slot) onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // 底槽：勾上的那几天是淡青，没勾的是灰。点空白处进"新增"。
        Positioned.fill(
          child: GestureDetector(
            key: Key('mower-plan-column-$day'),
            onTap: () => onEdit(day, null),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: enabled
                    ? MowerColors.brand.withValues(alpha: .07)
                    : const Color(0x0A2A2B2B),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        for (final slot in slots)
          Positioned(
            top: MowerPlanChart.offsetForMinutes(slot.startMinutes),
            left: 0,
            right: 0,
            child: _SlotBlock(
              slot: slot,
              onTap: () => onEdit(slot.day, slot.slot),
              onLongPress: () => onDelete(slot),
            ),
          ),
      ],
    );
  }
}

class _SlotBlock extends StatelessWidget {
  const _SlotBlock({
    required this.slot,
    required this.onTap,
    required this.onLongPress,
  });

  final MowerPlanSlot slot;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final span =
        MowerPlanChart.offsetForMinutes(slot.endMinutes) -
        MowerPlanChart.offsetForMinutes(slot.startMinutes);
    return GestureDetector(
      key: Key('mower-plan-slot-${slot.day}-${slot.slot}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: span < MowerPlanChart._minBlockHeight
            ? MowerPlanChart._minBlockHeight
            : span,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: slot.color,
          borderRadius: BorderRadius.circular(6),
          border: slot.trim
              ? Border.all(color: MowerColors.trimBorder, width: 2.4)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _SlotLabel(text: slot.startLabel),
            _SlotLabel(text: slot.endLabel),
          ],
        ),
      ),
    );
  }
}

class _SlotLabel extends StatelessWidget {
  const _SlotLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.45),
      ),
    );
  }
}

/// 那一排勾选框：勾上的是实心品牌色，没勾的是白底描边。
class _DayCheckbox extends StatelessWidget {
  const _DayCheckbox({
    required this.day,
    required this.checked,
    required this.onTap,
  });

  final int day;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('mower-plan-day-$day'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked ? MowerColors.brand : Colors.white,
          border: Border.all(
            color: checked
                ? MowerColors.brand
                : MowerColors.brand.withValues(alpha: .35),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: checked
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}

class _PlanLegend extends StatelessWidget {
  const _PlanLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const _LegendItem(color: MowerColors.slotOne, label: '时段一'),
        const SizedBox(width: 20),
        const _LegendItem(color: MowerColors.slotTwo, label: '时段二'),
        const SizedBox(width: 20),
        _LegendItem(
          color: Colors.white,
          label: '修边',
          border: Border.all(color: MowerColors.trimBorder, width: 2),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label, this.border});

  final Color color;
  final String label;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            border: border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: MowerColors.inkSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
