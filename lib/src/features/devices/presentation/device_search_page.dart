import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
/// 一次扫描只是那一瞬间的快照：**设备开机就一定处于可配网状态、不需要任何额外
/// 操作**，但它上电后要过一会儿热点才广播出来。所以这一页在 [DeviceSearchPage.searchWindow] 的窗口里反复扫描，
/// **扫到就把设备直接列在下面，不再跳页**——这一页就是一个监听器，用户看着它
/// 一台台冒出来，点哪台就带哪台进「连接 Wi-Fi」。
///
/// ⚠️ **扫描节奏受系统配额约束，不能想扫多密就多密。** Android 9 起前台应用每 2
/// 分钟只允许 4 次 `startScan`，超了直接被拒、返回上一次的缓存。2026-09-08 那版
/// 每 2 秒重扫一次，配额在头 20 秒就烧光，之后整个窗口拿到的都是**用户开机之前**
/// 的那份旧缓存——「先进搜索页、再给设备上电」于是永远搜不到。现在改成
/// 主动扫描退到 [_forceScanGap]（配额允许的最快节奏），中间的空档由
/// [_cachePollGap] 的读缓存补上——受配额限制的只有 `startScan`，读缓存不受限。
class DeviceSearchPage extends StatefulWidget {
  const DeviceSearchPage({super.key, this.request});

  /// 一轮搜索的时长。
  ///
  /// 3 分钟不是拍脑袋：设备上电、启动到热点广播出来本身就要几十秒；
  /// 而配额是每 2 分钟 4 次，窗口短于 2 分钟就等不到配额回补。两条出路全程都在，
  /// 窗口长不会把用户困住。
  static const Duration searchWindow = Duration(minutes: 3);

  final PairingRequest? request;

  @override
  State<DeviceSearchPage> createState() => _DeviceSearchPageState();
}

