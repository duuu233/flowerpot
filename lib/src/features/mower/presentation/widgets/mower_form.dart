import 'package:flutter/material.dart';

import '../../mower_ui.dart';

/// 稿子上每一页底部那颗「保存」：335×50、12 圆角、品牌色实心。
class MowerSaveButton extends StatelessWidget {
  const MowerSaveButton({
    required this.onPressed,
    super.key,
    this.label = '保存',
    this.buttonKey,
  });

  final VoidCallback? onPressed;
  final String label;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: MowerColors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: MowerColors.brand.withValues(alpha: .5),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }
}

/// 割草机设置子页（时间同步 / 雨淋设置 / 语言切换）底部的保存按钮条。
///
/// 稿子（561:3154 / 735:2559 / 735:2641）三页的「保存」都在 y=596，按钮底离 home 条 132——
/// 不是贴底。原来贴底（底边距 24）比稿子低约 108，卡片和按钮之间空出一大块。
/// 按屏高等比取这段距离（812 稿子上正好 132），矮屏最少留 24，别把卡片挤进滚动。
class MowerSaveBar extends StatelessWidget {
  const MowerSaveBar({required this.child, super.key});

  static const double designBottomGap = 132;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final gap = (designBottomGap * height / 812).clamp(24.0, designBottomGap);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, gap),
      child: child,
    );
  }
}

/// 「标题 + 副标题 + 开关」的一行。雨淋设置、时间同步两页反复用它。
class MowerSwitchRow extends StatelessWidget {
  const MowerSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
    this.switchKey,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 12),
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Key? switchKey;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: MowerColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle case final String text) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: const TextStyle(
                      color: MowerColors.inkSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Transform.scale(
            scale: .9,
            alignment: Alignment.centerRight,
            // shrinkWrap：不再按 48 的触控高度占位（Transform.scale 只缩画面不缩布局），
            // 否则每行都被撑到 76，稿子 64。
            child: Switch(
              key: switchKey,
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一根滚轮。雨淋设置的「时 / 分」和时段编辑弹层（割草计划、花盆行为页，`time_edit_sheet.dart`）共用它。
///
/// 透视压到最小：这一版设计里滚轮是平的，不要 iOS 那种圆筒感——和花盆那边的休眠
/// 延迟弹窗同一套参数，两处滚起来手感一致。
class MowerWheel extends StatelessWidget {
  const MowerWheel({
    required this.controller,
    required this.count,
    required this.selected,
    required this.onSelected,
    super.key,
    this.itemExtent = 56,
    this.unit,
    this.wheelKey,
    this.activeFontSize = 28,
  });

  final FixedExtentScrollController controller;
  final int count;
  final int selected;
  final ValueChanged<int> onSelected;
  final double itemExtent;

  /// 选中那一格右边跟着的单位（「时」「分」）；null 表示不画。
  final String? unit;
  final Key? wheelKey;
  final double activeFontSize;

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      key: wheelKey,
      controller: controller,
      itemExtent: itemExtent,
      physics: const FixedExtentScrollPhysics(),
      perspective: 0.001,
      diameterRatio: 20,
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) {
          final active = index == selected;
          return Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  index.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: active
                        ? MowerColors.ink
                        : MowerColors.inkTertiary,
                    fontSize: active ? activeFontSize : activeFontSize - 6,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (active && unit != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(
                    unit!,
                    style: const TextStyle(
                      color: MowerColors.ink,
                      fontSize: 15,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 卡片下面那几行灰色说明（区域设置的两条规则）。
class MowerNoteList extends StatelessWidget {
  const MowerNoteList({required this.notes, super.key});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              note,
              style: const TextStyle(
                color: MowerColors.inkSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}
