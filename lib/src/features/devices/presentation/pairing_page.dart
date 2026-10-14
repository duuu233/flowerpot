import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../state.dart';
import '../../../tuya/tuya_models.dart';
import '../pairing_gate.dart';
import 'pairing_failure_page.dart';
import 'widgets/pairing_progress_view.dart';

/// Route arguments for the Wi-Fi step, which now runs after a device is
/// connected on the selection page.
/// 底部那颗浮着的「开始配网」按钮占掉的高度（`bottom: 8` + 按钮高 50，再留点余量）。
///
/// 两处都要用它，而且必须是同一个数：
///
/// 1. 滚动区的底部 padding —— 让内容能滚到按钮上方，不被压在按钮下面；
/// 2. 输入框的 [TextField.scrollPadding] —— 键盘弹出时框架把光标滚进视口时，
///    默认只保证离视口底部 20px，而**视口底部就是键盘顶部**，那 20px 正好是这颗
///    按钮占着的位置。不把按钮的高度告诉它，获焦的输入框就会停在按钮后面，看起来
///    就是「被键盘挡住了」。
const double _startButtonInset = 92;

class PairingArguments {
  const PairingArguments({
    this.hotspotSsid,
    this.bleUuid,
    this.deviceNetworks = const <DeviceWifiNetwork>[],
    this.request,
    this.routerSsid = '',
  });

  /// 搜索页**在连设备热点之前**读到的路由器 Wi-Fi 名。
  ///
  /// 用户点「连接」时手机就挂到设备热点上了，此后「带出当前 Wi-Fi 名」那条规则只能留空
  /// （当前连的是热点，填它等于让设备去连它自己）。所以趁还在路由器上先把名字抓下来带
  /// 过来，用户到这一页仍然看到自己的 Wi-Fi 已经填好，只需输密码。
  final String routerSsid;

  /// The access point that planter raises in AP mode, as the scan saw it. AP
  /// provisioning needs the phone to join it, so the page can name it instead
  /// of saying "the device hotspot".
  final String? hotspotSsid;

  /// 这台设备的 BLE uuid；非空表示**走双模（蓝牙）配网**。
  ///
  /// 有它就不必碰设备的 Wi-Fi 热点：凭据经蓝牙下发（`FlowerpotState.pairViaBle`），
  /// 于是**没有系统入网授权框**、手机也全程不用离开路由器。为空时回落到 AP 那条
  /// （`pairViaHotspot`，配 [hotspotSsid] 使用）。
  final String? bleUuid;

  /// 设备**自己扫到的** Wi-Fi 列表，走蓝牙问它要的（`queryDeviceConfigState`）。
  ///
  /// 比手机扫到的准：手机在客厅收得到的网络，窗台上的花盆未必够得着。为空时
  /// 「切换」弹层回落到手机扫到的那份。
  final List<DeviceWifiNetwork> deviceNetworks;

  /// Credentials from a previous attempt, so a retry keeps what was entered.
  final PairingRequest? request;
}

/// Route arguments for the failure screen. The reason is carried so a debug
/// build can show the SDK's own code instead of only the generic copy.
class PairingFailureArguments {
  const PairingFailureArguments({
    this.request,
    this.code,
    this.message,
    this.bleUuid,
    this.hotspotSsid,
    this.deviceNetworks = const <DeviceWifiNetwork>[],
  });

  final PairingRequest? request;
  final String? code;
  final String? message;

  /// 刚才那次走的是**哪条路**。失败页据此决定「重新配网」照原样重来，以及蓝牙失败时
  /// 要不要给出「改用热点方式」那条退路。
  final String? bleUuid;
  final String? hotspotSsid;

  /// 上一次问设备要到的 Wi-Fi 列表，重试时不必再问一遍。
  final List<DeviceWifiNetwork> deviceNetworks;
}

class PairingPage extends StatefulWidget {
  const PairingPage({super.key, this.arguments});

