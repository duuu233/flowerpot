import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';

/// APP 启动页（冷启动闪屏）。
///
/// 由根组件 `FlowerpotApp` 在冷启动时先展示本页一小段时间，再切到登录页或主
/// 壳层。结构、动画时长与曲线与兄弟项目 BoltStar 的启动页保持一致，只有品牌
/// 内容和取色换成本项目的设计令牌。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  /// 启动页是否画 logo / 字标 / 标语那一组品牌内容。
  ///
  /// 2026-09-10 产品要求先只留背景图，置为 false；要恢复就把它改回 true。
  static const bool _showBranding = false;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 背景走 AppPageBackground.home，和主壳层是同一套绘制（渐变打底 + bg01
    // 按 fitWidth 顶部对齐）。这里若自己写一份 BoxFit.cover，切场时底图那圈
    // 轨道会明显位移——两边必须逐像素一致，交叉淡入才看不出接缝。
    return AppPageScaffold(
      key: const Key('splash-page'),
      background: AppPageBackground.home,
      useSafeArea: false,
      body: Center(
        child: _showBranding ? _buildBranding() : const SizedBox.shrink(),
      ),
    );
  }

  /// logo + 字标 + 标语那一组品牌内容。
  ///
  /// 2026-09-10 产品要求启动页**先只留背景图**，[_showBranding] 因此是 false，
  /// 这段暂时不画。是「先隐藏」不是删除——代码留在这里，开关改回 true 就恢复
  /// 原样，不必再照着设计稿重排一遍。
  Widget _buildBranding() {
    return FadeTransition(
      opacity: _fade,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Image.asset(
            AppAssets.appLogo,
            width: 92,
            height: 92,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: 'YSplanter',
          ),
          const SizedBox(height: 16),
          // 高度必须写死：只给 width 时，图解码完成前 RenderImage 会按
          // 0 高度参与布局，居中的 Column 会在首帧解码后整体跳一下。
          // 42 = 200 × 78/372，即字标原图 372×78 的等比高度。
          Image.asset(
            AppAssets.ysplanterWordmark,
            width: 200,
            height: 42,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
          const SizedBox(height: 16),
          const Text(
            '您的智能花盆贴心伴侣',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              letterSpacing: 1,
              height: 1.2,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
