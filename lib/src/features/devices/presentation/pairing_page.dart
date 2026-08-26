import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../core/config/debug_tools_config.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
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

  /// Provisioning mode sent to the SDK. The product UI always uses AP; debug
  /// builds can switch to EZ, which is usually the quicker one to bring up on
  /// a bench device.
  late String mode = widget.arguments?.request?.mode ?? 'ap';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNetworks());
  }

  @override
  void dispose() {
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

  /// AP provisioning fetches its token first, in its own step.
  ///
  /// `getActivatorToken` is a cloud call, and in AP mode the phone leaves the
  /// router for the device hotspot before provisioning starts — from there
  /// there is no route to the cloud, and Tuya answers with a network error that
  /// looks nothing like its actual cause. The bridge caches the token natively
  /// for 8 minutes; it is never handed back to Dart.
  Future<void> _prepareToken() async {
    final state = FlowerpotScope.of(context);
    final result = await state.prepareActivatorToken();
    if (!mounted) return;
    setState(() {});
    showAppMessage(
      context,
      result.success ? '已获取配网令牌，请到系统设置连接设备热点后返回' : result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  Future<void> _pair() async {
    if (ssidController.text.trim().isEmpty || passwordController.text.isEmpty) {
      showAppMessage(context, '请输入 Wi-Fi 名称与密码', tone: AppMessageTone.error);
      return;
    }

    final state = FlowerpotScope.of(context);
    // Credentials first, then the token: the user has to type them while the
    // phone still has internet, because AP mode sends them away to the hotspot
    // right afterwards.
    if (_needsToken(state.activatorTokenReady)) {
      await _prepareToken();
      return;
    }

    final request = PairingRequest(
      ssid: ssidController.text.trim(),
      password: passwordController.text,
      mode: mode,
    );
    final result = await state.pairDevice(request);
    if (!mounted) return;
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
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.pairingSuccess,
      arguments: state.selectedDevice!.id,
    );
  }

  /// EZ stays on the router the whole time, so its token is fetched inside
  /// `pairWifiDevice` and no separate step is shown.
  bool _needsToken(bool tokenReady) => mode == 'ap' && !tokenReady;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final scan = state.wifiScan;
    final tokenReady = state.activatorTokenReady;
    final needsToken = _needsToken(tokenReady);
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
                  if (mode == 'ez' &&
                      scan != null &&
                      scan.currentIs24g == false) ...<Widget>[
                    const SizedBox(height: 12),
                    _PairingHintCard(
                      key: const Key('pairing-band-warning'),
                      tone: AppColors.danger,
                      // EZ broadcasts the credentials over the network the
                      // phone is on; from 5 GHz the planter never hears them.
                      text:
                          '手机当前连接的是 5G 网络（${scan.current ?? ''}），'
                          'EZ 快连必须先切到 2.4G。',
                    ),
                  ],
                  if (mode == 'ap' && tokenReady) ...<Widget>[
                    const SizedBox(height: 12),
                    _HotspotStepCard(
                      hotspot: hotspot,
                      current: scan?.current,
                      joined: scan?.currentIsDeviceHotspot ?? false,
                      onRefresh: () => _loadNetworks(force: true),
                    ),
                  ],
                  if (DebugToolsConfig.enabled) ...<Widget>[
                    const SizedBox(height: 18),
                    Center(
                      child: _PairingModeSwitch(
                        mode: mode,
                        onChanged: (value) => setState(() => mode = value),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ] else
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
                  : Text(needsToken ? '下一步：连接设备热点' : '开始配网'),
            ),
          ),
        ],
      ),
    );
  }
}

/// What AP mode has to do between fetching the token and provisioning: join the
/// planter's own access point, which only the system Wi-Fi settings can do.
class _HotspotStepCard extends StatelessWidget {
  const _HotspotStepCard({
    required this.hotspot,
    required this.current,
    required this.joined,
    required this.onRefresh,
    super.key,
  });

  /// The planter hotspot picked on the selection page, when there was one.
  final String? hotspot;

  /// The network the phone is on right now, from the last scan.
  final String? current;
  final bool joined;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final target = hotspot == null ? '设备热点（SmartLife-… / TY_…）' : '「$hotspot」';
    return _PairingHintCard(
      key: const Key('pairing-hotspot-step'),
      tone: joined ? AppColors.success : AppColors.brandPrimary,
      text: joined
          ? '已连接 ${current ?? '设备热点'}，现在可以点「开始配网」。'
          : '配网令牌已就绪（8 分钟内有效）。\n'
                '请到系统设置连接 $target，提示「无法访问互联网」时选择保持连接，'
                '然后回到这里点「开始配网」。'
                '${current == null ? '' : '\n手机当前连接：$current'}',
      action: TextButton(
        key: const Key('pairing-hotspot-refresh'),
        onPressed: onRefresh,
        child: const Text('检查连接'),
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

/// Debug-only switch between the two Wi-Fi provisioning modes the bridge
/// supports, so a bench test does not have to be rebuilt to try the other one.
class _PairingModeSwitch extends StatelessWidget {
  const _PairingModeSwitch({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      key: const Key('pairing-mode-switch'),
      segments: const <ButtonSegment<String>>[
        ButtonSegment<String>(value: 'ap', label: Text('AP')),
        ButtonSegment<String>(value: 'ez', label: Text('EZ')),
      ],
      selected: <String>{mode},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelectionChanged: (value) => onChanged(value.first),
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

class _WifiCredentialsCard extends StatelessWidget {
  const _WifiCredentialsCard({
    required this.ssidController,
    required this.passwordController,
    required this.onSwitchWifi,
  });

  final TextEditingController ssidController;
  final TextEditingController passwordController;
  final VoidCallback onSwitchWifi;

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
                            controller: ssidController,
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
                    onPressed: onSwitchWifi,
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
                            controller: passwordController,
                            obscureText: true,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              letterSpacing: 3,
                            ),
                            decoration: const InputDecoration.collapsed(
                              hintText: '请输入密码',
                            ),
                          ),
                        ),
                      ],
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
