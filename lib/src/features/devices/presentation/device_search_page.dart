import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import 'pairing_page.dart';

/// First provisioning step: check that a planter is actually waiting to be
/// paired.
///
/// The product has no BLE pairing and the Tuya SDK has no device-scan API, so
/// there is nothing to "discover" in the SDK sense. What can be observed is the
/// access point a planter raises in AP mode, which is what the state's
/// `probeWifi` reads through the `scanWifi` bridge method. A hit is real
/// evidence the device entered pairing state; anything else leaves the decision
/// to the user instead of pretending to have found something.
///
/// 一次扫描只是那一瞬间的快照：用户长按设备让它进入配网状态时，热点往往还没
/// 广播出来。所以这一页在 [DeviceSearchPage.searchWindow] 的窗口里反复扫描，
/// 扫到就直接进下一步。两条出路（「重新扫描」「设备已在配网状态，继续」）**全程
/// 都在**，用户不必等窗口走完；从附近网络里手动挑一个的入口已经下线。
///
/// ⚠️ **扫描节奏受系统配额约束，不能想扫多密就多密。** Android 9 起前台应用每 2
/// 分钟只允许 4 次 `startScan`，超了直接被拒、返回上一次的缓存。2026-09-08 那版
/// 每 2 秒重扫一次，配额在头 20 秒就烧光，之后整个窗口拿到的都是**用户开机之前**
/// 的那份旧缓存——「先进搜索页、再给设备上电」于是永远搜不到。现在改成
/// [_burstScans] 次快扫之后退到 [_pacedGap]，并在被限流时明说正在等配额。
class DeviceSearchPage extends StatefulWidget {
  const DeviceSearchPage({super.key, this.request});

  /// 一轮搜索的时长。
  ///
  /// 3 分钟不是拍脑袋：设备上电、启动、长按进配网、热点广播出来，本身就要几十秒；
  /// 而配额是每 2 分钟 4 次，窗口短于 2 分钟就等不到配额回补。两条出路全程都在，
  /// 窗口长不会把用户困住。
  static const Duration searchWindow = Duration(minutes: 3);

  final PairingRequest? request;

  @override
  State<DeviceSearchPage> createState() => _DeviceSearchPageState();
}