class _DeviceSearchPageState extends State<DeviceSearchPage>
    with SingleTickerProviderStateMixin {
  /// 当前平台能不能列出附近的 Wi-Fi。
  ///
  /// **iOS 不能，而且没有替代方案**：系统没有任何公开 API 可以枚举附近热点
  /// （`NEHotspotHelper` 要 Apple 特批的 entitlement，普通 App 拿不到），
  /// `CNCopyCurrentNetworkInfo` 只回答「此刻连着哪个」。所以这一页在 iOS 上
  /// 永远列不出设备——这是平台限制，不是搜不到。
  ///
  /// 但**配网本身不需要先列出来**：iOS 侧用 `NEHotspotConfiguration(ssidPrefix:)`
  /// 按前缀直接连设备热点，系统弹一次确认框即可。加上「设备开机即可配网」这条
  /// 产品事实，iOS 上根本没有要确认的东西，给一个无条件的「下一步」就够了。
  static bool get _canListNetworks =>
      defaultTargetPlatform != TargetPlatform.iOS;

  /// **主动扫描**（`startScan`）的节奏。
  ///
  /// Android 前台每 2 分钟只许 4 次 ⇒ 平均 30 秒一次。比这更密只会被拒、拿回同一份
  /// 旧缓存，而且看不出来是旧的——那正是 09-08 那版搜不到设备的原因。
  static const Duration _forceScanGap = Duration(seconds: 30);

  /// **读缓存**的节奏。
  ///
  /// 受配额限制的只有 `startScan`，读系统的扫描结果缓存不受限、也几乎不耗时。而
  /// 系统自己（连接管理、设置页、别的应用）同样在扫，缓存会被它们刷新。所以这里
  /// 2 秒读一次：设备热点一旦被**任何一次**扫描看到，最多 2 秒就出现在列表里。
  ///
  /// 这一条是「为什么要等一分钟才搜到」的答案：改之前两次主动扫描之间的 30 秒是
  /// 完全瞎的，设备在那 30 秒里冒出来也要等到下一次真扫才看得见。
  static const Duration _cachePollGap = Duration(seconds: 2);

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

  /// 下一次**主动扫描**的定时器（30 秒一次，受系统配额约束）。
  Timer? _forceScanTimer;

  /// **读缓存**的定时器（2 秒一次，不受配额约束）。
  Timer? _pollTimer;

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
    _forceScanTimer?.cancel();
    _pollTimer?.cancel();
    _deadlineTimer?.cancel();
    _radarController.dispose();
    super.dispose();
  }

  /// 开始一轮搜索：重置 [DeviceSearchPage.searchWindow] 窗口，立刻扫一次。
  void _scan() {
    _forceScanTimer?.cancel();
    _pollTimer?.cancel();
    if (!mounted) return;
    _deadlineTimer?.cancel();
    _windowExpired = false;
    _throttled = false;
    _scannedForReal = false;
    _radarController.repeat();
    _deadlineTimer = Timer(DeviceSearchPage.searchWindow, () {
      _windowExpired = true;
      _forceScanTimer?.cancel();
      _pollTimer?.cancel();
      if (!mounted) return;
      _radarController.stop();
      setState(() => _scanning = false);
    });
    // 两条线并行：30 秒一次真扫（受配额约束），2 秒一次读缓存（不受约束）。
    _pollTimer = Timer.periodic(_cachePollGap, (_) => unawaited(_pollCache()));
    unawaited(_runScan());
  }

  /// 读一次系统的扫描缓存。不调 `startScan`，不占配额，几乎不耗时。
  ///
  /// 真扫在跑时跳过：`probeWifi` 有重入保护，这时调只会拿回一条
  /// `wifi_scanning` 的失败，白白把界面状态搅乱。
  Future<void> _pollCache() async {
    if (!mounted || _inFlight || _windowExpired) return;
    _inFlight = true;
    try {
      await FlowerpotScope.of(context).probeWifi(refresh: false);
    } finally {
      _inFlight = false;
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _runScan() async {
    if (!mounted || _inFlight) return;
    _inFlight = true;
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
    //
    // ⚠️ 这个判断只在**主动扫描**之后做。读缓存那条路本来就不刷新缓存，`ageMs`
    // 偏大是常态，拿它判限流会把每次读缓存都误判成被限流。
    _throttled =
        scan?.throttled == true ||
        (scan?.ageMs != null && scan!.ageMs! > _forceScanGap.inMilliseconds);
    if (result.success && !_throttled) _scannedForReal = true;
    // Only a real hotspot advances on its own. Every other outcome keeps the
    // user here with a reason and a way forward.
    // 2026-09-10 起不再自动跳页：扫到什么就画在下面，由用户点。自动跳走会把
    // 「还有第二台正在冒出来」这件事整个吃掉，用户也没机会确认自己点的是哪台。
    // 扫描本身成功、只是这一轮没看见设备热点时，窗口没走完就按节奏再扫一次，页面
    // 保持「搜索中」。Wi-Fi 没开、没权限这类失败重扫多少次都是同一个结果，直接报出来。
    final retryable = result.success || result.code == 'wifi_scanning';
    _result = result;
    if (retryable && !_windowExpired) {
      // 主动扫描固定 30 秒一次——那是配额允许的最快节奏，快了只会被拒。中间的
      // 空档由 2 秒一次的读缓存补上，不必也不该在这里缩短间隔。
      setState(() {});
      _forceScanTimer = Timer(_forceScanGap, () => unawaited(_runScan()));
      return;
    }
    _deadlineTimer?.cancel();
    _pollTimer?.cancel();
    _radarController.stop();
    setState(() {
      _scanning = false;
      _result = result;
    });
  }

  /// 点中某台设备：带着它的热点名进「连接 Wi-Fi」。
  void _openPairing(WifiNetwork hotspot) {
    Navigator.pushNamed(
      context,
      AppRoutes.pairing,
      arguments: PairingArguments(
        request: widget.request,
        hotspotSsid: hotspot.ssid,
      ),
    );
  }

  /// iOS 专用的下一步：不带热点名，直接进「连接 Wi-Fi」。
  ///
  /// 不是「确认设备已在配网状态」那种按钮——设备开机就一定可配网，没有要用户
  /// 确认的东西；这只是 iOS 列不出设备时唯一的入口。
  void _continueWithoutList() {
    Navigator.pushNamed(
      context,
      AppRoutes.pairing,
      arguments: PairingArguments(request: widget.request),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = FlowerpotScope.of(context).wifiScan;
    final hotspots = scan?.deviceHotspots ?? const <WifiNetwork>[];
    final outcome = _outcome(scan, hotspots);
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
                            fontSize: outcome.compactTitle
                                ? (compact ? 18 : 20)
                                : (compact ? 24 : 28),
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
                        // 找到的设备直接列在下面，边扫边冒出来。
                        if (hotspots.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 20),
                          _FoundDeviceList(
                            hotspots: hotspots,
                            onSelected: _openPairing,
                          ),
                        ],
                        // iOS 列不出设备，「下一步」全程都在——那是它唯一的
                        // 入口，让用户干等一轮窗口没有任何意义。
                        //
                        // 能列设备的平台上，「重新扫描」**只在搜完一轮、一台都
                        // 没搜到时**才出现：搜索中它点了也只是白烧一次系统配额，
                        // 已经搜到设备时用户要点的是那台设备、不是再扫一遍。
                        if (!_canListNetworks) ...<Widget>[
                          const SizedBox(height: 20),
                          _SearchActions(onContinue: _continueWithoutList),
                        ] else if (!_scanning && hotspots.isEmpty) ...<Widget>[
                          const SizedBox(height: 20),
                          _SearchActions(onRescan: _scan),
                        ],
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
  _SearchOutcome _outcome(WifiScan? scan, List<WifiNetwork> hotspots) {
    // 已经找到设备时，标题就该讲这件事，而不是继续报「搜索中」。
    if (hotspots.isNotEmpty) {
      return _SearchOutcome(
        '发现 ${hotspots.length} 台设备',
        _scanning ? '点击下方设备继续配网，仍在继续搜索…' : '点击下方设备继续配网。',
        compactTitle: true,
      );
    }
    if (_scanning) {
      // 被系统限流时别装作还在扫：这几十秒确实什么都没在查，说清楚比转圈诚实。
      if (_throttled) {
        return const _SearchOutcome(
          '搜索附近设备...',
          '系统限制了 Wi-Fi 扫描频率，正在等待下一次扫描。\n设备开机即可被搜索到，保持开机并靠近手机即可。',
        );
      }
      return const _SearchOutcome(
        '搜索附近设备...',
        '请确认设备已开机，并确认手机连接的是 2.4GHz Wi-Fi',
      );
    }
    final result = _result;
    // 另一次扫描还在跑不是失败：照常显示搜索中，别报「无法扫描附近设备」。
    if (result != null && result.code == 'wifi_scanning') {
      return const _SearchOutcome(
        '搜索附近设备...',
        '请确认设备已开机，并确认手机连接的是 2.4GHz Wi-Fi',
      );
    }
    if (result != null && !result.success) {
      return _SearchOutcome('无法扫描附近设备', _failureHint(result));
    }
    // 一次都没真扫成过（全程被限流）就不能下「附近没有设备」的结论。
    if (!_scannedForReal) {
      return const _SearchOutcome(
        '无法确认附近设备',
        '系统限制了 Wi-Fi 扫描频率，这段时间拿到的是旧的扫描结果。\n请保持设备开机并靠近手机，稍后会自动重试。',
      );
    }
    if (scan == null || scan.networks.isEmpty) {
      // iOS never enumerates access points, and a throttled Android scan can
      // come back empty too. Neither means the planter is missing.
      if (!_canListNetworks) {
        return const _SearchOutcome(
          '本机无法列出附近设备',
          'iOS 不提供附近 Wi-Fi 列表，设备无法在这里列出来。\n设备开机即可配网，直接下一步即可。',
        );
      }
      return const _SearchOutcome(
        '无法列出附近设备',
        '当前系统不提供附近网络列表，无法在这里列出设备。',
      );
    }
    return const _SearchOutcome(
      '未发现设备',
      '请确认设备已开机并靠近手机后重新扫描。',
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
  const _SearchOutcome(this.title, this.message, {this.compactTitle = false});

  final String title;
  final String message;

  /// 标题用小一号的字。
  ///
  /// 「搜索附近设备…」「未发现设备」是这一屏的主标题，28 撑得住；而「发现 N 台
  /// 设备」下面紧跟着设备列表，重点在列表上，同样 28 就显得太大了。
  final bool compactTitle;
}

/// 页面底部那颗按钮：要么「重新扫描」，要么 iOS 上的「下一步」。
///
/// 什么时候画由页面决定（见 `build` 里那段注释），这里只管长什么样。
class _SearchActions extends StatelessWidget {
  const _SearchActions({this.onRescan, this.onContinue})
    : assert(
        (onRescan == null) != (onContinue == null),
        '这颗按钮只会是「重新扫描」或「下一步」其中之一',
      );

  final VoidCallback? onRescan;

  /// 列不出设备的平台（iOS）上的下一步。
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final next = onContinue;
    return SizedBox(
      width: 220,
      height: 46,
      child: FilledButton(
        key: next != null
            ? const Key('device-search-continue')
            : const Key('device-search-rescan'),
        onPressed: next ?? onRescan,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandPrimary,
          foregroundColor: AppColors.surface,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 17),
        ),
        child: Text(next != null ? '下一步' : '重新扫描'),
      ),
    );
  }
}

/// 扫到的设备热点，直接列在搜索页上。
///
/// 2026-09-10 之前这一步是跳到「选择设备」页；跳走会把「还有第二台正在冒出来」
/// 整个吃掉，用户也没机会确认自己点的是哪台。现在边扫边往下加。
class _FoundDeviceList extends StatelessWidget {
  const _FoundDeviceList({required this.hotspots, required this.onSelected});

  static const listKey = Key('device-search-found-list');

  final List<WifiNetwork> hotspots;
  final ValueChanged<WifiNetwork> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: listKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < hotspots.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: 10),
          _FoundDeviceTile(
            index: index,
            hotspot: hotspots[index],
            onTap: () => onSelected(hotspots[index]),
          ),
        ],
      ],
    );
  }
}

class _FoundDeviceTile extends StatelessWidget {
  const _FoundDeviceTile({
    required this.index,
    required this.hotspot,
    required this.onTap,
  });

  final int index;
  final WifiNetwork hotspot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('device-search-found-$index'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.wifi_tethering,
                size: 22,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hotspot.ssid,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
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
