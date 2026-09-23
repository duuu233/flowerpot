import 'package:flutter/widgets.dart';

/// 全局按设计稿比例缩放（2026-09-23 产品：「现在反馈都是整体偏小，能按比例检查所有页面吗，
/// 尽量和 UI 图呈现的比例保持一致」）。
///
/// ## 为什么整体偏小
///
/// 设计稿按 **375 宽**画，页面里的字号、间距、图标、卡片尺寸都是这个宽度下的数；Flutter 按逻辑像素
/// 原样画。常见安卓机的逻辑宽度是 390~412，同一个 263 的电量环放在 412 宽的屏上，占屏比例就比稿子小
/// 一截——**每一页都是这样**，之前是哪页报小改哪页，永远改不完。
///
/// ## 做法
///
/// 手机宽度（[minWidth]~[maxWidth]）时，让整个 App 在**375 宽**的坐标系里排版，再整体等比缩放到
/// 实际宽度：`MediaQuery` 的尺寸 / 安全区 / 键盘高度按同一比例换算（页面拿到的就是「375 宽的屏」），
/// `devicePixelRatio` 乘上比例（图片按放大后的清晰度取），外面用 [FittedBox] 放大。命中测试、文本
/// 输入法定位都跟着变换走，页面代码不用改。平板等更宽的屏不缩放（会被放得过大）。
///
/// ⚠️ 用例里默认关着（`test/flutter_test_config.dart`）：既有用例按具体尺寸断言；专门验它的用例自己打开。
class DesignScale extends StatelessWidget {
  const DesignScale({required this.child, super.key});

  final Widget child;

  /// 设计稿宽度。
  static const double designWidth = 375;

  /// 只对手机宽度生效。
  static const double minWidth = 300;
  static const double maxWidth = 480;

  /// 总闸（不是 `const`：用例要能两头都验，改过在 `tearDown` 里 [reset]）。
  static bool enabled = true;
  static void reset() => enabled = true;

  /// 这个屏宽下的缩放比例；不缩放返回 1。
  static double scaleFor(double width) {
    if (!enabled || width < minWidth || width > maxWidth) return 1;
    return width / designWidth;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = scaleFor(media.size.width);
    if ((scale - 1).abs() < .005) return child;
    final logical = Size(designWidth, media.size.height / scale);
    return MediaQuery(
      data: media.copyWith(
        size: logical,
        devicePixelRatio: media.devicePixelRatio * scale,
        padding: media.padding / scale,
        viewPadding: media.viewPadding / scale,
        viewInsets: media.viewInsets / scale,
        systemGestureInsets: media.systemGestureInsets / scale,
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: logical.width,
          height: logical.height,
          child: child,
        ),
      ),
    );
  }
}