  final PairingArguments? arguments;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> with WidgetsBindingObserver {
  // Only a retry pre-fills these. A placeholder SSID/password would be handed
  // to the SDK verbatim on the first real pairing attempt, so a fresh start
  // asks for the network the phone is actually on — filled in from the scan,
  // never from a made-up name.
  late final ssidController = TextEditingController(
    text: widget.arguments?.request?.ssid ?? '',
  );
  late final passwordController = TextEditingController(
    text: widget.arguments?.request?.password ?? '',
  );

  /// 正在跑的那次配网所属的状态对象。用户在配网期间退出本页时据此中止：
  /// 否则 activator 会继续跑满两分钟，手机也一直挂在设备热点上。dispose 里
  /// 已经不能查 InheritedWidget，所以发起时就把引用留下。
  FlowerpotState? _pairingState;

  /// 本页拿到过的状态对象，`dispose` 里用来还原网络（那时已不能查 InheritedWidget）。
  FlowerpotState? _scopeState;

  /// 本页发起的配网正在跑。用它而不是 `state.busy` 来决定是否盖进度页：busy 是
  /// 全局操作锁，别处的写操作也会把它拉起来。
  bool _pairing = false;

  /// 这一趟走的是**双模（蓝牙）**配网。
  ///
  /// 它与 AP 那条最实质的差别是**手机从来没离开路由器**，所以本页那几处「把 Wi-Fi
  /// 还回去」对它全都不适用。
  bool get _viaBle => (widget.arguments?.bleUuid ?? '').isNotEmpty;

  /// 上一次由扫描自动填进输入框的名称。用户自己打字或从「切换」里选过之后，
  /// 输入框的内容就和它对不上了，此后的刷新不再覆盖用户的选择。
  String? _autoFilledSsid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 强制重扫，不吃 state 里的缓存：那份快照可能是搜索页几分钟前留下的，
    // 用户之后很可能已经把手机切到了别的网络。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_loadNetworks()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final state = _pairingState;
    if (state != null) {
      _pairingState = null;
      // 配网还在跑：中止它（内部会一并解开网络绑定）。
      unawaited(state.cancelPairing());
    } else {
      // ⚠️ **没跑配网也要把手机的 Wi-Fi 还回去。** 走 AP 那条时，进这一页手机已经挂在
      // 设备热点上（搜索页连的），用户在这里直接返回、或者输到一半退出，不还原就等于
      // 把他的手机撂在一个没网的热点上。
      //
      // 走蓝牙那条时手机从来没离开路由器，没有热点可放——调了也是空操作，但按 uuid
      // 判一下，读代码的人才不会以为双模也会动网络。
      final scope = _scopeState;
      if (scope != null && !_viaBle) unawaited(scope.releaseDeviceHotspot());
    }
    ssidController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  /// 回到前台就重新读一次当前网络。用户在这一页最常见的动作就是切到系统设置
  /// 换 Wi-Fi 再回来（手动连热点的路径更是必须这么做），不重读的话页面上留着
  /// 的还是进页面那一刻的名字，和手机实际连的网络对不上。
  ///
  /// 配网过程中不刷新：那时手机是故意挂在设备热点上的。
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // 切到后台：**把手机的 Wi-Fi 还回去**，别把用户撂在一个没网的设备热点上。
    // 用户可能只是去别处看一眼 Wi-Fi 密码，也可能就此不回来了——后者若不还原，
    // 手机会一直没网直到进程被杀。回到本页时 `resumed` 会重新读一次网络；真要配网时
    // `pairViaHotspot` 的第②步会重新连热点（已连则跳过）。
    //
    // ⚠️ 配网跑起来之后不能放：那会把正在用的通道掐断。
    if (lifecycleState == AppLifecycleState.paused) {
      if (_pairing || _viaBle) return;
      unawaited(_scopeState?.releaseDeviceHotspot());
      return;
    }
    if (lifecycleState != AppLifecycleState.resumed || _pairing) return;
    unawaited(_loadNetworks());
  }

