import 'package:flutter/material.dart';

import '../../tokens/app_assets.dart';
import '../../tokens/app_colors.dart';

class DateRangeNavigator extends StatelessWidget {
  const DateRangeNavigator({
    required this.label,
    super.key,
    this.onPrevious,
    this.onNext,
    this.onLabelTap,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onLabelTap;

  /// 两个方向都翻不动时，这条就是一个纯标签，不画箭头。
  ///
  /// 典型场景是水位 / 土壤湿度 / 光照的**周、月**：设备的周包、月包只有当期那一份
  /// （规则见 features/devices/models/history_period.dart），左右两边永远都是灰的。
  /// 画两个永远点不动的按钮只会让人反复去点、以为是卡了 —— 周 / 月固定显示当期即可
  /// （2026-09-18 用户要求）。
  ///
  /// 日视图不受影响：它至少有一侧可翻（当期能往前、翻到头能往后），照旧显示两个按钮，
  /// 到边的那一侧仍按原样置灰 —— 灰在这里是有意义的，它告诉用户「这个方向到头了」。
  bool get _hasArrows => onPrevious != null || onNext != null;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: _hasArrows
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.center,
      children: <Widget>[
        if (_hasArrows)
          _NavigationButton(
            assetPath: AppAssets.chevronLeftIcon,
            onPressed: onPrevious,
          ),
        if (onLabelTap == null)
          Text(label, style: Theme.of(context).textTheme.bodyLarge)
        else
          TextButton.icon(
            onPressed: onLabelTap,
            label: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            iconAlignment: IconAlignment.end,
            icon: const Icon(
              Icons.arrow_drop_down_rounded,
              color: AppColors.textPrimary,
            ),
          ),
        if (_hasArrows)
          _NavigationButton(
            assetPath: AppAssets.chevronRightIcon,
            onPressed: onNext,
          ),
      ],
    );
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({required this.assetPath, this.onPressed});

  final String assetPath;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // 稿子（156:5082 / 156:5196 / 156:4814）左右切换是 24 的白色圆（原 40，整行被撑高 16）。
    return IconButton.filled(
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textSecondary,
        fixedSize: const Size.square(24),
        minimumSize: const Size.square(24),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      icon: Image.asset(
        assetPath,
        width: 12,
        height: 12,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}
