import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../state.dart';
import '../../../tuya/tuya_models.dart';

/// Route arguments for the Wi-Fi step, which now runs after a device is
/// connected on the selection page.
class PairingArguments {
  const PairingArguments({this.deviceName, this.hotspotSsid, this.request});

  /// Planter picked on the selection page, shown above the credentials.
  final String? deviceName;

  /// The access point that planter raises in AP mode, as the scan saw it. AP
  /// provisioning needs the phone to join it, so the page can name it instead
  /// of saying "the device hotspot".
  final String? hotspotSsid;

  /// Credentials from a previous attempt, so a retry keeps what was entered.
  final PairingRequest? request;
}

/// Route arguments for the failure screen. The reason is carried so a debug
/// build can show the SDK's own code instead of only the generic copy.
class PairingFailureArguments {
  const PairingFailureArguments({this.request, this.code, this.message});

  final PairingRequest? request;
  final String? code;
  final String? message;
}

class PairingPage extends StatefulWidget {
  const PairingPage({super.key, this.arguments});

  final PairingArguments? arguments;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
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

  /// 平台不让 App 自己连热点（iOS、Android 9 及以下）时切到手动路径：页面改为
  /// 引导用户去系统设置连热点，按钮变成「已连接热点，开始配网」，下一次点击
  /// 告诉状态层热点已经由用户连好，直接配网。
  bool _manualHotspot = false;

