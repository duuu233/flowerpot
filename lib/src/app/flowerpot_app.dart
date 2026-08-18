import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system/design_system.dart';
import '../features/auth/presentation/auth_page.dart';
import '../features/preview/preview_config.dart';
import '../features/shell/presentation/shell_page.dart';
import '../features/splash/presentation/splash_page.dart';
import '../routes/app_routes.dart';
import '../state.dart';
import '../tuya/tuya_repository.dart';
import 'app_theme.dart';

/// 根节点切换动效时长（闪屏 → 登录页/主壳层）。
const Duration kRootTransitionDuration = Duration(milliseconds: 1100);

/// fade-through 时间轴分界：前 35% 旧页退场、后 65% 新页进场。
const double _kRootFadeThroughSplit = 0.35;

/// 新页进场的起始缩放：从 1.04 落回 1.0（出场反向：1.0 推远到 1.04）。
///
/// 用 >1 而不是 Material fadeThrough 标准的 0.92→1.0：这几页都全屏铺底图，
/// 从小于 1 进场会在四周露出下面垫的底图，出现一圈「画中画」边缝；从 1.04
/// 收缩则溢出屏幕外，永远不露边。
const double _kRootEntryScale = 1.04;

/// 根节点切换动效（Material Motion fade-through 的变体）。
///
/// 纯 crossfade 的问题是全程两页同时半透明，画面浑浊且没有空间感。这里改成
/// 两段接力（曲线的 Interval 在 [AnimatedSwitcher] 上配）：
///   0%─35%    旧页淡出，同时轻微推远（1.0→1.04）
///   35%─100%  新页淡入，从 1.04 缩放落位
/// 进出场共用同一个 Tween：出场条目的动画反向跑，自动得到「推远退场」。
Widget _rootTransitionBuilder(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween<double>(begin: _kRootEntryScale, end: 1).animate(animation),
      child: child,
    ),
  );
}

/// 根节点切换的层叠方式：在新旧两页**之下**垫一层不透明背景。
///
/// `home` 底下没有任何东西负责铺底，交叉淡入时两页各自半透明，合成覆盖率不足
/// 1 会透到引擎的黑色底色，表现为切换中间整体压暗一下。垫上与闪屏同一张底图
/// 后，背景层在整个切换过程中恒定，只有前景内容在淡入淡出。
///
/// `previousChildren.isNotEmpty` 恰好等价于「正在切换」，切换结束后这层不再
/// 构建，稳态零开销。
Widget _rootTransitionLayout(
  Widget? currentChild,
  List<Widget> previousChildren,
) {
  return Stack(
    fit: StackFit.expand,
    children: <Widget>[
      if (previousChildren.isNotEmpty) const _RootTransitionBackdrop(),
      ...previousChildren,
      if (currentChild != null) currentChild,
    ],
  );
}

/// 切换期间的兜底背景。
class _RootTransitionBackdrop extends StatelessWidget {
  const _RootTransitionBackdrop();

  @override
  Widget build(BuildContext context) {
    // 只画渐变，不画任何贴图——这正是三个目标页的公共部分：
    // `AppPageBackground.home`（闪屏、主壳层）与 `.account`（登录页）用的是
    // **同一个**渐变，贴图却各是各的（`bg01.png` / `auth_background.png`）。
    // 同色渐变按任意 alpha 混合仍是原色，所以垫这一层能保证整个切换过程背景
    // 恒定；若把 bg01 也垫进来，闪屏→登录页时那圈轨道会在退场图之外再叠一份，
    // 中途反而变重。渐变末端是不透明的 canvas，两页半透明时不会露出引擎黑底。
    // 取 home 的渐变而不是照抄一份字面量：splash_page_test 里有一条断言盯着
    // 「home 与 account 的渐变相等」，这个前提被改动打破时测试先红，而不是切
    // 场悄悄变难看。
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppPageBackground.home.gradient),
      child: const SizedBox.expand(),
    );
  }
}

class FlowerpotApp extends StatefulWidget {
  const FlowerpotApp({
    super.key,
    this.repository,
    this.splashDuration = const Duration(milliseconds: 1800),
  });

  final TuyaRepository? repository;

  /// How long the cold-start screen stays up at minimum. Tests pass
  /// [Duration.zero] so they do not have to wait it out.
  final Duration splashDuration;

  @override
  State<FlowerpotApp> createState() => _FlowerpotAppState();
}

class _FlowerpotAppState extends State<FlowerpotApp> {
  late final FlowerpotState state = FlowerpotState(
    repository:
        widget.repository ??
        TuyaRepository.create(seedMockDevice: !StaticPreviewConfig.enabled),
  );

  /// Cold-start screen, dismissed once the minimum time has passed *and* the
  /// session has been restored — otherwise a returning user would see the
  /// login page flash before the shell replaces it.
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    // The demo build starts signed out on the login page like the real app;
    // it only differs in that the mock backend owns no planter yet.
    unawaited(_dismissSplashWhenReady());
  }

  Future<void> _dismissSplashWhenReady() async {
    try {
      await Future.wait<void>(<Future<void>>[
        Future<void>.delayed(widget.splashDuration),
        state.initialize(),
      ]);
    } catch (error, stackTrace) {
      // initialize() already turns its own failures into state, so nothing is
      // expected here. Report rather than swallow — but still fall through to
      // the finally, because a stuck splash is the one outcome the user cannot
      // recover from.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'flowerpot',
          context: ErrorDescription('while restoring the session on start-up'),
        ),
      );
    } finally {
      if (mounted) setState(() => _showSplash = false);
    }
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return FlowerpotScope(
          state: state,
          child: MaterialApp(
            title: '智能花盆',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            locale: Locale(state.languageCode),
            // The first screen is built here rather than through
            // `initialRoute`, so the splash can be swapped for the real entry
            // point without a route transition. Pushed routes still go through
            // AppRoutes.
            home: AnimatedSwitcher(
              // 只负责冷启动那一次切场：闪屏 → 登录页（新用户）或 → 主壳层
              // （会话已恢复）。登录成功后走的是 AuthPage 里的
              // pushNamedAndRemoveUntil(AppRoutes.shell)，属于路由动画，不经过
              // 这里。fade-through 两段接力：Interval 把出场压在前 35%、进场排
              // 在后 65%，完整推理见 _rootTransitionBuilder。
              duration: kRootTransitionDuration,
              switchInCurve: const Interval(
                _kRootFadeThroughSplit,
                1,
                curve: Curves.easeOutCubic,
              ),
              switchOutCurve: const Interval(
                1 - _kRootFadeThroughSplit,
                1,
                curve: Curves.easeInCubic,
              ),
              transitionBuilder: _rootTransitionBuilder,
              layoutBuilder: _rootTransitionLayout,
              child: _showSplash
                  ? const SplashPage()
                  : state.authenticated
                  ? const AppShell()
                  : const AuthPage(),
            ),
            onGenerateRoute: (settings) => AppRoutes.onGenerateRoute(
              settings,
              authenticated: state.authenticated,
            ),
          ),
        );
      },
    );
  }
}

class FlowerpotScope extends InheritedNotifier<FlowerpotState> {
  const FlowerpotScope({
    required FlowerpotState state,
    required super.child,
    super.key,
  }) : super(notifier: state);

  static FlowerpotState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FlowerpotScope>();
    assert(scope != null, 'FlowerpotScope is missing above this context.');
    return scope!.notifier!;
  }
}
