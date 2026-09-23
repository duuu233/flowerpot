import 'package:flutter/material.dart';

import '../../mower_ui.dart';

/// 周排程图表：七列 × 24 小时，时段画成色块。
///
/// **纵轴不是匀的。** 稿子上 08–18 那段拉开（约 26 px/小时），00–08 和 18–24 压扁
/// （约 5–7 px/小时）——白天才是用户真正排任务的区间，夜里那两段只是为了让轴完整。
/// [_anchors] 就是从稿子上量出来的那几个刻度位置，块的上下沿和左边的刻度用的是
/// 同一套映射，所以两边永远对得齐。
///
/// **纵轴高度随屏幕走**（2026-09-23 产品：「根据屏幕自适应一下高度，留有少许的间隔」）：
/// 图表撑满父级给的高度，纵轴拿剩下的那段；锚点按稿子上的**比例**缩放
/// （稿子纵轴 340：08 点在 40、18 点在 300），不再写死 340 像素。
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

  /// 刻度锚点：`分钟 -> 占纵轴的比例`，取自稿子（纵轴 340：0 / 40 / 300 / 340）。
  static const List<(int, double)> _anchors = <(int, double)>[
    (0, 0.0),
    (8 * 60, 40 / 340),
    (18 * 60, 300 / 340),
    (24 * 60, 1.0),
  ];

  /// 稿子上的纵轴高度；父级没给有界高度时（比如放在不限高的滚动里）用它。
  static const double designAxisHeight = 340;

  /// 色块的最小高度：两行时间标签（各 16）加上下内边距就是这么高，
  /// 比它再矮字就叠一起了——稿子上 1 小时的块也是按这个高度画的。
  static const double _minBlockHeight = 38;

  /// 把「当天第几分钟」换算成纵轴上的位置（0…[axisHeight]）。
  static double offsetForMinutes(
    int minutes, [
    double axisHeight = designAxisHeight,
  ]) {
    final value = minutes.clamp(0, 24 * 60);
    for (var i = 0; i < _anchors.length - 1; i++) {
      final (startMinutes, startOffset) = _anchors[i];
      final (endMinutes, endOffset) = _anchors[i + 1];
      if (value <= endMinutes) {
        final ratio = (value - startMinutes) / (endMinutes - startMinutes);
        return (startOffset + (endOffset - startOffset) * ratio) * axisHeight;
      }
    }
    return axisHeight;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 18, 20, 0),
          child: Row(
            children: <Widget>[
              for (var day = 0; day < MowerPlanAxis.dayLabels.length; day++)
                Expanded(
                  child: Text(
                    MowerPlanAxis.dayLabels[day],
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
              for (var day = 0; day < MowerPlanAxis.dayLabels.length; day++)
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
        Flexible(
          child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 10, 20, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
            final axisHeight = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : designAxisHeight;
            return SizedBox(
            height: axisHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                // 左边那列刻度：贴着纵轴外侧，用的是同一套锚点。
                for (final hour in MowerPlanAxis.axisHours)
                  Positioned(
                    left: -30,
                    top: offsetForMinutes(hour * 60, axisHeight) - 7,
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
                    for (var day = 0; day < MowerPlanAxis.dayLabels.length; day++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _DayColumn(
                            axisHeight: axisHeight,
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
            );
            },
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
    required this.axisHeight,
    required this.day,
    required this.enabled,
    required this.slots,
    required this.onEdit,
    required this.onDelete,
  });

  final double axisHeight;
  final int day;
  final bool enabled;
  final List<MowerPlanSlot> slots;

  /// 色块顶边：按起点算；块底会伸出纵轴就往上挪到贴底（见上面 Positioned 的说明）。
  double _blockTop(MowerPlanSlot slot) {
    final top = MowerPlanChart.offsetForMinutes(slot.startMinutes, axisHeight);
    final bottomLimit = axisHeight - _blockHeight(slot, axisHeight);
    return top > bottomLimit ? (bottomLimit < 0 ? 0 : bottomLimit) : top;
  }
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
            // 色块至少 [MowerPlanChart._minBlockHeight] 高（放两行时间）。夜里 18–24 点那段
            // 被压得很扁，21:00–23:00 真按比例只有十几像素，按起点往下画 38 就伸出纵轴底部、
            // 被下面的图例盖住（2026-09-23 产品：「设置到 21:00 到 23:00 在下面就被挡住了」）。
            // 伸出去的就整块往上挪，贴着纵轴底边；时间标签照旧写真实时间。
            top: _blockTop(slot),
            left: 0,
            right: 0,
            child: _SlotBlock(
              axisHeight: axisHeight,
              slot: slot,
              onTap: () => onEdit(slot.day, slot.slot),
              onLongPress: () => onDelete(slot),
            ),
          ),
      ],
    );
  }
}

/// 色块高度：按比例的跨度，不足 [MowerPlanChart._minBlockHeight] 就用它。
double _blockHeight(MowerPlanSlot slot, double axisHeight) {
  final span =
      MowerPlanChart.offsetForMinutes(slot.endMinutes, axisHeight) -
      MowerPlanChart.offsetForMinutes(slot.startMinutes, axisHeight);
  return span < MowerPlanChart._minBlockHeight
      ? MowerPlanChart._minBlockHeight
      : span;
}

class _SlotBlock extends StatelessWidget {
  const _SlotBlock({
    required this.axisHeight,
    required this.slot,
    required this.onTap,
    required this.onLongPress,
  });

  final double axisHeight;
  final MowerPlanSlot slot;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('mower-plan-slot-${slot.day}-${slot.slot}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: _blockHeight(slot, axisHeight),
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