  /// 正在跑的那次配网所属的状态对象。用户在配网期间退出本页时据此中止：
  /// 否则 activator 会继续跑满两分钟，手机也一直挂在设备热点上。dispose 里
  /// 已经不能查 InheritedWidget，所以发起时就把引用留下。
  FlowerpotState? _pairingState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNetworks());
  }

  @override
  void dispose() {
    final state = _pairingState;
    if (state != null) {
      _pairingState = null;
      unawaited(state.cancelPairing());
    }
    ssidController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  /// Fills the SSID with the network the phone is on, which is the one the
  /// planter has to join in the overwhelming majority of setups.
  ///
  /// Only a real scan result is used, and only a 2.4 GHz one: handing the SDK a
  /// 5 GHz or hotspot name would make provisioning fail in a way that looks
  /// like a device problem.
  Future<void> _loadNetworks({bool force = false}) async {
    if (!mounted) return;
    final state = FlowerpotScope.of(context);
    if (force || state.wifiScan == null) await state.probeWifi();
    if (!mounted) return;
    final scan = state.wifiScan;
    final current = scan?.current;
    if (scan != null &&
        current != null &&
        current.isNotEmpty &&
        ssidController.text.isEmpty &&
        scan.currentIs24g != false &&
        !scan.currentIsDeviceHotspot) {
      ssidController.text = current;
    }
    setState(() {});
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
        networks: state.wifiScan?.routerNetworks ?? const <WifiNetwork>[],
        onRefresh: () async {
          await state.probeWifi();
          return state.wifiScan?.routerNetworks ?? const <WifiNetwork>[];
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
    // 取令牌 → 连热点 → 下发凭据串成一次操作。这三步有顺序约束（令牌只能在还有
    // 外网时取，连上热点后就取不到了），交给用户按顺序点三个按钮，错一次就是两
    // 分钟超时，而失败原因从 `1006` 里看不出来。
    _pairingState = state;
    final result = await state.pairViaHotspot(
      ssid: request.ssid,
      password: request.password,
      hotspotSsid: widget.arguments?.hotspotSsid,
      hotspotJoinedManually: _manualHotspot,
    );
    _pairingState = null;
    if (!mounted) return;
    if (result.code == 'hotspot_manual_required') {
      // 不是失败：令牌已取好，等用户去系统设置把热点连上再点一次。
      setState(() => _manualHotspot = true);
      showAppMessage(context, '请先到系统设置连接设备热点', tone: AppMessageTone.info);
      return;
    }
    if (!result.success) {
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.pairingFailure,
        arguments: PairingFailureArguments(
          request: request,
          code: result.code,
          message: result.message,
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

  /// Used when the selection step carried no hotspot name. Naming one family
  /// only would send the user looking for a network that is not there: the
  /// suffix is random and the prefix varies between firmware builds.
  static const String _hotspotDescription =
      '设备自己放出的热点（多为 SmartLife-… / SmartLift-… 这类带随机后缀的名字）';

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final hotspot = widget.arguments?.hotspotSsid;
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '连接Wi-Fi', leading: AppBackButton()),
      background: AppPageBackground.account,
      body: Stack(
        children: <Widget>[
          SingleChildScrollView(
            key: const Key('pairing-scroll-view'),
            padding: const EdgeInsets.only(bottom: 92),
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                88,
                AppSpacing.pageMargin,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _WifiConnectionIllustration(),
                  const SizedBox(height: 27),
                  if (widget.arguments?.deviceName case final String name) ...[
                    Text(
                      '已连接 $name',
                      key: const Key('pairing-connected-device'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Text(
                    '请将设备连接到2.4GHz Wi-Fi网络',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _WifiNoticeCard(),
                  const SizedBox(height: 12),
                  _WifiCredentialsCard(
                    ssidController: ssidController,
                    passwordController: passwordController,
                    onSwitchWifi: _switchWifi,
                  ),
                  const SizedBox(height: 12),
                  if (_manualHotspot)
                    _PairingHintCard(
                      key: const Key('pairing-hotspot-manual'),
                      tone: AppColors.warning,
                      text:
                          '当前系统不允许 App 直接连接热点。请到系统设置连接'
                          '${hotspot == null ? _hotspotDescription : '「$hotspot」'}'
                          '，若系统提示该网络无法上网请选择保持连接，然后回到本页点'
                          '「已连接热点，开始配网」。',
                    )
                  else
                    _PairingHintCard(
                      key: const Key('pairing-hotspot-step'),
                      tone: AppColors.brandPrimary,
                      text:
                          '点「开始配网」后，系统会弹框询问是否连接'
                          '${hotspot == null ? '设备热点' : '「$hotspot」'}，确认即可，'
                          '不必到系统设置里手动连。',
                    ),
                  const SizedBox(height: 38),
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
                  : Text(_manualHotspot ? '已连接热点，开始配网' : '开始配网'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small notice strip used for the band warning and the AP hotspot step.
class _PairingHintCard extends StatelessWidget {
  const _PairingHintCard({
    required this.tone,
    required this.text,
    this.action,
    super.key,
  });

  final Color tone;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .08),
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, action == null ? 12 : 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              text,
              style: TextStyle(color: tone, fontSize: 13, height: 1.55),
            ),
            if (action != null)
              Align(alignment: Alignment.centerRight, child: action!),
          ],
        ),
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
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Wi-Fi名称',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          // Editable: the switcher lists what the phone can
                          // actually see, which is nothing on iOS, so the real
                          // network always has to be typable.
                          child: TextField(
                            key: const Key('pairing-ssid-field'),
                            controller: widget.ssidController,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                            ),
                            decoration: const InputDecoration.collapsed(
                              hintText: '输入 2.4G 名称',
                            ),
                          ),
                        ),
                      ],
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Wi-Fi密码',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: TextField(
                            key: const Key('pairing-password-field'),
                            controller: widget.passwordController,
                            obscureText: _obscurePassword,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              // 圆点之间要留空才看得清位数；明文时恢复正常字距，
                              // 否则路由器密码会被拉得很难读。
                              letterSpacing: _obscurePassword ? 3 : 0,
                            ),
                            decoration: const InputDecoration.collapsed(
                              hintText: '请输入密码',
                            ),
                          ),
                        ),
                      ],
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
                    const Text(
                      '选择Wi-Fi',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
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
                  const Text(
                    '仅显示可用的2.4GHzWi-Fi网络',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
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
                    ? const Padding(
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
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 36),
                        itemCount: networks.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppColors.divider),
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
            ],
          ),
        ),
      ),
    );
  }
}
