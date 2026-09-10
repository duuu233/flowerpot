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
/// **扫到就把设备列在下面，并自动带着它进下一步**——2026-09-10 产品口径：整个
/// 配网流程只留一步要用户操作（输 Wi-Fi 密码），选设备这一步不该让用户自己点。
/// **设备由用户手动选**：列表里每行一颗「连接」按钮，点了才进「连接 Wi-Fi」。
/// 2026-09-10 短暂试过「扫到就自动连热点并带走」，产品明确要求改回手动——那个连接会弹
/// 系统入网授权框，自己冒出来时用户完全不知道发生了什么；由用户点触发，框出现在他刚
/// 表达意图的那一刻，体验完全不同。
///
/// ⚠️ **扫描节奏受系统配额约束，不能想扫多密就多密。** Android 9 起前台应用每 2
/// 分钟只允许 4 次 `startScan`，超了直接被拒、返回上一次的缓存。2026-09-08 那版
/// 每 2 秒重扫一次，配额在头 20 秒就烧光，之后整个窗口拿到的都是**用户开机之前**
/// 的那份旧缓存——「先进搜索页、再给设备上电」于是永远搜不到。现在改成
/// 主动扫描退到 [_forceScanGap]（配额允许的最快节奏，且**均匀铺满**整个窗口，
/// 不在开头扎堆），中间的空档由
/// [_cachePollGap] 的读缓存补上——受配额限制的只有 `startScan`，读缓存不受限。
///
/// 还有一条同源的规矩：**进页面先免费读一次缓存，等权限落定再开窗口与真扫节奏**，
/// 见 [_DeviceSearchPageState._startSearchWindow]。首次进入要授权，那个系统框会把
/// 调用挂起几十秒；让挡在它前面的是「读缓存」而不是「真扫」，一次配额都不会浪费，
/// 3 分钟窗口也不会被授权时间吃掉。
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

  /// 主动扫描的**配额**：Android 9（API 28）起，前台应用每 2 分钟只许 4 次
  /// `startScan`（后台每 30 分钟 1 次）。超额时 `startScan` 直接返回 false、不再
  /// 广播，`scanResults` 返回上一次的缓存。
  ///
  /// 见 Android 官方文档「Wi-Fi scanning restrictions」。用户可以在开发者选项里
  /// 关掉「Wi-Fi 扫描节流」（Android 10 起有这个开关），所以开发机上常常测不出来。
  /// iOS 不适用——它根本不提供扫描接口。
  /// 配额本身（4 次 / 2 分钟）只作记录：[_forceScanGap] 就是按它算出来的，改配额
  /// 就要重算那个间隔。
  static const int quotaScans = 4;
  static const Duration quotaWindow = Duration(minutes: 2);

  /// 主动扫描的节奏：**均匀铺满**，间隔取配额允许的最小值。
  ///
  /// 4 次 / 2 分钟 ⇒ 平均 30 秒一次就是上限，再密只会被拒。留 2 秒余量取 32 秒，
  /// 排下来 0 / 32 / 64 / 96 / 128s……：第 5 次发生在 128s，此时滚动窗口
  /// [8s, 128s] 里只有 32/64/96 三次，稳稳在配额内（定时器只会偏慢不会偏快，
  /// 余量只增不减）。
  ///
  /// **为什么不再前置加密。** 上一版排的是 0/6/46/86s——把 4 次里的 2 次押在头
  /// 6 秒，赌「用户进页面时设备早就开着」。这个赌对了一半：设备先开机那条确实第一
  /// 次就扫到；但反过来「先进搜索页、再给设备上电」时，头两次全扫在设备还没广播
  /// 热点的时刻，白扔，真正有用的第一次要等到 46s，错过就是 86s。均匀排之后，
  /// 设备无论什么时候上电，最多 32 秒就被扫到——最坏情况从 86 秒降到 32 秒，
  /// 而「设备先开机」那条仍然是第一次就扫到，没有损失。
  ///
  /// 中间的空档由 [_cachePollGap] 的读缓存补上，那条路不占配额。
  static const Duration _forceScanGap = Duration(seconds: 32);

  /// **读缓存**的节奏。
  ///
  /// 受配额限制的只有 `startScan`，读系统的扫描结果缓存不受限、也几乎不耗时。而
  /// 系统自己（连接管理、设置页、别的应用）同样在扫，缓存会被它们刷新。所以这里
  /// 1 秒读一次：设备热点一旦被**任何一次**扫描看到，最多 1 秒就出现在列表里。
  ///
  /// 这一条是「为什么要等一分钟才搜到」的答案：改之前两次主动扫描之间的几十秒是
  /// 完全瞎的，设备在那几十秒里冒出来也要等到下一次真扫才看得见。
  ///
  /// 1 秒一次是这一页唯一能无代价拉高的频率——真扫的节奏封死在配额上，读缓存
  /// 不是。它决定的是「某一次扫描（我们的或系统的）看到热点」到「列表上出现」
  /// 之间的延迟，拉到 1 秒就基本感知不到了。
  static const Duration _cachePollGap = Duration(seconds: 1);

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

  /// 下一次**主动扫描**的定时器（[_forceScanGap] 一次，受系统配额约束）。
  Timer? _forceScanTimer;

  /// **读缓存**的定时器（[_cachePollGap] 一次，不受配额约束）。
  Timer? _pollTimer;

  /// 「取令牌 + 确认家庭」这两步云端请求的预取。
  ///
  /// ⚠️ **必须在手机还连着路由器的时候跑完。** 涂鸦文档原文：「开始配网之前，
  /// SDK 需要在**联网状态下**从云端获取配网 Token」。配网一开始，SDK 就会把手机
  /// 连到设备热点上，那张网没有外网——那时再去取令牌，只能指望系统回落到蜂窝，
  /// 慢且不一定成。
  ///
  /// 改新流程时把这一步漏了：原流程是 `pairViaHotspot` 内部先取令牌再连热点，
  /// 顺序天然是对的；新流程把取令牌留在了 `apStartPairing` 里，而那时热点已经连上。
  /// 这里补回来——进本页就预取，`apStartPairing` 直接复用缓存的令牌。
  ///
  /// 尽力而为：失败不拦路，`apStartPairing` 仍会自己再取一次，和改之前一样。
  Future<ActionResult>? _prepared;

  /// 本轮是否已经自动跳过一次。
  ///
  /// 只自动一次：用户从「连接 Wi-Fi」返回本页时不该被再弹走一次，那样就退不出来了。
  bool _autoOpened = false;

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
    // 本页不再持有任何热点连接（设备由用户手动点「连接」、热点在配网那一步才连），
    // 所以这里没有网络要还原——那件事由「连接 Wi-Fi」页负责。
    _forceScanTimer?.cancel();
    _pollTimer?.cancel();
    _deadlineTimer?.cancel();
    _radarController.dispose();
    super.dispose();
  }

  /// 开始一轮搜索。
  void _scan() {
    _forceScanTimer?.cancel();
    _pollTimer?.cancel();
    _deadlineTimer?.cancel();
    if (!mounted) return;
    _windowExpired = false;
    _throttled = false;
    _scannedForReal = false;
    _autoOpened = false;
    _radarController.repeat();
    setState(() {
      _scanning = true;
      _result = null;
    });
    unawaited(_startSearchWindow());
  }

  /// 先免费读一次缓存，**等权限落定、页面也真的就绪了**，再开窗口与真扫节奏。
  ///
  /// 这个顺序解决两件事（2026-09-10 产品反馈）：
  ///
  /// 1. **首次进入要授权。** `scanWifi` 在原生侧是要权限的（`NEARBY_WIFI_DEVICES` /
  ///    `ACCESS_FINE_LOCATION`），首次进入会弹系统授权框，而原生把这次调用挂起、
  ///    等用户答完再执行。所以**让挡在权限框前面的那一次是「读缓存」而不是「真扫」**：
  ///    读缓存不占扫描配额（受配额限制的只有 `startScan`），用户点「允许」之前一次真扫
  ///    都不会被浪费；而且 3 分钟窗口与 [_forceScanGap] 的节奏都从授权之后才起算，
  ///    不再被授权那几十秒吃掉。
  /// 2. **非首次进入要「马上搜出来」。** 这一次读缓存几乎不耗时，而系统自己、设置页、
  ///    别的应用一直在扫，缓存里往往**已经**有设备热点了——这时设备会在进页面的瞬间
  ///    就出现，一次 `startScan` 都不用发。
  ///
  /// ⚠️ 不要为了「快一点」在开头塞两次真扫。那是 0/6/46/86s 那版的做法，已经被证明
  /// 会把配额押在设备还没上电的时刻，反而让「先进页面后开机」要等 86 秒。见
  /// [_forceScanGap] 的说明。
  Future<void> _startSearchWindow() async {
    final state = FlowerpotScope.of(context);
    // 趁手机还连着路由器，先把要走云端的两步取回来，别等到连上设备热点没外网了
    // 才去取。只取一次：令牌有效期比一轮搜索窗口长得多，重新扫描不必重取。
    // 它不在原生的权限门禁名单里，和下面的授权互不影响。
    _prepared ??= state.prepareForPairing();
    // ① 免费的一次：读系统扫描缓存。首次进入时的权限框就挡在这一步。
    _inFlight = true;
    try {
      await state.probeWifi(refresh: false);
    } catch (_) {
      // 读缓存失败不下结论——紧接着那次真扫会给出权威结果与原因。
    } finally {
      _inFlight = false;
    }
    if (!mounted || _windowExpired) return;
    setState(() {});
    // 缓存里就有设备的话到此为止，一次真扫都不用发。
    _maybeAutoOpen();
    if (_autoOpened) return;
    // ② 权限落定、页面就绪——从这一刻才开始计窗口、起节奏。
    _deadlineTimer = Timer(DeviceSearchPage.searchWindow, () {
      _windowExpired = true;
      _forceScanTimer?.cancel();
      _pollTimer?.cancel();
      if (!mounted) return;
      _radarController.stop();
      setState(() => _scanning = false);
    });
    // 两条线并行：32 秒一次真扫（受配额约束），1 秒一次读缓存（不受约束）。
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
    _maybeAutoOpen();
  }

  /// 扫到设备就把扫描停下来，等用户在列表里点「连接」。
  ///
  /// ⚠️ **这里不做任何自动连接。** 2026-09-10 产品口径：**设备由用户手动选**——列表里
  /// 每行一颗「连接」按钮，点了才往下走。短暂试过「扫到就自动连热点」，产品明确要求改回
  /// 手动：那个连接会弹系统入网授权框，自己冒出来的时候用户完全不知道发生了什么；
  /// 由用户点按钮触发，框出现在他刚表达意图的那一刻，体验完全不同。
  ///
  /// 扫到之后扫描线全部停掉——目标已经在眼前了，再扫只是白烧系统配额。
  void _maybeAutoOpen() {
    if (_autoOpened || !mounted) return;
    final hotspots =
        FlowerpotScope.of(context).wifiScan?.deviceHotspots ??
        const <WifiNetwork>[];
    if (hotspots.isEmpty) return;
    _forceScanTimer?.cancel();
    _pollTimer?.cancel();
    _deadlineTimer?.cancel();
    _radarController.stop();
    setState(() {
      _autoOpened = true;
      _scanning = false;
    });
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
    _maybeAutoOpen();
    if (_autoOpened) return;
    if (retryable && !_windowExpired) {
      // 均匀 32 秒一次——排下来 0/32/64/96/128s，任意 2 分钟窗口里都不超过配额的
      // 4 次。中间的空档由读缓存补上，那条不占配额。
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

  /// 带着这台设备进「连接 Wi-Fi」。
  /// 带着这台设备进「连接 Wi-Fi」。
  ///
  /// `deviceName` 也一起带过去：用户没有点过「确认连接这台」，那么连接的是哪台
  /// 必须在下一页上写清楚，否则整条流程就成了黑箱。设备名就用热点名——AP 模式下
  /// App 能拿到的就这一个标识。
  void _openPairing(WifiNetwork hotspot) {
    Navigator.pushNamed(
      context,
      AppRoutes.pairing,
      arguments: PairingArguments(
        request: widget.request,
        hotspotSsid: hotspot.ssid,
        deviceName: hotspot.ssid,
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
        // 设备本身不联网，所以下一步是给它配一个 Wi-Fi；这里先说清要点哪个按钮。
        '点设备右侧的「连接」，然后选择要让它加入的 Wi-Fi 并输入密码。',
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
              // 一颗明确的「连接」，而不是一个箭头：这一步是**用户手动选设备**
              // （2026-09-10 产品口径），按钮比箭头更说明"点了会发生什么"。
              // 整行也照旧可点，两者同一个动作。
              FilledButton(
                key: Key('device-search-connect-$index'),
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(68, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: AppColors.surface,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 14),
                ),
                child: const Text('连接'),
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