  /// Fills the SSID with the network the phone is on, which is the one the
  /// planter has to join in the overwhelming majority of setups.
  ///
  /// Only a real scan result is used, and only a 2.4 GHz one: handing the SDK a
  /// 5 GHz or hotspot name would make provisioning fail in a way that looks
  /// like a device problem.
  /// 把手机当前连着的 Wi-Fi 名带进输入框。
  ///
  /// **只读缓存、不发起扫描**：名字来自 `WifiManager.connectionInfo`，根本不需要
  /// 扫描；而一次真扫要等系统的 `SCAN_RESULTS_AVAILABLE` 广播（最多 5 秒）、被配额
  /// 挡住时还更久——名字就是这样被拖慢的。附近网络列表留给「切换」那个弹层自己去拉。
  Future<void> _loadNetworks() async {
    if (!mounted) return;
    final state = FlowerpotScope.of(context);
    _scopeState = state;
    await state.probeWifi(refresh: false);
    if (!mounted) return;
    _applyCurrentSsid(state);
  }


  /// 规则很简单（2026-09-10 产品口径）：
  ///
  /// 1. 手机连着 Wi-Fi 就**直接带出来**；
  /// 2. 没连就**留空**，让用户自己去「切换」里选。
  ///
  /// 唯一的例外是手机此刻正挂在设备热点上（上一次配网失败留下的），那个名字填进去
  /// 等于让设备去连它自己，所以按「没连」处理。频段不再作为过滤条件——连的是 5G 时
  /// 照样带出来，由页面上那条频段提示去说明，空着一个框反而让人不知道该做什么。
  void _applyCurrentSsid(FlowerpotState state) {
    // 用户自己输入或从「切换」里选过的名字一律不动。
    final untouched =
        ssidController.text.isEmpty || ssidController.text == _autoFilledSsid;
    if (!untouched) {
      setState(() {});
      return;
    }
    final scan = state.wifiScan;
    final current = scan?.current;
    final connected =
        current != null &&
        current.isNotEmpty &&
        !(scan?.currentIsDeviceHotspot ?? false);
    // 手机还在路由器上就用当前网络；已经挂到设备热点上了就用搜索页连热点**之前**抓到
    // 的那个路由器名（见 [PairingArguments.routerSsid]）。两者都没有才留空。
    final preset = widget.arguments?.routerSsid ?? '';
    final filled = connected ? current : preset;
    ssidController.text = filled;
    _autoFilledSsid = filled.isEmpty ? null : filled;
    setState(() {});
  }

  /// 用户在进度页上按了「取消配网」。中止只是让 `pairViaHotspot` 以
  /// `pair_cancelled` 返回，收尾（释放热点、作废令牌）还是它自己做，所以这里
  /// 不动 `_pairing`——等那次 await 回来再关进度页。
  Future<void> _cancelPairing() async {
    final state = _pairingState;
    if (state == null) return;
    await state.cancelPairing();
  }


  /// 「切换」弹层里列的网络。**设备自己扫到的优先。**
  ///
  /// 走蓝牙那条时，上一页已经通过 `queryDeviceConfigState` 问设备要过它扫到的列表
  /// （不走系统 Wi-Fi scan，与那条 4 次/2 分钟的配额无关）。**那份比手机扫到的准**：
  /// 手机在客厅收得到的网络，窗台上的花盆未必够得着，让用户从手机的列表里挑，挑中一个
  /// 设备根本连不上的网络是很常见的失败。
  ///
  /// 设备没给（老固件不支持、或这次查失败了）就回落到手机扫到的那份。设备只支持
  /// 2.4G，所以频段一律按 2.4G 记。
  List<WifiNetwork> _routerNetworks(FlowerpotState state) {
    final fromDevice = widget.arguments?.deviceNetworks ?? const <DeviceWifiNetwork>[];
    if (fromDevice.isNotEmpty) {
      return fromDevice
          .map(
            (item) => WifiNetwork(
              ssid: item.ssid,
              level: item.rssi,
              frequency: 2412,
            ),
          )
          .toList(growable: false);
    }
    return state.wifiScan?.routerNetworks ?? const <WifiNetwork>[];
  }

