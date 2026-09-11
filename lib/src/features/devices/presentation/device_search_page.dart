import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
// `FlowerpotState`：连上热点之后本页就持有一条连接，dispose / paused 里要还原网络，
// 那时已经不能查 InheritedWidget，所以得按类型留引用。
import '../../../state.dart';
import '../../../tuya/tuya_models.dart';
import '../pairing_gate.dart';
import 'pairing_page.dart';
import 'widgets/pairing_progress_view.dart';

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
/// 搜索页的路由参数。
///
/// 原来这一页直接收一个裸 [PairingRequest]；[preferHotspot] 出现之后需要两样东西，
/// 所以包一层。老调用点传裸 request 仍然可用（见 `AppRoutes._deviceSearchPage`）。
class DeviceSearchArguments {
  const DeviceSearchArguments({this.request, this.preferHotspot = false});

  final PairingRequest? request;

  /// **这一轮直接用 Wi-Fi 热点方式找设备，别开蓝牙那条。**
  ///
  /// 唯一的来路是失败页那颗「改用热点方式配网」：蓝牙已经试过并且没成，再自动优选
  /// 到蓝牙上只会让用户在同一个坑里再等一轮。
  final bool preferHotspot;
}

class DeviceSearchPage extends StatefulWidget {
  const DeviceSearchPage({super.key, this.request, this.preferHotspot = false});

  /// 一轮搜索的时长。
  ///
  /// 3 分钟不是拍脑袋：设备上电、启动到热点广播出来本身就要几十秒；
  /// 而配额是每 2 分钟 4 次，窗口短于 2 分钟就等不到配额回补。两条出路全程都在，
  /// 窗口长不会把用户困住。
  static const Duration searchWindow = Duration(minutes: 3);

  final PairingRequest? request;

  /// 见 [DeviceSearchArguments.preferHotspot]。
  final bool preferHotspot;

  @override
  State<DeviceSearchPage> createState() => _DeviceSearchPageState();
}

