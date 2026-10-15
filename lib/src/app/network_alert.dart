import '../core/config/debug_log_gate.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/network/network_status.dart';
import '../design_system/design_system.dart';
import '../routes/app_routes.dart';
import '../shared/l10n/app_l10n.dart';
import '../shared/widgets/blocking_progress.dart';
import '../state.dart';
import 'app_route_tracker.dart';

/// 登记了「重试时怎么刷新」的页面。见 [NetworkRetryAware]。
final List<NetworkRetryAware> _retryPages = <NetworkRetryAware>[];

/// 页面进页面时要拉数据的，混入它并实现 [reloadForNetworkRetry]：「网络异常」弹窗
/// 点「重试」、网络已经恢复时，**当前页**的这个方法会被调用。
///
/// 没混入的页面，重试时统一重读一次设备列表（已登录时）——状态页、各设置子页的
/// 数据都来自设备快照，这一步就够了。
mixin NetworkRetryAware<T extends StatefulWidget> on State<T> {
  Route<dynamic>? _networkRetryRoute;

  /// 把本页进页面时拉的数据再拉一遍。失败不必抛：页面自己原有的失败处理照常生效，
  /// 还是没网的话会再弹一次「网络异常」。
  Future<void> reloadForNetworkRetry();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _networkRetryRoute = ModalRoute.of(context);
    if (!_retryPages.contains(this)) _retryPages.add(this);
  }

  @override
  void dispose() {
    _retryPages.remove(this);
    super.dispose();
  }
}

/// 全局「网络异常」弹窗（2026-09-15 产品）。
///
/// 标题「网络异常」，正文「当前网络不可用，请检查网络后重试」，按钮「取消」「重试」；
/// 「重试」= 重新刷新当前页面、重新加载数据。
///
/// **什么时候弹**：闪屏结束、回到前台（等 [resumeDelay] 让 Wi-Fi 先连上）、以及
/// 任何一次请求因网络失败（[NetworkStatus.reportFailure]）之后，去 [NetworkStatus.probe]
/// 查一次，查出来没网才弹。一次只弹一个，弹着的时候再来的失败不叠。
///
/// **什么时候不弹**：
/// - 配网动线（[quietRoutes]）：PRODUCT_RULES §1.6 不许 App 自己冒弹框；而且 AP 配网时
///   手机就是挂在没有外网的设备热点上，查出来「没网」是预期内的。
/// - 最上面正盖着别的弹框 / 进度圈：先记下，等它关掉再查。直接盖上去的话，
///   `withBlockingProgress` 收尾时 pop 掉的会是这个弹窗而不是它自己的进度圈。
/// - 刚点过「取消」的 [cancelCooldown] 之内：同一次操作里一起发出去的几条请求会陆续
///   失败，不能用户刚关掉就又冒出来。
///
/// 挂在 `MaterialApp.builder` 上（Navigator 之上），弹窗画在根 Navigator 的 Overlay 里。
class NetworkAlertHost extends StatefulWidget {
  const NetworkAlertHost({
    required this.state,
    required this.routes,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final FlowerpotState state;
  final AppRouteTracker routes;

  /// 闪屏期间为 false；变成 true 的那一刻做冷启动那次检查。
  final bool enabled;
  final Widget child;

  /// 配网动线上的页面，见类注释。
  static const Set<String> quietRoutes = <String>{
    AppRoutes.deviceSearch,
    AppRoutes.pairing,
    AppRoutes.pairingFailure,
    AppRoutes.pairingSuccess,
  };

  /// 回前台后等多久再查：用户多半是去系统设置里开了 Wi-Fi 回来，刚回来那一两秒还在连。
  static const Duration resumeDelay = Duration(seconds: 2);

  /// 点「取消」之后多久内不再弹。
  static const Duration cancelCooldown = Duration(seconds: 3);

  /// 点「重试」后进度圈至少转多久。断网时 DNS 是秒回失败的，没有这一下，弹窗关掉
  /// 又立刻原样弹出来，看着像按钮没反应。
  static const Duration retrySpinner = Duration(milliseconds: 600);

  @override
  State<NetworkAlertHost> createState() => _NetworkAlertHostState();
}

class _NetworkAlertHostState extends State<NetworkAlertHost>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _failures;
  Timer? _resumeTimer;
  Timer? _cooldown;

  /// 一轮「查网 → 弹窗 → 重试」正在进行，期间再来的检查都跳过。
  bool _checking = false;

  /// 查出来没网，但当时盖着别的弹框；等它关掉再查一次。
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.routes.addListener(_routesChanged);
    _failures = NetworkStatus.failures.listen((_) => unawaited(_check()));
    if (widget.enabled) _checkAfterFrame();
  }