class _DeviceSearchPageState extends State<DeviceSearchPage>
    with SingleTickerProviderStateMixin {
  /// 开头连扫几次，用来抓「设备已经在配网状态」这种常见情形。
  ///
  /// 只花掉系统配额（每 2 分钟 4 次）里的 2 次，剩下的留给后面慢扫。
  static const int _burstScans = 2;

  /// 快扫阶段两次之间的间隔。
  static const Duration _burstGap = Duration(seconds: 3);

  /// 快扫用完之后的节奏。
  ///
  /// 配额是每 2 分钟 4 次 ⇒ 平均 30 秒一次。比这更密只会被拒、拿回同一份旧缓存，
  /// 而且看不出来是旧的——这正是 09-08 那版搜不到设备的原因。
  static const Duration _pacedGap = Duration(seconds: 30);

  late final AnimationController _radarController;

  /// What the page shows: the radar sweep and the "searching" copy.
  bool _scanning = true;

  /// Whether a scan is actually in flight. A second one would only collide with
  /// the state's single-operation guard and report "busy" as a scan failure.
  bool _inFlight = false;
  ActionResult? _result;

  /// 本轮搜索窗口的截止时间，到点之前扫不到就一直重扫。
  Timer? _deadlineTimer;
  bool _windowExpired = false;
  Timer? _retryTimer;

  /// 本轮已经发起过几次扫描，用来决定还在不在快扫阶段。
  int _scanCount = 0;

  /// 上一次扫描是不是被系统限流了（拿回的是旧缓存）。界面据此换一句话。
  bool _throttled = false;

  /// 本轮有没有真的扫成过一次。
  ///
  /// 一次都没真扫过就说「未发现配网中的设备」是撒谎——那句结论只有在真扫过之后
  /// 才成立。
  bool _scannedForReal = false;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _deadlineTimer?.cancel();
    _radarController.dispose();
    super.dispose();
  }

  /// 开始一轮搜索：重置 [DeviceSearchPage.searchWindow] 窗口，立刻扫一次。
  void _scan() {
    _retryTimer?.cancel();
    if (!mounted) return;
    _deadlineTimer?.cancel();
    _windowExpired = false;
    _scanCount = 0;
    _throttled = false;
    _scannedForReal = false;
    _radarController.repeat();
    _deadlineTimer = Timer(DeviceSearchPage.searchWindow, () {
      _windowExpired = true;
      _retryTimer?.cancel();
      if (!mounted) return;
      _radarController.stop();
      setState(() => _scanning = false);
    });
    unawaited(_runScan());
  }

  Future<void> _runScan() async {
    if (!mounted || _inFlight) return;
    _inFlight = true;
    _scanCount++;
    setState(() {
      _scanning = true;
      _result = null;
    });
    final state = FlowerpotScope.of(context);
    final result = await state.probeWifi();
    _inFlight = false;
    if (!mounted) return;
    final scan = state.wifiScan;
    // 被限流 ⇒ 这一轮答的是旧缓存，不能算「扫过了」。有些机型限流时 startScan 照样
    // 返回 true，只是不重扫，所以再看一眼缓存年龄兜底。
    _throttled =
        scan?.throttled == true ||
        (scan?.ageMs != null && scan!.ageMs! > _pacedGap.inMilliseconds);
    if (result.success && !_throttled) _scannedForReal = true;
    // Only a real hotspot advances on its own. Every other outcome keeps the
    // user here with a reason and a way forward.
    final found =
        result.success && (state.wifiScan?.deviceHotspots.isNotEmpty ?? false);
    if (found) {
      // The searching state is kept while the selection page takes over: this
      // page is still on screen during the transition and would otherwise
      // flash the "nothing found" copy on its way out.
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.deviceSelection,
        arguments: widget.request,
      );
      return;
    }
    // 扫描本身成功、只是这一轮没看见设备热点时，窗口没走完就按节奏再扫一次，页面
    // 保持「搜索中」。Wi-Fi 没开、没权限这类失败重扫多少次都是同一个结果，直接报出来。
    final retryable = result.success || result.code == 'wifi_scanning';
    _result = result;
    if (retryable && !_windowExpired) {
      // 头几次快扫抓「设备已经在配网状态」；之后退到 30 秒一次，让系统配额回补。
      // 被限流时同样按慢节奏等——立刻重试只会再被拒一次。
      final gap = (_scanCount < _burstScans && !_throttled)
          ? _burstGap
          : _pacedGap;
      setState(() {});
      _retryTimer = Timer(gap, _runScan);
      return;
    }
    _deadlineTimer?.cancel();
    _radarController.stop();
    setState(() {
      _scanning = false;
      _result = result;
    });
  }

  /// Skips the evidence and goes straight to the Wi-Fi credentials.
  ///
  /// Needed on iOS, where the platform only reports the network the phone is
  /// on, and on any Android whose scan is throttled or refused — provisioning
  /// itself still works there.
  void _continueAnyway() {
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.pairing,
      arguments: PairingArguments(request: widget.request),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = FlowerpotScope.of(context).wifiScan;
    final outcome = _outcome(scan);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '搜索设备', leading: AppBackButton()),
      background: AppPageBackground.account,
      body: ResponsiveContent(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            return Column(
              key: const Key('device-search-content'),
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      compact ? 54 : 84,
                      12,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      children: <Widget>[
                        _SearchRadar(
                          animation: _radarController,
                          spinning: _scanning,
                          // Same artwork as the empty-device screen, so it is
                          // rendered at the same size; the asset carries a lot
                          // of transparent padding, which made 200 look
                          // undersized.
                          size: compact ? 210 : 244,
                        ),
                        SizedBox(height: compact ? 12 : 20),
                        Text(
                          outcome.title,
                          key: const Key('searching-device-label'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: compact ? 24 : 28,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          outcome.message,
                          key: const Key('device-search-message'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        // 两条出路全程都在。窗口从 45 秒拉长到 3 分钟之后，藏起
                        // 按钮等窗口走完就是把用户困在原地——尤其是他明知道设备
                        // 已经在配网状态、只想直接下一步的时候。
                        const SizedBox(height: 20),
                        _SearchActions(
                          scanning: _scanning,
                          onRescan: _scan,
                          onContinue: _continueAnyway,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.pageMargin,
                    0,
                    AppSpacing.pageMargin,
                    compact ? 10 : 18,
                  ),
                  child: const _SearchTipCard(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Copy for the current scan outcome. Kept in one place so the page never
  /// says "no device" when the platform simply cannot answer.
  _SearchOutcome _outcome(WifiScan? scan) {
    if (_scanning) {
      // 被系统限流时别装作还在扫：这几十秒确实什么都没在查，说清楚比转圈诚实。
      if (_throttled) {
        return const _SearchOutcome(
          '搜索附近设备...',
          '系统限制了 Wi-Fi 扫描频率，正在等待下一次扫描。\n设备已进入配网状态的话，可以直接继续下一步。',
        );
      }
      return const _SearchOutcome(
        '搜索附近设备...',
        '请让设备进入配网状态，并确认手机连接的是2.4GHz Wi-Fi',
      );
    }
    final result = _result;
    // 另一次扫描还在跑不是失败：照常显示搜索中，别报「无法扫描附近设备」。
    if (result != null && result.code == 'wifi_scanning') {
      return const _SearchOutcome(
        '搜索附近设备...',
        '请让设备进入配网状态，并确认手机连接的是2.4GHz Wi-Fi',
      );
    }
    if (result != null && !result.success) {
      return _SearchOutcome('无法扫描附近设备', _failureHint(result));
    }
    // 一次都没真扫成过（全程被限流）就不能下「附近没有设备」的结论。
    if (!_scannedForReal) {
      return const _SearchOutcome(
        '无法确认附近设备',
        '系统限制了 Wi-Fi 扫描频率，这段时间拿到的是旧的扫描结果。\n确认设备指示灯已进入配网状态后继续下一步。',
      );
    }
    if (scan == null || scan.networks.isEmpty) {
      // iOS never enumerates access points, and a throttled Android scan can
      // come back empty too. Neither means the planter is missing.
      return const _SearchOutcome(
        '无法列出附近设备',
        '当前系统不提供附近网络列表。\n确认设备指示灯已进入配网状态后继续下一步。',
      );
    }
    return const _SearchOutcome(
      '未发现配网中的设备',
      '请长按设备按键让它进入配网状态后重新扫描。',
    );
  }

  String _failureHint(ActionResult result) => switch (result.code) {
    'wifi_disabled' => '请先打开手机 Wi-Fi 再重新扫描。',
    'location_disabled' => 'Android 9–12 扫描 Wi-Fi 需要打开系统定位开关。',
    'permission_denied' => '扫描需要附近设备/定位权限，请在系统设置中允许后重试。',
    _ => result.message,
  };
}

class _SearchOutcome {
  const _SearchOutcome(this.title, this.message);

  final String title;
  final String message;
}

class _SearchActions extends StatelessWidget {
  const _SearchActions({
    required this.scanning,
    required this.onRescan,
    required this.onContinue,
  });

  final bool scanning;
  final VoidCallback onRescan;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          width: 220,
          height: 46,
          child: FilledButton(
            key: const Key('device-search-rescan'),
            // 搜索中时「重新扫描」只会白白再烧一次系统配额，禁用它；
            // 「设备已在配网状态，继续」全程可点。
            onPressed: scanning ? null : onRescan,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: AppColors.surface,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 17),
            ),
            child: const Text('重新扫描'),
          ),
        ),
        TextButton(
          key: const Key('device-search-continue'),
          onPressed: onContinue,
          child: const Text(
            '设备已在配网状态，继续',
            style: TextStyle(color: AppColors.brandPrimary, fontSize: 15),
          ),
        ),
      ],
    );
  }
}

