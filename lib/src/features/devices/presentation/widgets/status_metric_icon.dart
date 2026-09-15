import 'package:flutter/material.dart';

/// 状态页摘要卡片底部指标行的圆形图标。
///
/// 大小与位置**以需水状态那张卡为准**（2026-09-15 产品：光照、湿度、温度三页这里的
/// 图标太小、位置不对，需水是正常的）：可见圆底直径 [diameter] = 40；整行在卡片内边距
/// （18）之外再往里收 [rowInsetStart]，图标左沿距卡片外沿 26；图标与文字间距 [gap]。
/// 四张设计稿（`docs/UI/需水状态-水仓水位变化.png`、`光照状态.png`、`空气温度.png`、
/// `相对湿度.png`）这一行的图标大小和位置是同一套。
///
/// **不能直接按 40 画**：`status_*_icon.png` 是给顶部状态行做的，80×80 的图里圆底只占
/// 7–72，四周各有 7 像素透明边，按 40 画出来圆只有 33——这就是「太小」。需水卡用的
/// `water_level_icon` / `water_status_icon` 以及 `metric_*_icon` 是满幅的。满幅资源
/// [transparentInset] 给 0；带透明边的给 [statusIconInset]，图按比例放大，越出 40 的
/// 只是透明边，排版仍按 40 算。
class StatusMetricIcon extends StatelessWidget {
  const StatusMetricIcon({
    required this.assetPath,
    super.key,
    this.transparentInset = 0,
    this.semanticLabel,
  });

  /// 可见圆底的直径。
  static const double diameter = 40;

  /// `status_*_icon.png` 每边透明留边占图边长的比例。
  static const double statusIconInset = 7 / 80;

  /// 指标行在卡片内边距之外左侧再收的量：18 + 8 = 26。
  static const double rowInsetStart = 8;

  /// 两组指标并排时右侧再收的量：18 + 4 = 22，与需水卡一致。
  static const double rowInsetEnd = 4;

  /// 图标与右边文字的间距。
  static const double gap = 8;

  final String assetPath;
  final double transparentInset;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final drawn = diameter / (1 - 2 * transparentInset);
    return SizedBox.square(
      dimension: diameter,
      child: OverflowBox(
        minWidth: drawn,
        maxWidth: drawn,
        minHeight: drawn,
        maxHeight: drawn,
        child: Image.asset(
          assetPath,
          width: drawn,
          height: drawn,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: semanticLabel,
          excludeFromSemantics: semanticLabel == null,
        ),
      ),
    );
  }
}