  @override
  void didUpdateWidget(covariant NetworkAlertHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.routes, widget.routes)) {
      oldWidget.routes.removeListener(_routesChanged);
      widget.routes.addListener(_routesChanged);
    }
    if (widget.enabled && !oldWidget.enabled) _checkAfterFrame();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    if (lifecycleState != AppLifecycleState.resumed) return;
    // 从后台回来是一次新的机会，不再沿用切走之前那次「取消」。
    _cooldown?.cancel();
    _cooldown = null;
    _resumeTimer = Timer(NetworkAlertHost.resumeDelay, () {
      _resumeTimer = null;
      unawaited(_check());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.routes.removeListener(_routesChanged);
    unawaited(_failures?.cancel());
    _resumeTimer?.cancel();
    _cooldown?.cancel();
    super.dispose();
  }

  void _checkAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  void _routesChanged() {
    if (!_pending || widget.routes.popupOnTop) return;
    _pending = false;
    // 回调发生在 Navigator 刷新路由栈的过程中；_check 在推弹窗之前一定先 await
    // 一次探测，推路由不会落在这次刷新里。
    unawaited(_check());
  }

  bool get _quiet => NetworkAlertHost.quietRoutes.contains(
    widget.routes.currentPage?.settings.name,
  );

  Future<void> _check() async {
    if (!mounted || !widget.enabled || _checking || _cooldown != null) return;
    if (_quiet) return;
    _checking = true;
    try {
      if (await _probe()) return;
      if (!mounted || !widget.enabled || _quiet) return;
      DebugLogGate.log(
        '[network] 网络不可用（${widget.routes.currentPage?.settings.name}）',
      );
      if (widget.routes.popupOnTop) {
        _pending = true;
        return;
      }
      await _alertUntilResolved();
    } finally {
      _checking = false;
    }
  }

  Future<bool> _probe() async {
    try {
      return await NetworkStatus.probe();
    } catch (_) {
      // 判断不了就当有网：宁可少弹一次，也不冤枉用户的网络。
      return true;
    }
  }

  /// 弹「网络异常」。点「重试」先查网：还是不通就再弹，通了就刷新当前页。
  Future<void> _alertUntilResolved() async {
    final l10n = AppL10n(widget.state.language);
    while (mounted) {
      final dialogContext = widget.routes.navigator?.overlay?.context;
      if (dialogContext == null) return;
      final retry = await showAppDialog(
        dialogContext,
        title: l10n.networkErrorTitle,
        message: l10n.networkErrorMessage,
        icon: Icons.wifi_off_rounded,
        cancelLabel: l10n.cancel,
        confirmLabel: l10n.retry,
        barrierDismissible: false,
      );
      if (!mounted) return;
      if (retry != true) {
        _cooldown = Timer(NetworkAlertHost.cancelCooldown, () {
          _cooldown = null;
        });
        return;
      }
      final progressContext = widget.routes.navigator?.overlay?.context;
      if (progressContext == null) return;
      final online = await withBlockingProgress<bool>(
        progressContext,
        () async {
          final results = await Future.wait<bool>(<Future<bool>>[
            _probe(),
            Future<bool>.delayed(NetworkAlertHost.retrySpinner, () => true),
          ]);
          return results.first;
        },
      );
      if (!mounted) return;
      if (online ?? false) {
        // 不等刷新做完：这一轮检查到此结束，刷新途中再有失败要能重新走检查。
        unawaited(_reloadCurrentPage());
        return;
      }
      if (_quiet) return;
    }
  }

  /// 「重新执行刷新当前页面，重新加载数据」。
  Future<void> _reloadCurrentPage() async {
    final page = widget.routes.currentPage;
    final pages = _retryPages
        .where(
          (item) => item.mounted && identical(item._networkRetryRoute, page),
        )
        .toList(growable: false);
    DebugLogGate.log(
      '[network] 重试：刷新 ${page?.settings.name}（登记 ${pages.length} 处）',
    );
    if (pages.isEmpty) {
      if (widget.state.authenticated) await widget.state.reloadDevices();
      return;
    }
    await Future.wait<void>(pages.map(_reloadPage));
  }

  static Future<void> _reloadPage(NetworkRetryAware page) async {
    try {
      await page.reloadForNetworkRetry();
    } catch (error) {
      DebugLogGate.log('[network] 重试刷新失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
