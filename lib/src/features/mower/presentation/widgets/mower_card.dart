import 'package:flutter/material.dart';

import '../../mower_ui.dart';

/// 割草机那套图里反复出现的那张卡：半透明白 + 一层很淡的品牌色投影 + 16 圆角。
///
/// 设置列表、设备参数、今日计划、周排程图表、消息卡……版式各不相同，但外壳是同一个，
/// 所以只写一遍。
class MowerCard extends StatelessWidget {
  const MowerCard({
    required this.child,
    super.key,
    this.padding = EdgeInsets.zero,
    this.radius = 16,
    this.color = MowerColors.cardFill,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: border,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: MowerColors.cardShadow,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 卡片里两行之间那条线：稿子上它左右各留 16，不是通栏。
class MowerRowDivider extends StatelessWidget {
  const MowerRowDivider({super.key, this.indent = 16});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent),
      child: const ColoredBox(
        color: MowerColors.divider,
        child: SizedBox(height: 1, width: double.infinity),
      ),
    );
  }
}