  Future<void> _switchWifi() async {
    final state = FlowerpotScope.of(context);
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .42),
      builder: (_) => _WifiSelectionSheet(
        current: ssidController.text,
        networks: _routerNetworks(state),
        onRefresh: () async {
          // 「刷新」= 手机重扫一遍。受 Android 配额限制（2 分钟 4 次），所以只在
          // 用户主动点的时候发起。
          await state.probeWifi(refresh: true);
          if (!context.mounted) return const <WifiNetwork>[];
          return _routerNetworks(state);
        },
      ),
    );
    if (value != null && value.isNotEmpty && mounted) {
      setState(() => ssidController.text = value);
    }
  }

  Future<void> _pair() async {
    if (ssidController.text.trim().isEmpty || passwordController.text.isEmpty) {
      showAppMessage(context, '请输入 Wi-Fi 名称与密码', tone: AppMessageTone.error);
      return;
    }

    final state = FlowerpotScope.of(context);
    final request = PairingRequest(
      ssid: ssidController.text.trim(),
      password: passwordController.text,
    );
    // ⚠️ **这两行不能省，`2026-09-11` 的大删除（`aef6ccd`）把它们连同上面那段注释一起
    // 删掉了，症状就是「填完密码点下一步卡住」。** `build` 靠 `_pairing` 切进度页：它一直
    // 是 false，点下按钮后页面就还停在输密码那一屏，只有按钮里转一个圈，而 `pairViaHotspot`
    // 最长要跑满 `pairingDeadline`（150 秒）才回来——中间没有任何进度、也没有「取消配网」。
    //
    // `_pairingState` 同样要留下：`dispose` 与 `didChangeAppLifecycleState` 都按它区分
    // 「配网正在跑」。为 null 时退出本页走的是 `releaseDeviceHotspot()`、切后台也会去放
    // 热点——那会把正在下发凭据的通道掐断，配网**真的会失败**，不只是看起来卡住。
    //
    // 按 `223bdae^`（git 里最后一版配网成功的代码）原样恢复。
    _pairingState = state;
    setState(() => _pairing = true);
    // **两条配网路径，按上一页是怎么发现这台设备的分叉。**
    //
    // 1. **双模（蓝牙）——主路径。** 固件已确认支持蓝牙配网。凭据经蓝牙下发
    //    （原生 `IMultiModeActivator.startActivator`），**全程不碰设备的 Wi-Fi 热点**：
    //    没有系统入网授权框、手机不用离开路由器、也不依赖 Wi-Fi 扫描拿确切热点名。
    // 2. **AP 热点——回落。** 一台 BLE 设备都没扫到时走它（手机蓝牙关着、或设备不是
    //    双模）。手机这时已经在设备热点上（搜索页那颗「连接」干的），`pairViaHotspot`
    //    内部的连热点一步会检测到"已在目标热点上"而原地跳过。
    //
    // 两条都要令牌，而令牌走云端、必须在**还连着路由器**时取好——由搜索页预取
    // （`prepareForPairing`）。AP 那条尤其要紧：手机一挂到设备热点上就没有外网了。
    final bleUuid = widget.arguments?.bleUuid;
    // ⚠️ **AP 屏蔽期间拿不到 uuid 就直接报错，不许悄悄退回 AP。**
    //
    // 悄悄退回是这一轮最要命的一种错：用户会在某次配网成功里以为「蓝牙这条通了」，
    // 而实际上成功的是 AP，本轮要验的结论就此被盖掉。宁可当场失败并说清楚。
    if (!PairingGate.apEnabled && (bleUuid == null || bleUuid.isEmpty)) {
      const code = 'ap_disabled';
      const message =
          '当前版本已屏蔽热点（AP）配网，只走蓝牙双模；'
          '而这次没有拿到设备的蓝牙标识，无法下发凭据。'
          '请回搜索页用蓝牙重新搜索并选择设备。';
      // 失败页 2026-09-14 起只画一句笼统文案，完整原因记进联调日志。
      state.logPairingFailure(
        PairingFailurePage.diagnosticFor(code: code, message: message),
      );
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.pairingFailure,
        arguments: PairingFailureArguments(
          request: request,
          code: code,
          message: message,
        ),
      );
      return;
    }
    final result = bleUuid != null && bleUuid.isNotEmpty
        ? await state.pairViaBle(
            uuid: bleUuid,
            ssid: request.ssid,
            password: request.password,
          )
        : await state.pairViaHotspot(
            ssid: request.ssid,
            password: request.password,
            hotspotSsid: widget.arguments?.hotspotSsid,
          );
    _pairingState = null;
    if (!mounted) return;
    setState(() => _pairing = false);
    if (!result.success) {
      // 失败页 2026-09-14 起只画一句笼统文案（产品：原因 / 失败码 / 各步耗时那段不要了），
      // 完整原因记进联调日志，排查照样有据。
      state.logPairingFailure(
        PairingFailurePage.diagnosticFor(
          code: result.code,
          message: result.message,
        ),
      );
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.pairingFailure,
        arguments: PairingFailureArguments(
          request: request,
          code: result.code,
          message: result.message,
          // 走的是哪条路要一起带过去：不带的话「重新配网」会掉进另一条分支，
          // 用户得到的是**另一个**失败，排查方向直接被带偏。
          bleUuid: widget.arguments?.bleUuid,
          hotspotSsid: widget.arguments?.hotspotSsid,
          deviceNetworks:
              widget.arguments?.deviceNetworks ??
              const <DeviceWifiNetwork>[],
        ),
      );
      return;
    }
    // 不强制解包：配网返回成功、设备却没进列表时（云端刚绑完还没同步、或这中间
    // 有一次拉取拿到了空列表），`!` 会把一次成功的配网变成一个空指针异常——页面
    // 停在原地不动，看起来就像配网失败了，实际设备已经绑好。
    final device = state.selectedDevice;
    if (device == null) {
      showAppMessage(
        context,
        '配网成功，但暂时读不到设备信息，请回设备列表下拉刷新',
        tone: AppMessageTone.info,
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.pairingSuccess,
      arguments: device.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    if (_pairing) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '设备配网', leading: AppBackButton()),
        background: AppPageBackground.account,
        body: PairingProgressView(
          stage: state.pairingStage,
          onCancel: _cancelPairing,
        ),
      );
    }
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '连接Wi-Fi', leading: AppBackButton()),
      background: AppPageBackground.account,
      body: Stack(
        children: <Widget>[
          SingleChildScrollView(
            key: const Key('pairing-scroll-view'),
            // [_startButtonInset] 是底部那颗「开始配网」按钮的占位：它浮在滚动区
            // 外面，内容要让出这一段才不会被压在按钮下面。键盘弹出时它还有第二个
            // 作用——给自动滚动留出可滚的余量，详见输入框上的 `scrollPadding`。
            //
            // 键盘避让靠两件事配合：Scaffold 默认 `resizeToAvoidBottomInset: true`
            // 把 body 按键盘缩矮、滚动视口跟着变矮（这一半本来就对），**加上**输入框
            // 的 `scrollPadding` 把这颗按钮的高度算进去（这一半 2026-09-10 才补上：
            // 框架默认只留 20px，而那 20px 正好被按钮占着，所以获焦的输入框看起来
            // 还是被挡住）。
            padding: const EdgeInsets.only(bottom: _startButtonInset),
            child: ResponsiveContent(
              // 顶部留白 88 → 56 → 10：这一页的目标是**整屏放得下、不用滚**。
              // 2026-09-23 按稿子 247:7496 对齐：提示句在 y=387（正文从 y=90 起，
              // 10 + 插图 270 + 17），原 56 让整页低约 60，底部说明被开始按钮挡住。
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                10,
                AppSpacing.pageMargin,
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _WifiConnectionIllustration(),
                  const SizedBox(height: 17),
                  // 2026-09-10 动线调整后这里不再画「已选择设备 xxx」：设备是在
                  // **搜索页**上点「连接」确认的，热点那时也已经连上，这一页的任务只剩
                  // 「选一个要让设备加入的 Wi-Fi 并输密码」，再重复一遍设备名只是占地方。
                  const Text(
                    '请将设备连接到2.4GHz Wi-Fi网络',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _WifiNoticeCard(),
                  const SizedBox(height: 10),
                  _WifiCredentialsCard(
                    ssidController: ssidController,
                    passwordController: passwordController,
                    onSwitchWifi: _switchWifi,
                  ),
                  // 2026-09-10 产品要求：「点『开始配网』后，系统会弹框询问是否连接…
                  // 不必到系统设置里手动连」那一整段删掉。系统弹框来了用户自然看得见，
                  // 提前解释一遍只是占掉半屏。
                  //
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Image.asset(
                        AppAssets.infoOutlineIcon,
                        width: 18,
                        height: 18,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        '连接过程中请保持设备靠近路由器',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.pageMargin,
            right: AppSpacing.pageMargin,
            bottom: 8,
            child: FilledButton(
              key: const Key('start-pairing-button'),
              onPressed: state.busy ? null : _pair,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: AppColors.surface,
                elevation: 2,
                shadowColor: AppColors.brandPrimary.withValues(alpha: .35),
                shape: const StadiumBorder(),
                textStyle: AppTypography.pageTitle.copyWith(
                  color: AppColors.surface,
                ),
              ),
              child: state.busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.surface,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('开始配网'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WifiConnectionIllustration extends StatelessWidget {
  const _WifiConnectionIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('wifi-connection-illustration'),
      height: 270,
      child: Image.asset(
        AppAssets.pairingWifiSetupIllustration,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}

class _WifiNoticeCard extends StatelessWidget {
  const _WifiNoticeCard();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 300;
        return DecoratedBox(
          key: const Key('wifi-notice-card'),
          decoration: const BoxDecoration(
            color: AppColors.surfaceTranslucent,
            borderRadius: AppRadius.card,
          ),
          child: SizedBox(
            height: compact ? 84 : 72,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  _WifiBandIcon(),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '仅支持2.4GHz Wi-Fi网络',
                          style: TextStyle(
                            color: AppColors.brandPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '请确保设备连接的是稳定的2.4GHz网络',
                          style: TextStyle(
                            color: AppColors.brandPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WifiBandIcon extends StatelessWidget {
  const _WifiBandIcon();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.wifi24GhzIcon,
      width: 40,
      height: 40,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '2.4GHz Wi-Fi',
    );
  }
}

class _WifiCredentialsCard extends StatefulWidget {
  const _WifiCredentialsCard({
    required this.ssidController,
    required this.passwordController,
    required this.onSwitchWifi,
  });

  final TextEditingController ssidController;
  final TextEditingController passwordController;
  final VoidCallback onSwitchWifi;

  @override
  State<_WifiCredentialsCard> createState() => _WifiCredentialsCardState();
}

class _WifiCredentialsCardState extends State<_WifiCredentialsCard> {
  /// Wi-Fi 密码默认遮蔽，可切明文。
  ///
  /// 配网失败最常见的原因之一就是密码打错，而这里又是全大小写/符号混排的路由器
  /// 密码，看不见就只能靠重试两分钟来发现输错了。
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 72,
              child: Row(
                children: <Widget>[
                  const _CredentialIcon(
                    assetPath: AppAssets.wifiNetworkIcon,
                    semanticLabel: 'Wi-Fi 名称',
                  ),
                  const SizedBox(width: 12),
                  // Editable: the switcher lists what the phone can actually
                  // see, which is nothing on iOS, so the real network always
                  // has to be typable.
                  Expanded(
                    child: _CredentialInput(
                      fieldKey: const Key('pairing-ssid-field'),
                      label: 'Wi-Fi名称',
                      hintText: '输入 2.4G 名称',
                      controller: widget.ssidController,
                    ),
                  ),
                  TextButton(
                    key: const Key('switch-wifi-button'),
                    onPressed: widget.onSwitchWifi,
                    child: const Text('切换'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            SizedBox(
              height: 72,
              child: Row(
                children: <Widget>[
                  const _CredentialIcon(
                    assetPath: AppAssets.wifiPasswordIcon,
                    semanticLabel: 'Wi-Fi 密码',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CredentialInput(
                      fieldKey: const Key('pairing-password-field'),
                      label: 'Wi-Fi密码',
                      hintText: '请输入密码',
                      controller: widget.passwordController,
                      obscureText: _obscurePassword,
                      // 圆点之间要留空才看得清位数；明文时恢复正常字距，否则
                      // 路由器密码会被拉得很难读。
                      letterSpacing: _obscurePassword ? 3 : 0,
                    ),
                  ),
                  IconButton(
                    key: const Key('pairing-password-visibility'),
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: _obscurePassword
                        ? Image.asset(
                            AppAssets.passwordVisibilityOffIcon,
                            width: 24,
                            height: 24,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            excludeFromSemantics: true,
                          )
                        : const Icon(
                            Icons.visibility_outlined,
                            color: AppColors.textSecondary,
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

/// 凭据卡里的一格：上面一行小标签，下面是可编辑的值。
///
/// 两格（Wi-Fi 名称 / 密码）共用同一份版式。原来各写一遍，且把输入框压在
/// `SizedBox(height: 24)` 里配 `InputDecoration.collapsed`——15px 的字加上光标本就
/// 接近这个高度，聚焦时光标上下顶格、点击热区也只有 24px，是「上下太窄」的来源。
/// 现在交给 `isDense` + 上下留白自己撑开（约 33px），并且聚焦时在值下面画一条品牌
/// 色细线，让「哪一格正在输入」看得见——收起焦点后这条线是透明的，静态版式与设计
/// 稿一致。
class _CredentialInput extends StatelessWidget {
  const _CredentialInput({
    required this.fieldKey,
    required this.label,
    required this.hintText,
    required this.controller,
    this.obscureText = false,
    this.letterSpacing = 0,
  });

  final Key fieldKey;
  final String label;
  final String hintText;
  final TextEditingController controller;
  final bool obscureText;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        TextField(
          key: fieldKey,
          controller: controller,
          obscureText: obscureText,
          // 键盘避让的关键一行。
          //
          // Scaffold 的 `resizeToAvoidBottomInset`（默认 true）已经把 body 按键盘
          // 缩矮、滚动视口跟着变矮，框架也会自动把光标滚进视口——但它默认只留
          // `EdgeInsets.all(20)`，也就是光标离视口底部 20px 就算「可见」。视口底部
          // 就是键盘顶部，而那一带被浮着的「开始配网」按钮占了，所以获焦的输入框
          // 会停在按钮后面。这里把按钮的占位加进去，页面就会多往上滚一点。
          //
          // ⚠️ 不要改成「关掉 resizeToAvoidBottomInset + 自己加 viewInsets 的
          // padding」那一套：视口不缩的话 `ensureVisible` 根本没有可滚的余量，
          // 而开着 resize 时 body 里读到的 `viewInsets.bottom` 恒为 0（已被
          // Scaffold 消费掉），两头都不成立。
          scrollPadding: const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            _startButtonInset + 12,
          ),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            letterSpacing: letterSpacing,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.only(top: 4, bottom: 6),
            hintText: hintText,
            hintStyle: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 15,
            ),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.transparent),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.transparent),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.brandPrimary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _CredentialIcon extends StatelessWidget {
  const _CredentialIcon({required this.assetPath, required this.semanticLabel});

  final String assetPath;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: 40,
      height: 40,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel,
    );
  }
}

/// The 2.4 GHz networks the phone can actually see, from `scanWifi`.
///
/// Empty is a normal answer: iOS does not enumerate access points at all, and
/// Android throttles scans. The sheet says so instead of offering example
/// names, because whatever is picked here is handed to the SDK verbatim.
class _WifiSelectionSheet extends StatefulWidget {
  const _WifiSelectionSheet({
    required this.current,
    required this.networks,
    required this.onRefresh,
  });

  final String current;
  final List<WifiNetwork> networks;
  final Future<List<WifiNetwork>> Function() onRefresh;

  @override
  State<_WifiSelectionSheet> createState() => _WifiSelectionSheetState();
}

class _WifiSelectionSheetState extends State<_WifiSelectionSheet> {
  late String selected = widget.current;
  late List<WifiNetwork> networks = widget.networks;
  bool refreshing = false;

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    final result = await widget.onRefresh();
    if (!mounted) return;
    setState(() {
      networks = result;
      refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      // 用例据此断言「弹层有没有被自动弹出来」。
      key: const Key('pairing-wifi-sheet'),
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      // Fixed height with a scrolling list: keep the header short, since the
      // non-scrolling part has no room to grow at large text scales.
      child: SizedBox(
        height: 360,
        child: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 48,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.disabled,
                  borderRadius: AppRadius.full,
                ),
              ),
              SizedBox(
                height: 56,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('wifi-selection-cancel'),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            '取消',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Flexible(
                      child: Text(
                        '选择Wi-Fi',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const Key('wifi-selection-confirm'),
                          onPressed: selected.isEmpty
                              ? null
                              : () => Navigator.pop(context, selected),
                          child: const Text(
                            '确认',
                            style: TextStyle(
                              color: AppColors.brandPrimary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Flexible(
                    child: Text(
                      '仅显示可用的2.4GHzWi-Fi网络',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('wifi-selection-refresh'),
                    tooltip: '重新扫描',
                    visualDensity: VisualDensity.compact,
                    onPressed: refreshing ? null : _refresh,
                    icon: refreshing
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.refresh,
                            size: 18,
                            color: AppColors.brandPrimary,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: networks.isEmpty
                    ? const AppDialogScrollView(
                        padding: EdgeInsets.symmetric(horizontal: 36),
                        child: Center(
                          child: Text(
                            '没有扫描到 2.4GHz 网络。\n'
                            '可以直接在上一页手动输入 Wi-Fi 名称。',
                            key: Key('wifi-selection-empty'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        ),
                      )
                    : AppDialogScrollbar(
                        builder: (controller) => ListView.separated(
                          controller: controller,
                          primary: false,
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          itemCount: networks.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            color: AppColors.divider,
                          ),
                          itemBuilder: (context, index) {
                            final network = networks[index];
                            final active = selected == network.ssid;
                            return InkWell(
                              key: Key('wifi-option-${network.ssid}'),
                              onTap: () =>
                                  setState(() => selected = network.ssid),
                              child: SizedBox(
                                height: 64,
                                child: Row(
                                  children: <Widget>[
                                    Image.asset(
                                      AppAssets.wifiSignalIcon,
                                      width: 27,
                                      height: 27,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      semanticLabel: 'Wi-Fi 网络',
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        network.ssid,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 17,
                                        ),
                                      ),
                                    ),
                                    if (active)
                                      Image.asset(
                                        AppAssets.checkmarkIcon,
                                        key: const Key('wifi-selected-check'),
                                        width: 28,
                                        height: 28,
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.high,
                                        semanticLabel: '已选择',
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
