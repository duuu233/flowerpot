import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

/// 小红点：一行里「这儿有新东西」的最轻提示。
///
/// 不带数字、不可点，也不占布局之外的位置——它只是把注意力引到所在的那一行，
/// 真正要做的事仍然在点进去之后。语义标签默认给出，读屏用户否则只会听到一个
/// 没有名字的装饰。
class AppNoticeDot extends StatelessWidget {
  const AppNoticeDot({super.key, this.size = 8, this.semanticLabel = '有新内容'});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      container: semanticLabel != null,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: AppColors.danger,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