class _DeviceSearchPageState extends State<DeviceSearchPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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

  /// 给**涂鸦 SDK** 留出来的扫描次数。
  ///
  /// `startScan` 的配额是**按 UID 算的**——涂鸦 SDK 就跑在我们进程里，和搜索页共用同一份
  /// 4 次 / 2 分钟。2026-09-11「连接设备卡几十秒」就是这么来的：搜索页两分钟把 4 次用满，
  /// 用户紧接着点「连接」，SDK 想扫一次去找设备热点却被限流，**它在等一个永远不会来的
  /// 扫描结果广播**，一直挂到超时。
  ///
  /// 当时按 2 次预留，因为那条动线里 `queryDeviceConfigState`（涂鸦「新流程」）必须自己
  /// 扫描找热点。**那条路已经整条删掉**（见 [FlowerpotState.pairViaHotspot]），现在剩下的
  /// 动线里没有东西会用 `startScan`：
  ///
  /// - 连热点走 `WifiNetworkSpecifier` + `requestNetwork`，匹配网络由**系统进程**去扫，
  ///   不记在我们的 UID 上；
  /// - `pairWifiDevice`（标准 AP）在手机已经挂到热点上之后只跟 `192.168.176.1` 通讯。
  ///
  /// 2026-09-11 晚：预留从 1 降到 **0**。理由是动线里**再没有任何东西会在我们 UID 上
  /// `startScan`**——连热点要么走 `WifiNetworkSpecifier`（匹配网络由**系统进程**扫）、
  /// 要么走 `openWifiPanel`（用户手动连），`pairWifiDevice`（标准 AP）在手机已上热点后只跟
  /// `192.168.176.1` 开 socket，都不扫。所以 4 格全给搜索页，真扫到达系统允许的最快节奏。
  ///
  /// ⚠️ 将来若重新引入任何「SDK 自己扫描找设备」的配网路径（如
  /// `queryDeviceConfigState`），**必须把这个值改回 ≥1**，否则会重演 09-11 的
  /// 「连接设备卡几十秒」——SDK 抢不到配额，在等一个永远不来的扫描广播。
  static const int _quotaReservedForSdk = 0;

  /// 搜索页自己能用的真扫次数（每 [quotaWindow] 内）。
  static const int _ownScanBudget = quotaScans - _quotaReservedForSdk;

  /// 两次**主动扫描**之间的间隔：按预算**均匀铺满**整个窗口。
  ///
  /// 由 [_ownScanBudget] 反推：4 次 / 2 分钟 ⇒ 30 秒一次是系统允许的上限（再密只会被拒）。
  /// 留 2 秒余量取 32 秒，排下来 0/32/64/96/128s：第 5 次在 128s，此时滚动窗口 [8s,128s]
  /// 里只有 32/64/96 三次，稳稳在配额内。**改 [_quotaReservedForSdk] 就要跟着改这里。**
  ///
  /// **为什么是均匀铺满，而不是前面加密。** 早先排的是 0/6/46/86s——把 4 次里的 2 次押在
  /// 头 6 秒，赌「用户进页面时设备早就开着」。这个赌对了一半：设备先开机那条确实第一次就
  /// 扫到；但反过来「先进搜索页、再给设备上电」时，头两次全扫在设备还没广播热点的时刻，
  /// 白扔，真正有用的第一次要等到 46s，错过就是 86s。均匀排之后设备无论什么时候上电，
  /// 最多一个间隔就被扫到，而「设备先开机」那条仍然是第一次就扫到，没有损失。
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

  /// 本轮自己发起过的真扫时刻，只保留滚动窗口内的。
  ///
  /// 光靠定时器间隔不够稳：用户点「重新扫描」、页面重进都会额外发一次。这里如实记账，
  /// 超预算就不发——**宁可慢，也要给 SDK 留出配额**（见 [_quotaReservedForSdk]）。
  final List<DateTime> _ownScans = <DateTime>[];

  /// 现在还能不能发一次真扫。
  bool get _canForceScan {
    final now = DateTime.now();
    _ownScans.removeWhere((at) => now.difference(at) >= quotaWindow);
    return _ownScans.length < _ownScanBudget;
  }

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
  /// 现在的动线是「搜索页先连热点 → 下一页输密码 → `pairViaHotspot` 下发凭据」，连热点
  /// 发生在取令牌**之前**，所以令牌必须在进本页时就预取好。
  ///
  /// 尽力而为：失败不拦路，`pairViaHotspot` 第①步仍会自己再取一次。
  Future<ActionResult>? _prepared;

  /// 本轮是否已经自动跳过一次。
  ///
  /// 只自动一次：用户从「连接 Wi-Fi」返回本页时不该被再弹走一次，那样就退不出来了。
  bool _autoOpened = false;

  /// 上一次扫描是不是被系统限流了（拿回的是旧缓存）。界面据此换一句话。
  bool _throttled = false;

  /// 正在连某一行设备的热点时，那一行的下标；空闲时为 null。
  ///
  /// 点「连接」是**真的去连**（见 [_connectAndOpen]），所以要有进行中的态，也要挡住
  /// 期间的重复点击。
  int? _connectingIndex;

  /// 正在等用户在**系统**入网授权框上点「连接」。
  ///
  /// 只在这一小段为真：`connectDeviceHotspot` 发出去、用户还没处理完。进度页据它把
  /// 副标题换成"系统会问一次…"，用户点完框、框消失时看到的就不是一个没头没尾的转圈。
  bool _awaitingConsent = false;

  /// 连设备失败的完整原因（含原始码、用时、当时连的网络），画在页面上。
  ///
  /// 长按可复制——排查时要的就是这一整段原文。
  String? _connectError;

  /// 连过热点的那个状态对象，给 [dispose] / [didChangeAppLifecycleState] 还原网络用。
  FlowerpotState? _hotspotState;

  /// 搜了这么久还一台都没有，就把「设备可能已经退出配网状态」这条说出来，并且**立刻**
  /// 把动作交给用户，不要让他等满整个 3 分钟窗口。
  ///
  /// 为什么是这个数：进页面立刻真扫一次，第二次真扫在 [_forceScanGap]（32 秒），中间一直
  /// 在读缓存（系统自己、别的应用扫出来的结果都会被捡到）。取**第二次真扫之后**——两次
  /// 真扫加一路读缓存都没有，才值得提醒用户设备可能已经退出配网状态。再往前提会在设备
  /// 正常启动的那几十秒里误报，也会在第二次真扫出结果之前就先喊。
  static const Duration _stalledAfter = Duration(seconds: 40);

  Timer? _stalledTimer;

  /// **给蓝牙的抢答窗口。**
  ///
  /// 双模是主路径，可 Wi-Fi 那条**会先答**：进页面第一件事就是读系统扫描缓存（不占
  /// 配额、几乎不耗时），而缓存里往往**已经**有设备热点了——系统自己、设置页、别的应用
  /// 一直在扫。那一瞬间列表先画出 AP 那一行，用户一点，整条流程就掉进了更差的那条：
  /// 多一个系统入网授权框、手机还要离开路由器、还得先拿到确切热点名。
  ///
  /// 所以扫描开始后的这几秒里，只要蓝牙**还在扫**，就先不画 Wi-Fi 热点。BLE 广播是
  /// 设备主动周期性发的，双模设备通常一两秒就能扫到；给到 4 秒还没有，多半就不是双模
  /// 设备（或蓝牙这条不通），那时再回落到热点列表——4 秒换一次"走对路"，值。
  ///
  /// ⚠️ 蓝牙用不了（没硬件、开关关着、包里没模块）时**根本不进这个窗口**：
  /// [_bleScanStartedAt] 只在真的扫起来了才置位。
  static const Duration _bleGrace = Duration(seconds: 4);

  /// 本轮 BLE 扫描真正跑起来的时刻；没跑起来就是 null。
  DateTime? _bleScanStartedAt;

  /// 抢答窗口到点后重画一次。
  ///
  /// 没有它的话，窗口期内如果 BLE 一台都没扫到、Wi-Fi 也没有新结果，就没有任何东西
  /// 触发重建——热点列表会一直被压着不显示，看起来就是"搜不到"。
  Timer? _bleGraceTimer;

  /// 到点了还一台都没搜到。
  bool _stalled = false;

  /// 本轮有没有真的扫成过一次。
  ///
  /// 一次都没真扫过就说「未发现配网中的设备」是撒谎——那句结论只有在真扫过之后
  /// 才成立。
  bool _scannedForReal = false;

  /// 开过 BLE 扫描的那个状态对象，[dispose] 里用来停扫（那时已不能查 InheritedWidget）。
  ///
  /// **一定要停**：扫描回调在原生侧握着 Activity，而且在真的耗电。
  FlowerpotState? _bleState;

  /// 本页这一刻列出来的设备。**BLE 优先**，见 [_foundDevices]。
  ///
  /// 存一份是因为「点了第几行」要能对回具体设备：BLE 列表随扫描一直在变，
  /// 光靠下标在两帧之间可能指向另一台。
  List<_FoundDevice> _found = const <_FoundDevice>[];

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // 切到后台就把手机的 Wi-Fi 还回去：连上设备热点之后手机是没有外网的，不还原等于
    // 把用户撂在那儿直到进程被杀。
    //
    // ⚠️ 正在连的那一刻不能放：系统入网授权框会把本页 pause，这时放等于自己把刚发出去
    // 的请求撤回。`_connectingIndex != null` 正好覆盖那一段。
    if (lifecycleState != AppLifecycleState.paused) return;
    if (_connectingIndex != null) return;
    final state = _hotspotState;
    if (state == null) return;
    _hotspotState = null;
    unawaited(state.releaseDeviceHotspot());
  }

  @override
  void dispose() {
    // ⚠️ 离开本页一定要把手机的 Wi-Fi 还回去：用户点过「连接」之后本页就持有一条
    // 设备热点连接，那期间手机没有外网。无条件调、幂等——漏放的代价（用户莫名断网）
    // 远大于多调一次。配网期间本页不会被 dispose（下一页是 push 上去的）。
    final hotspotState = _hotspotState;
    _hotspotState = null;
    if (hotspotState != null) unawaited(hotspotState.releaseDeviceHotspot());
    // BLE 扫描同理：不停的话它会一直扫到超时，还握着这个 Activity。
    final bleState = _bleState;
    _bleState = null;
    if (bleState != null) unawaited(bleState.stopBleDiscovery());
    WidgetsBinding.instance.removeObserver(this);
    _forceScanTimer?.cancel();
    _pollTimer?.cancel();
    _deadlineTimer?.cancel();
    _stalledTimer?.cancel();
    _bleGraceTimer?.cancel();
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
    _stalledTimer?.cancel();
    _stalled = false;
    _bleGraceTimer?.cancel();
    _bleScanStartedAt = null;
    // ⚠️ **不清 `_ownScans`**：配额由系统按时间算，重新扫描 / 重进页面都不会让它回补。
    // 清了只会让我们以为还有预算、继续把 SDK 的那份也花掉。
    _connectingIndex = null;
    _awaitingConsent = false;
    _connectError = null;
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
    // **并行开一条 BLE 发现通道**（2026-09-11 起）。
    //
    // Wi-Fi 那条的慢是系统给的：前台每 2 分钟只有 4 次 `startScan`，而设备上电到
    // 热点广播出来还要几十秒。BLE 不受那条配额约束，双模设备一上电就在广播，通常
    // 一两秒就能扫到——「搜索不及时」正是冲着这一点。
    //
    // 不 await：BLE 起不起得来（手机没蓝牙、开关关着、固件不是双模）都不该拖住
    // Wi-Fi 那条回落路径。起不来时页面上会写清楚是哪一种。
    //
    // `preferHotspot` 时整条跳过：那是从失败页「改用热点方式」过来的，蓝牙刚试过
    // 并且没成，再优选回蓝牙只会让用户在同一个坑里再等一轮。
    //
    // ⚠️ AP 被屏蔽时（[PairingGate.apEnabled] = false）`preferHotspot` 不再成立——
    // 那条路整条关着，没有「改用热点」可退，所以蓝牙无条件开。
    if (PairingGate.apEnabled ? !widget.preferHotspot : true) {
      unawaited(_startBleDiscovery(state));
    }
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
      _stalledTimer?.cancel();
      if (!mounted) return;
      _radarController.stop();
      setState(() => _scanning = false);
    });
    _stalledTimer = Timer(_stalledAfter, () {
      if (!mounted) return;
      setState(() => _stalled = true);
    });
    // 1 秒一次读缓存（不占配额）：**AP 关着也要留**。它维持 `wifiScan.current`——
    // 也就是「手机现在连的是哪个路由器」，下一页要拿它把 Wi-Fi 名填好。
    _pollTimer = Timer.periodic(_cachePollGap, (_) => unawaited(_pollCache()));
    // 32 秒一次真扫只服务 AP：它唯一的用途是发现**设备热点**。AP 屏蔽期间不发，
    // 省下那条「2 分钟 4 次 `startScan`」的配额，也不让雷达页显得在做无用功。
    if (PairingGate.apEnabled) {
      unawaited(_runScan());
    }
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
    // 「扫到热点就停下来等用户点」是 AP 的动线。AP 屏蔽期间热点列表根本不画，
    // 停在这里只会把 BLE 那条的扫描线一起掐掉。
    if (!PairingGate.apEnabled) return;
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
    // 预算用完就不发真扫了：剩下的配额要留给涂鸦 SDK 去找设备热点
    // （见 [_quotaReservedForSdk]）。这一轮改成读缓存——不占配额，而系统自己、别的应用
    // 也在扫，缓存照样会被刷新。
    if (!_canForceScan) {
      await _pollCache();
      if (!mounted || _windowExpired || _autoOpened) return;
      _forceScanTimer = Timer(_cachePollGap, () => unawaited(_runScan()));
      return;
    }
    _inFlight = true;
    _ownScans.add(DateTime.now());
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

  /// 用户点了某一行的「连接」：**把手机连到这台设备的热点上**，连上了才进下一页。
  ///
  /// ## 授权统一收在这一颗按钮上（2026-09-11 产品口径）
  ///
  /// 产品原则是"整个配网流程都不弹系统 UI、用我们自己的页面"，但 Android 10+ 上让应用
  /// 连指定热点**只有** `WifiNetworkSpecifier` 一条公开路，它必然弹一次系统确认框。
  /// 产品给的处置是：**如果必须授权，就统一收在这颗「连接」按钮上**——只在这里出现、
  /// 只出现一次，之后的页面（输密码、配网进度）一个系统框都没有。
  ///
  /// 手机已经在该热点上时（上次配网留下的、或系统记住后自动重连的）**直接跳过，零点击**。
  ///
  /// ## 为什么必须有这一步
  ///
  /// `git show 223bdae^` 是最后一版**能配网成功**的代码，它的路径是
  /// `pairViaHotspot`：取令牌 → **`_joinHotspotForPairing`（就是这个 API）** →
  /// `pairWifiDevice`。提交 `223bdae` 把"App 自己连热点"换成"指望 SDK 自己连"，从那以后
  /// 全是 `207220`（配网任务整体超时）——**SDK 实测并不连**。所以这一步不能省。
  ///
  /// ## 顺序：云端三件事必须在连热点之前
  ///
  /// 取令牌 / 取安全配置 / 确认家庭都走云端，而一连上设备热点手机就没有外网了。
  /// 所以先 `await _prepared`，再连。
  Future<void> _connectAndOpen(int index, WifiNetwork hotspot) async {
    if (_connectingIndex != null || !mounted) return;
    final state = FlowerpotScope.of(context);
    // 趁还在路由器上把当前网络名记下来带给下一页：连上热点之后就读不到它了。
    final scan = state.wifiScan;
    final routerSsid = (scan?.currentIsDeviceHotspot ?? false)
        ? ''
        : (scan?.current ?? '');
    setState(() {
      _connectingIndex = index;
      _connectError = null;
    });
    // 预取失败不拦路：配网时还会自己再取一次令牌。
    await _prepared;
    if (!mounted) return;
    // ② **App 自己把手机连到设备热点上。**
    //
    // 这一步是涂鸦官方回复里明写的（2026-09-11 产品转达）：
    //
    // > 连接热点：**App 调用系统 API 自动连接设备热点**（Android 允许直接跳转 Wi-Fi 列表）
    //
    // ⚠️ **不是 SDK 干的，删掉就配不上。** 四条独立证据都指向它：官方 AP 文档的定义
    // 「用户需要手动切换手机的 Wi-Fi 设置」；git 上 `223bdae^`（有这步）能配成、`223bdae`
    // （删掉这步）之后全是 `207220` 超时；四次真机实测失败时手机始终留在路由器上；
    // 以及涂鸦这份回复。
    //
    // Android 10+ 上这一步会弹一次系统入网授权框——产品口径是**如果必须授权，就统一收在
    // 「连接」这颗按钮上**，只在这里出现一次，后面的页面一个框都没有。手机已经在该热点上
    // 时直接跳过、零点击。
    // 手机已经在这个热点上时原生会原地返回、不弹框，那就不必说"系统会问一次"。
    final needsConsent = (state.wifiScan?.current ?? '') != hotspot.ssid;
    if (needsConsent) setState(() => _awaitingConsent = true);
    final joined = await state.connectDeviceHotspot(hotspotSsid: hotspot.ssid);
    if (!mounted) return;
    setState(() => _awaitingConsent = false);
    if (!joined.success) {
      setState(() {
        _connectingIndex = null;
        _awaitingConsent = false;
        _connectError = _connectFailureHint(
          joined.code,
          reason: joined.message,
          viaBle: false,
        );
      });
      return;
    }
    // ③ 令牌已经在 `_prepared` 里取好了（涂鸦的步骤表把它排在连热点之后，但那样走不通
    //    ——连上热点手机就没有外网，取不到云端的东西）。
    //
    // 连上了就进「连接 Wi-Fi」页，把**连热点之前**读到的路由器名带过去：用户到那一页
    // 只需输密码。剩下的交给 `pairViaHotspot`（内部会发现手机已在热点上而跳过连接，
    // 所以不会再弹第二个系统框）。
    _hotspotState = state;
    setState(() {
      _connectingIndex = null;
      _connectError = null;
    });
    _openPairing(hotspotSsid: hotspot.ssid, routerSsid: routerSsid);
  }

  /// 和 Wi-Fi 扫描并行开 BLE 发现。
  ///
  /// 失败不抛、不拦路：这条通道目前是**加上去的**，Wi-Fi 那条照常跑。
  Future<void> _startBleDiscovery(FlowerpotState state) async {
    _bleState = state;
    final started = await state.startBleDiscovery();
    if (!mounted) return;
    // 真的扫起来了才给抢答窗口：蓝牙用不了时一秒都不该压着热点列表。
    if (started) {
      _bleScanStartedAt = DateTime.now();
      _bleGraceTimer?.cancel();
      _bleGraceTimer = Timer(_bleGrace, () {
        if (mounted) setState(() {});
      });
    }
    // 可用性（可用 / 没硬件 / 没开蓝牙 / 包里没模块）要画到页面上，
    // 不能默默扫不出来让人以为是设备坏了。
    setState(() {});
  }

  /// 蓝牙还在抢答窗口里：这几秒先别画 Wi-Fi 热点，见 [_bleGrace]。
  bool _bleAnswering(FlowerpotState state) {
    final startedAt = _bleScanStartedAt;
    if (startedAt == null || !state.bleScanning) return false;
    return DateTime.now().difference(startedAt) < _bleGrace;
  }

  /// 常驻的蓝牙搜索状态：**一行事实**，可长按复制。
  ///
  /// AP 屏蔽期间这一页实质是排查工具，要回答的是「用的是不是蓝牙、扫到了什么」。
  /// 所以这里只摆事实、不下结论（`PRODUCT_RULES` §4.1）：扫描方式、蓝牙可用性、
  /// 扫到几台、其中多少台已被绑定、已经扫了多久。
  String _bleScanStatus(FlowerpotState state) {
    final availability = state.bleAvailability;
    final ble = state.bleDevices;
    final bound = ble.where((item) => item.bound).length;
    final startedAt = _bleScanStartedAt;
    final elapsed = startedAt == null
        ? '未开始'
        : '${DateTime.now().difference(startedAt).inSeconds}s';
    // 每一道门单独一行：扫不到时要能一眼看出卡在哪一层，而不是笼统一句「不可用」。
    final blocked = availability.usable
        ? '可用'
        : (availability.reason.isEmpty ? '不可用' : availability.reason);
    final raw = state.rawBleDevices;
    final where = <String>[
      '搜索方式：蓝牙（AP 已屏蔽）',
      '蓝牙：$blocked',
      '蓝牙开关：${availability.enabled ? '开' : '关'}'
          ' · 定位服务：${availability.locationOn ? '开' : '关（BLE 扫描必需）'}',
      '权限：扫描 ${availability.scanPermission ? '已授予' : '未授予'}'
          ' · 定位 ${availability.locationPermission ? '已授予' : '未授予'}',
      '扫描：${state.bleScanning ? '进行中 $elapsed' : '未在扫描'}',
      '涂鸦 SDK 扫到 ${ble.length} 台${bound == 0 ? '' : '（其中 $bound 台已被绑定）'}',
      // **这一行是这轮的关键证据**：系统原生扫描不带任何过滤，附近有广播就收。
      // 它比涂鸦那条多出来的部分，就是「在广播、但不是涂鸦协议格式」的设备。
      '系统原生扫到 ${raw.length} 条广播（无过滤，仅对照）',
      if (raw.isNotEmpty) '　最强：${raw.first.label} ${raw.first.rssi}dBm',
      '过滤：无（扫到什么列什么）',
    ];
    return where.join('\n');
  }

  /// 蓝牙那条通道不可用时的一句话；可用（或还没探测出结果）时返回 null。
  ///
  /// 固件已确认支持蓝牙配网，所以**蓝牙关着 = 用户少了主路径**：他只会觉得"怎么搜这么
  /// 慢"，而真正的原因是一条腿没了。说清楚比让他猜强。
  String? _bleNotice(FlowerpotState state) {
    // 这一轮本来就不走蓝牙（从失败页「改用热点方式」过来的），别再提蓝牙。
    if (widget.preferHotspot) return null;
    final availability = state.bleAvailability;
    // 还没探完：别抢在结论之前说话。
    if (availability == BleAvailability.unknown) return null;
    if (availability.usable) return null;
    if (availability.available && availability.supported) {
      return PairingGate.apEnabled
          ? '蓝牙没有打开。本机型支持蓝牙配网——打开蓝牙会快很多，也不用再确认连接热点。'
          : '蓝牙没有打开。当前版本只走蓝牙配网（热点方式已屏蔽），请先打开蓝牙。';
    }
    // ⚠️ AP 屏蔽期间**不能再说「正在用 Wi-Fi 热点方式搜索」**——那条根本没开，
    // 说了就是假话，会让人以为还有另一条路在跑。
    return PairingGate.apEnabled
        ? '这台手机用不了蓝牙配网（${availability.reason}），正在用 Wi-Fi 热点方式搜索。'
        : '这台手机用不了蓝牙配网（${availability.reason}），而热点方式已屏蔽，本机暂时没有可用路径。';
  }

  /// 用户点了列表里第 [index] 台：按它是**哪条通道发现的**分叉。
  ///
  /// BLE（双模）那条是主路径——固件已确认支持蓝牙配网，而它在每一项上都更好：更快
  /// 被发现、**没有系统入网授权框**、手机全程不离开路由器。Wi-Fi 热点那条是回落，
  /// 只有一台 BLE 设备都没扫到时才会出现在列表里。
  Future<void> _openDevice(int index) async {
    if (index < 0 || index >= _found.length) return;
    final device = _found[index];
    final ble = device.ble;
    if (ble != null) {
      await _connectBleAndOpen(index, ble);
      return;
    }
    // 走到这里说明列表里有热点行。AP 屏蔽期间 `_foundDevices` 根本不产出热点行，
    // 所以这是"不该发生"的一支——显式挡住并说清楚，比让它悄悄走 AP 强。
    if (!PairingGate.apEnabled) {
      setState(() => _connectError = 'AP（热点）配网已屏蔽，当前版本只走蓝牙。');
      return;
    }
    await _connectAndOpen(index, device.hotspot!);
  }

  /// 这一刻要列出来的设备。**BLE 扫到就只列 BLE。**
  ///
  /// 为什么不两条通道都列：同一台设备会同时在广播 BLE、又拉着 Wi-Fi 热点，而两边
  /// **没有可靠的共同标识**（BLE 给 uuid，Wi-Fi 只有 SSID），去重做不干净，混在一起
  /// 就是同一台花盆出现两行、用户不知道该点哪个。既然双模那条在各方面都更好——更快、
  /// 没有系统授权框、不用离开路由器——扫到就只走它，一台都没扫到才回落 Wi-Fi 热点。
  List<_FoundDevice> _foundDevices(
    FlowerpotState state,
    List<WifiNetwork> hotspots,
  ) {
    // **AP 屏蔽期间只有蓝牙一条**（2026-09-11）：热点一律不列，`preferHotspot`
    // 也不再成立。要的就是「蓝牙扫到什么就是什么」，混进 AP 会让结论失真——
    // 用户一旦从热点那条配成了，这轮要验的「设备支不支持蓝牙」就没答案了。
    if (!PairingGate.apEnabled) {
      return state.bleDevices.map(_FoundDevice.ble).toList(growable: false);
    }
    if (widget.preferHotspot) {
      return hotspots.map(_FoundDevice.hotspot).toList(growable: false);
    }
    final ble = state.bleDevices;
    if (ble.isNotEmpty) {
      return ble.map(_FoundDevice.ble).toList(growable: false);
    }
    // 蓝牙还在抢答窗口里：先空着，别让用户抢在 BLE 答出来之前点走更差的那条路。
    if (_bleAnswering(state)) return const <_FoundDevice>[];
    return hotspots.map(_FoundDevice.hotspot).toList(growable: false);
  }

  /// 用户点了一台 **BLE 发现的**设备：查它扫到的 Wi-Fi 列表，然后进输密码页。
  ///
  /// 这就是双模优化路径的前两步落在真实动线上的样子：
  ///
  /// 1. （已发生）BLE 扫描发现设备；
  /// 2. `supportWifiList` 为真 ⇒ `queryDeviceConfigState`——**建本地蓝牙连接**问设备要
  ///    它自己扫到的 Wi-Fi 列表，不走系统 Wi-Fi scan，与那条 4 次/2 分钟的配额无关；
  /// 3. 带着列表进下一页，用户选网络 + 输密码，配网走 `pairViaBle`（凭据经蓝牙下发，
  ///    **全程没有系统入网授权框**）。
  ///
  /// 查列表失败不拦路：Wi-Fi 名让用户从手机扫到的列表里自己选，配网照样能走。
  Future<void> _connectBleAndOpen(int index, BleDevice device) async {
    if (_connectingIndex != null || !mounted) return;
    final state = FlowerpotScope.of(context);
    // 趁还连着路由器把当前网络名记下来带给下一页。双模全程不离开路由器，所以这里
    // 读到的就是用户要让设备加入的那个网络，直接填好、他只需输密码。
    final scan = state.wifiScan;
    final routerSsid = (scan?.currentIsDeviceHotspot ?? false)
        ? ''
        : (scan?.current ?? '');
    setState(() {
      _connectingIndex = index;
      _connectError = null;
    });
    // 令牌要走云端，必须趁手机还连着路由器取好（双模下它本来就没离开）。
    await _prepared;
    if (!mounted) return;
    // 停扫再连：接下来要和这台建立蓝牙连接，一边扫一边连是在抢同一个射频，
    // 只会把连接拖慢甚至连不上。
    await state.stopBleDiscovery();
    if (!mounted) return;
    var networks = const <DeviceWifiNetwork>[];
    if (device.supportWifiList) {
      final result = await state.loadDeviceWifiList(device);
      if (!mounted) return;
      if (result.success) {
        networks = state.deviceWifiNetworks;
      } else {
        // 不拦路，但把原文留在页面上——查不到列表和配不上是两回事。
        setState(
          () => _connectError = _connectFailureHint(
            result.code,
            reason: result.message,
            viaBle: true,
          ),
        );
      }
    }
    setState(() => _connectingIndex = null);
    if (!mounted) return;
    _openPairing(
      bleUuid: device.uuid,
      deviceNetworks: networks,
      routerSsid: routerSsid,
    );
  }

  /// 长按复制页面上那段说明——失败时它就是完整的诊断信息。
  Future<void> _copyMessage(String message) async {
    await Clipboard.setData(ClipboardData(text: message));
    if (!mounted) return;
    showAppMessage(context, '已复制', tone: AppMessageTone.success);
  }

  /// 连设备失败时画在页面上的话。
  ///
  /// SDK 这一步只会给一个笼统的超时（`207220`），用户看了不知道该做什么。把**最可能的
  /// 两个原因**摆出来——它们都是可以立刻动手排除的：
  ///
  /// 1. **设备已经退出配网状态**。设备静置一段时间就不再广播热点了（产品口径，见
  ///    `docs/PRODUCT_RULES.md` 1.5），断电重启即可恢复。
  /// 2. **手机的扫描配额被占满**。`startScan` 的配额按 UID 算，SDK 和我们共用；虽然已经
  ///    给它留了 [_quotaReservedForSdk] 次，但如果刚刚反复搜索过，系统那边可能仍在限流，
  ///    等一会儿再试就好。
  ///
  /// ⚠️ **事实在前，猜测在后。** 2026-09-11 第一版把两条"最常见原因"排在最上面，结果
  /// 用户看到的全是猜测、真正的诊断被挤到看不见的地方——而产品的反馈正是「感觉不是这个
  /// 问题」。现在原始码与原文顶在第一行，建议缩成一行放最后。
  /// 连接/查询失败时画在页面上的话。**事实在前、建议在后**（`PRODUCT_RULES` §4.1）。
  ///
  /// [viaBle] 决定给哪一套建议：两条路的失败原因**完全不重合**，串台的建议比没有建议
  /// 更糟。早先这里只有 AP 那一套，蓝牙失败时会劝用户「等系统的 Wi-Fi 扫描限制缓过来」
  /// ——而蓝牙这条根本不碰 Wi-Fi 扫描，照做只是白等。
  String _connectFailureHint(
    String? code, {
    required String reason,
    required bool viaBle,
  }) {
    final tag = code == null || code.isEmpty ? '' : '【$code】';
    final String advice;
    if (viaBle) {
      advice = switch (code) {
        'ble_wifi_list_unsupported' =>
          '这台设备的固件不支持回报 Wi-Fi 列表（需 TuyaOS 3.6.1 及以上）。\n'
              '配网仍可继续：下一页手动输入 Wi-Fi 名与密码即可。',
        _ =>
          '可以先试：让设备靠近手机；给设备断电重启（重上电后会回到配网状态）；\n'
              '确认手机蓝牙已打开，然后重新点「连接」。',
      };
    } else {
      // 在系统框上点了「取消」是**用户的选择，不是故障**，那一种单独给话术——
      // 别把"断电重启"这种排障步骤推给他。
      advice = code == 'hotspot_join_cancelled'
          ? '重新点「连接」，在系统框里选「连接」即可。\n'
                '设备放久了会退出配网模式，那种情况下断电重启再试。'
          : '可以先试：给设备断电重启后再点「连接」；或等十几秒让系统的 Wi-Fi 扫描限制缓过来。';
    }
    return '$tag$reason\n'
        '\n'
        '$advice';
  }

  /// 进度页上的「取消」：中止正在跑的连接，回到列表。
  void _cancelConnect() {
    final state = _hotspotState ?? FlowerpotScope.of(context);
    unawaited(state.stopDevicePairing());
    if (!mounted) return;
    setState(() {
      _connectingIndex = null;
      _awaitingConsent = false;
      _connectError = '已取消连接，可重新点「连接」。';
    });
  }

  /// 带着这台设备进「连接 Wi-Fi」。两条发现通道共用这一个入口。
  ///
  /// - **BLE（双模）**：带 [bleUuid] 与设备自己扫到的网络 [deviceNetworks]，下一页的
  ///   配网走 `pairViaBle`（凭据经蓝牙下发，没有系统授权框）；
  /// - **Wi-Fi 热点（AP）**：带 [hotspotSsid]，下一页走 `pairViaHotspot`。
  ///
  /// [routerSsid] 都要带：它是**连热点之前**（AP）或**此刻**（BLE，全程没离开路由器）
  /// 读到的当前网络名，下一页据此把 Wi-Fi 名填好，用户只需输密码。
  void _openPairing({
    String? hotspotSsid,
    String? bleUuid,
    List<DeviceWifiNetwork> deviceNetworks = const <DeviceWifiNetwork>[],
    String routerSsid = '',
  }) {
    Navigator.pushNamed(
      context,
      AppRoutes.pairing,
      arguments: PairingArguments(
        request: widget.request,
        hotspotSsid: hotspotSsid,
        bleUuid: bleUuid,
        deviceNetworks: deviceNetworks,
        routerSsid: routerSsid,
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
    final state = FlowerpotScope.of(context);
    final scan = state.wifiScan;
    final hotspots = scan?.deviceHotspots ?? const <WifiNetwork>[];
    // 这一刻列什么：BLE 扫到就只列 BLE，一台都没有才回落 Wi-Fi 热点。
    _found = _foundDevices(state, hotspots);
    final outcome = _outcome(scan, hotspots, _found);
    // 点了「连接」之后盖上进度页——**照智能生活的做法**（`docs/配网1.jpg`）：标题
    // 「正在连接设备…」，下面把五步列出来，当前那一步转圈。前两步（建立连接、设备扫
    // Wi-Fi）就发生在这段等待里，走完就跳去选网络。
    if (_connectingIndex != null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '搜索设备', leading: AppBackButton()),
        background: AppPageBackground.account,
        body: PairingProgressView(
          stage: state.pairingStage,
          onCancel: _cancelConnect,
          notice: _awaitingConsent
              ? '系统会问一次是否连接设备热点，选「连接」继续。\n'
                    '这是 Android 的必经一步，只在这里出现一次。'
              : null,
        ),
      );
    }
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
                        // 长按可复制：连设备失败时这里带着原始码、原文、用时和手机
                        // 当时连的网络，排查要的就是这一整段。
                        GestureDetector(
                          onLongPress: () => _copyMessage(outcome.message),
                          child: Text(
                            outcome.message,
                            key: const Key('device-search-message'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                        // 把**原生日志原样画出来**，产品直接截图给开发。不看 logcat 也能
                        // 定位：停在哪一步、手机当时连的是什么、用了多久。
                        //
                        // ⚠️ AP 屏蔽期间**只要有日志就画**，不再等到失败才画：这一轮的
                        // 目的就是判定设备支不支持蓝牙，「扫描起没起来、报了什么」本身
                        // 就是要交付的结论，成功那次的日志同样要能截图。
                        if ((!PairingGate.apEnabled || _connectError != null) &&
                            state.pairingLog.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          _PairingLogBox(lines: state.pairingLog),
                        ],
                        // 蓝牙那条通道不可用时说一句——否则用户只看到"搜得慢"，
                        // 不知道少了哪条腿。可用时什么都不说，不占地方。
                        // **常驻的搜索状态行**（AP 屏蔽期间）：这一页现在是排查工具，
                        // 「用的是不是蓝牙、扫到几台、扫了多久」必须一眼看得到、能截图。
                        if (!PairingGate.apEnabled) ...<Widget>[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onLongPress: () => _copyMessage(_bleScanStatus(state)),
                            child: Text(
                              _bleScanStatus(state),
                              key: const Key('device-search-ble-status'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                                height: 1.5,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                        if (_bleNotice(state) case final String notice) ...<Widget>[
                          const SizedBox(height: 10),
                          Text(
                            notice,
                            key: const Key('device-search-ble-notice'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ],
                        // 找到的设备直接列在下面，边扫边冒出来。
                        if (_found.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 20),
                          _FoundDeviceList(
                            devices: _found,
                            busyIndex: _connectingIndex,
                            // 只有 AP 那条要连设备热点、才会弹系统框。走 BLE 时
                            // 一个框都没有，别预告一件不会发生的事。
                            // 手机已经在某个设备热点上时同样不弹。
                            showConsentHint:
                                _found.any((item) => !item.isBle) &&
                                !(scan?.currentIsDeviceHotspot ?? false),
                            onSelected: (index) =>
                                unawaited(_openDevice(index)),
                          ),
                        ],
                        // iOS 列不出设备，「下一步」全程都在——那是它唯一的
                        // 入口，让用户干等一轮窗口没有任何意义。
                        //
                        // 能列设备的平台上，「重新扫描」**只在搜完一轮、一台都
                        // 没搜到时**才出现：搜索中它点了也只是白烧一次系统配额，
                        // 已经搜到设备时用户要点的是那台设备、不是再扫一遍。
                        // ⚠️ iOS 那颗「下一步」是 **AP 专用**的入口（它列不出附近
                        // Wi-Fi，只能按前缀直连热点）。AP 屏蔽期间它通向一条走不通的
                        // 路——点下去只会在下一页拿不到 BLE uuid 而报错，所以直接不画，
                        // 由 `_bleOnlyOutcome()` 说明本机为什么没有可用路径。
                        if (!_canListNetworks && PairingGate.apEnabled) ...<Widget>[
                          const SizedBox(height: 20),
                          _SearchActions(onContinue: _continueWithoutList),
                        ] else if ((!_scanning || _stalled) &&
                            _found.isEmpty) ...<Widget>[
                          const SizedBox(height: 20),
                          // `_stalled` 让这颗按钮在 40 秒就出现，而不是等满 3 分钟窗口。
                          // 设备静置一段时间会退出配网状态，这时用户要做的事（断电重启
                          // 再搜）和我们能做的事（重排扫描）都得尽早给他。
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
  _SearchOutcome _outcome(
    WifiScan? scan,
    List<WifiNetwork> hotspots,
    List<_FoundDevice> found,
  ) {
    // ⚠️ **AP 屏蔽期间先分流**：下面那一整套结论（限流、没扫到网络、iOS 列不出来）
    // 讲的都是 **Wi-Fi 扫描**，而这轮根本不发 Wi-Fi 扫描。原样走下去会给出
    // 「系统限制了 Wi-Fi 扫描频率」这种与事实无关的话，把排查方向带偏。
    if (!PairingGate.apEnabled && found.isEmpty) {
      return _bleOnlyOutcome();
    }
    // 已经找到设备时，标题就该讲这件事，而不是继续报「搜索中」。
    if (found.isNotEmpty) {
      // 走蓝牙那条时**没有系统确认框**，别照抄 AP 的话术预告一件不会发生的事。
      final viaBle = found.first.isBle;
      return _SearchOutcome(
        '发现 ${found.length} 台设备',
        // 设备本身不联网，所以下一步是给它配一个 Wi-Fi；这里先说清要点哪个按钮。
        // 预取失败时把原因顶上来，免得用户后面遇到失败完全没有线索。
        _connectError ??
            (viaBle
                ? '点设备右侧的「连接」，之后只需输入 Wi-Fi 密码。'
                : '点设备右侧的「连接」连上这台设备（系统会弹一次确认框，请点「连接」），'
                      '之后只需输入 Wi-Fi 密码。'),
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
      if (_stalled) {
        // ⚠️ 这一句是 2026-09-10 产品反馈换来的：**设备静置一段时间会退出配网模式**，
        // 那之后它不再广播热点，扫多久都没用。真扫受系统配额限制（前台 4 次 / 2 分钟）
        // 已经跑在上限上，所以这时有用的不是再等，而是让用户把设备断电重启——重启后
        // 热点一定在，下一次扫描就能看见。
        // 两条通道都没答上来时才走到这里，所以话要覆盖两条：设备退出配网状态后
        // **蓝牙广播和 Wi-Fi 热点会一起停**，断电重启两条一起恢复。
        return const _SearchOutcome(
          '还没搜到设备',
          '设备静置一段时间会退出配网状态，此时它既不广播蓝牙、也不再拉起热点。\n'
              '请给设备断电重启（重新上电后会自动回到配网状态），再点「重新扫描」。',
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

  /// AP 屏蔽期间还没扫到设备时说什么。**只讲蓝牙**，并且把当前事实摆出来。
  ///
  /// 这一轮的目的就是判定「设备到底支不支持蓝牙配网」，所以这里每一句都要能被当作
  /// 证据：蓝牙能不能用、扫没扫起来、扫了多久、扫到几台。含糊的「未发现设备」在这轮
  /// 里是没有价值的（`PRODUCT_RULES` §4.1 事实在前）。
  _SearchOutcome _bleOnlyOutcome() {
    final state = FlowerpotScope.of(context);
    final availability = state.bleAvailability;
    if (!availability.available || !availability.supported) {
      // 原因先落成局部变量再拼：插值里再套一层同种引号虽然合法，但可读性差——
      // 2026-09-11 把 `\n` 写成真换行、源码被截断成两行的就是这一处。
      final reason = availability.reason.isEmpty
          ? '这台手机或这个包不支持 BLE'
          : availability.reason;
      return _SearchOutcome(
        '本机用不了蓝牙配网',
        '$reason。\n'
            '当前版本已屏蔽热点（AP）配网，只走蓝牙，所以这里没有可用的替代路径。',
      );
    }
    if (!availability.enabled) {
      return const _SearchOutcome(
        '请先打开蓝牙',
        '当前版本只走蓝牙配网（热点方式已屏蔽）。打开手机蓝牙后点「重新扫描」。',
      );
    }
    if (!availability.scanPermission || !availability.locationPermission) {
      return const _SearchOutcome(
        '缺少搜索所需的权限',
        'BLE 扫描需要「附近的设备」与「定位」权限。\n'
            '请在系统设置里授予本应用这两项权限后，再点「重新扫描」。',
      );
    }
    if (!availability.locationOn) {
      // ⚠️ 这一条最容易被当成"设备有问题"：定位服务关着时 BLE 扫描**静默返回空**，
      // 不报错、不回调，页面上和"附近没有设备"一模一样。必须单独说出来。
      return const _SearchOutcome(
        '请打开系统定位服务',
        '定位权限已经给了，但**系统的定位开关是关着的**——Android 上 BLE 扫描要求它打开，\n'
            '关着时扫描不会报错、只会一台都扫不到。请在下拉菜单或系统设置里打开定位，\n'
            '再点「重新扫描」。',
      );
    }
    if (_stalled) {
      // 涂鸦扫不到时，**系统原生扫描的数目就是分水岭**——把结论直接写出来，
      // 别让人对着「未发现设备」去猜（`PRODUCT_RULES` §4.1 事实在前）。
      final rawCount = state.rawBleDevices.length;
      if (rawCount > 0) {
        return _SearchOutcome(
          '附近有蓝牙广播，但没有涂鸦设备',
          '系统原生扫描收到 $rawCount 条广播，而涂鸦 SDK 一台都没认出来。\n'
              '这说明手机这边的扫描是通的：要么这些广播里没有花盆，'
              '要么花盆广播的格式不是涂鸦配网要的那种（属于固件侧）。\n'
              '请确认设备已上电并处于配网状态；仍然如此的话，把本页截图给设备方。',
        );
      }
      return const _SearchOutcome(
        '蓝牙没有扫到任何设备',
        '已经扫了一段时间，**连系统原生扫描也一条广播都没收到**（当前不做任何过滤）。\n'
            '可能是：设备没有在广播 BLE（固件未支持）、设备已退出配网状态、或距离太远。\n'
            '请给设备断电重启后靠近手机，再点「重新扫描」。',
      );
    }
    return const _SearchOutcome(
      '正在用蓝牙搜索设备...',
      '当前版本已屏蔽热点（AP）配网，只用蓝牙搜索；扫到的设备**不做任何过滤**，全部列出。',
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

/// 配网原生日志，**直接画在页面上**。
///
/// 产品不看 logcat（「你把日志直接打印到页面上，我截图给你」），所以这几行必须能被截图。
/// 内容是原生 `trace()` 推上来的：`ap query: begin` / `activator=…` / `builder ok` /
/// `wifi before` / `handed to SDK…` / `success|error … wifi now` / `pairing step: …`。
///
/// 等长字体 + 左对齐 + 可长按复制：这是给人读的诊断，不是给用户看的文案。
class _PairingLogBox extends StatelessWidget {
  const _PairingLogBox({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final text = lines.join('\n');
    return GestureDetector(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          showAppMessage(context, '日志已复制', tone: AppMessageTone.success);
        }
      },
      child: Container(
        key: const Key('device-search-pairing-log'),
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.textTertiary.withValues(alpha: .3)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.left,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            height: 1.45,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
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
/// 搜索页列出的一台待配网设备，**不区分是哪条通道发现的**。
///
/// 两条通道的模型完全不同（BLE 给 `ScanDeviceBean`，Wi-Fi 只有一个 SSID），但页面上
/// 它们是同一件东西：一台可以点「连接」的设备。差异收在这里，列表与行就不必各写一遍。
class _FoundDevice {
  const _FoundDevice.ble(BleDevice device) : ble = device, hotspot = null;

  const _FoundDevice.hotspot(WifiNetwork network)
    : ble = null,
      hotspot = network;

  final BleDevice? ble;
  final WifiNetwork? hotspot;

  bool get isBle => ble != null;

  /// 行上显示的名字。BLE 广播常常没有名字，`BleDevice.label` 会退到 mac 尾号。
  String get label => ble?.label ?? hotspot!.ssid;

  /// 行上那行小字：**说清楚是怎么发现的、下一步会怎么走**。整条动线是黑箱时，
  /// 用户遇到失败完全无从下手。
  /// 行上那行小字：**说清楚是怎么发现的、这台是什么、下一步会怎么走**。
  ///
  /// AP 屏蔽期间这一行同时是**排查证据**（`PairingGate.showUnfilteredBleScan`）：
  /// 不做过滤之后，绑定状态、能力位、pid 都得摆出来，否则用户看到一行却不知道
  /// 它为什么点不动、或者为什么点了会失败。
  String get detail {
    final device = ble;
    if (device == null) {
      return 'Wi-Fi 热点 · 连上它再配网';
    }
    final parts = <String>[
      '蓝牙 ${device.rssi}dBm',
      if (device.bound) '已被绑定',
      device.supportWifiList ? '可读取设备扫到的 Wi-Fi' : '固件不支持读 Wi-Fi 列表',
      if (device.productId.isNotEmpty) 'pid ${device.productId}',
    ];
    return parts.join(' · ');
  }

  /// 这一行现在能不能点。
  ///
  /// **已被绑定的不给点**：它要么在别人账号下、要么已经在本账号里，点下去必然失败。
  /// 但仍然**列出来**——这一轮要的就是「蓝牙到底看见了什么」，藏起来等于把证据删掉。
  bool get selectable => ble == null || !ble!.bound;
}

class _FoundDeviceList extends StatelessWidget {
  const _FoundDeviceList({
    required this.devices,
    required this.onSelected,
    required this.busyIndex,
    required this.showConsentHint,
  });

  static const listKey = Key('device-search-found-list');

  final List<_FoundDevice> devices;

  /// 回调给的是**下标**：页面要据它知道是哪一行在转圈。
  final ValueChanged<int> onSelected;

  /// 正在连接的那一行；null 表示空闲。
  final int? busyIndex;

  /// 要不要在按钮上方说明"系统会问一次"。手机已经在设备热点上时不会弹框，
  /// 那就别说——说了反而让人以为还有一步要做。
  final bool showConsentHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: listKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // **把系统框"预告"在按钮正上方。**
        //
        // 涂鸦 2026-09-11 书面确认：Android 10+ 第三方 App 连设备热点只能走
        // `WifiNetworkSpecifier`，系统授权框强制出现、无绕过方案（见
        // `PRODUCT_RULES` §4.0）。既然关不掉，那就别让它显得像出错——在用户按下去
        // 之前一句话说清会发生什么、点哪个、只问一次。
        if (showConsentHint) ...<Widget>[
          const Text(
            '点「连接」后，系统会问一次是否连接设备热点，选「连接」即可。\n'
            '只在这一步问一次，后面输密码、配网都不会再弹。',
            key: Key('device-search-consent-hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (var index = 0; index < devices.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: 10),
          _FoundDeviceTile(
            index: index,
            device: devices[index],
            busy: busyIndex == index,
            // 正在连某一行时，别的行一律不可点——同时只能有一条连接，
            // 蓝牙那条更是如此（一边扫一边连是在抢同一个射频）。
            // 已被绑定的那些照常列出来（这一轮不过滤），但点不动。
            onTap: busyIndex == null && devices[index].selectable
                ? () => onSelected(index)
                : null,
          ),
        ],
      ],
    );
  }
}

class _FoundDeviceTile extends StatelessWidget {
  const _FoundDeviceTile({
    required this.index,
    required this.device,
    required this.onTap,
    required this.busy,
  });

  final int index;
  final _FoundDevice device;

  /// null 表示此刻不可点（别的行正在连）。
  final VoidCallback? onTap;

  /// 这一行正在连热点。
  final bool busy;

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
              // 图标就说明走的是哪条路：蓝牙 / 热点。
              Icon(
                device.isBle ? Icons.bluetooth : Icons.wifi_tethering,
                size: 22,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      device.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.detail,
                      key: Key('device-search-found-detail-$index'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 一颗明确的「连接」，而不是一个箭头：这一步是**用户手动选设备**
              // （2026-09-10 产品口径），按钮比箭头更说明"点了会发生什么"。
              // 整行也照旧可点，两者同一个动作。
              FilledButton(
                key: Key('device-search-connect-$index'),
                onPressed: busy ? null : onTap,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(68, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: AppColors.surface,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 14),
                ),
                child: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.surface,
                        ),
                      )
                    : const Text('连接'),
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