class _SearchRadar extends StatelessWidget {
  const _SearchRadar({
    required this.animation,
    required this.spinning,
    required this.size,
  });

  final Animation<double> animation;
  final bool spinning;
  final double size;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              child: Image.asset(
                AppAssets.pairingDeviceSearchIllustration,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
            ),
            // The sweep stops with the scan: a wedge still going round after
            // the answer arrived reads as "still searching".
            if (spinning)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) => CustomPaint(
                    painter: _RadarPainter(progress: animation.value),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The sweeping wedge over the search artwork.
///
/// `docs/UI/搜索附近设备.png` shows this wedge, but it is not baked into
/// `pairing_device_search_illustration.png`, so it has to be painted and
/// animated here. It is motion, not an icon — keep it when reconciling this
/// page against the Figma frame.
class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .43;
    final angle = -math.pi / 2 + progress * math.pi * 2;
    final sweep = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius * 1.08),
        angle - .28,
        .56,
        false,
      )
      ..close();
    canvas.drawPath(
      sweep,
      Paint()..color = AppColors.brandPrimary.withValues(alpha: .12),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _SearchTipCard extends StatelessWidget {
  const _SearchTipCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.brandSurfaceAlt,
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 18, 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _QuestionBubble(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '小提示',
                    style: TextStyle(
                      color: AppColors.brandPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '若长时间未搜索到设备，请确认设备已开机\n请将手机靠近设备',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: MediaQuery.sizeOf(context).width < 350
                          ? 12
                          : 13,
                      height: 1.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.helpChatIcon,
      width: 34,
      height: 34,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '提示',
    );
  }
}
