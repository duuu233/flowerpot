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
/// "Anything else" includes a hotspot whose SSID is outside the known prefixes:
/// the scan saw it, only the recognition missed it. Whenever the scan came back
/// with 2.4 GHz networks the page therefore offers the selection list as well,
/// where the raw scan can be picked from by name.
class DeviceSearchPage extends StatefulWidget {
  const DeviceSearchPage({super.key, this.request});

  final PairingRequest? request;

  @override
  State<DeviceSearchPage> createState() => _DeviceSearchPageState();
}

class _DeviceSearchPageState extends State<DeviceSearchPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarController;

  /// What the page shows: the radar sweep and the "searching" copy.
  bool _scanning = true;

  /// Whether a scan is actually in flight. A second one would only collide with
  /// the state's single-operation guard and report "busy" as a scan failure.
  bool _inFlight = false;
  ActionResult? _result;

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
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
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

  /// Opens the selection page on the raw scan, for a planter whose hotspot
  /// name is outside the recognized prefixes: it is in the list the phone
  /// returned, just not under a name this app knows.
  void _pickManually() {
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.deviceSelection,
      arguments: widget.request,
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
                        if (!_scanning) ...<Widget>[
                          const SizedBox(height: 20),
                          _SearchActions(
                            onRescan: _scan,
                            onContinue: _continueAnyway,
                            // Only worth offering when the scan actually
                            // returned something pickable.
                            onPickManually:
                                (scan?.otherNetworks.isEmpty ?? true)
                                ? null
                                : _pickManually,
                          ),
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
  _SearchOutcome _outcome(WifiScan? scan) {
    if (_scanning) {
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
    if (scan == null || scan.networks.isEmpty) {
      // iOS never enumerates access points, and a throttled Android scan can
      // come back empty too. Neither means the planter is missing.
      return const _SearchOutcome(
        '无法列出附近设备',
        '当前系统不提供附近网络列表。\n确认设备指示灯已进入配网状态后继续下一步。',
      );
    }
    final current = scan.current;
    // 认得出的热点没有，不代表设备不在列表里——量产固件的热点名可能不在白名单
    // 上。扫到过 2.4G 网络时把手动选择指出来，那份列表就是原始扫描结果。
    final manual = scan.otherNetworks.isNotEmpty;
    return _SearchOutcome(
      '未发现配网中的设备',
      '扫描到 ${scan.networks.length} 个网络，其中没有认得出的设备热点。\n'
      '${current == null ? '' : '手机当前连接：$current${_band(scan)}\n'}'
      '请长按设备按键让它进入配网状态后重新扫描'
      '${manual ? '；\n设备热点已经出现在 Wi-Fi 列表里的话，用下面的手动选择。' : '。'}',
    );
  }

  String _band(WifiScan scan) => switch (scan.currentIs24g) {
    true => '（2.4G）',
    false => '（5G，配网需要 2.4G）',
    null => '',
  };

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
    required this.onRescan,
    required this.onContinue,
    required this.onPickManually,
  });

  final VoidCallback onRescan;
  final VoidCallback onContinue;

  /// Null when the scan returned nothing to pick from.
  final VoidCallback? onPickManually;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          width: 220,
          height: 46,
          child: FilledButton(
            key: const Key('device-search-rescan'),
            onPressed: onRescan,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: AppColors.surface,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 17),
            ),
            child: const Text('重新扫描'),
          ),
        ),
        if (onPickManually case final VoidCallback pick)
          TextButton(
            key: const Key('device-search-manual-pick'),
            onPressed: pick,
            child: const Text(
              '从附近网络中手动选择设备',
              style: TextStyle(color: AppColors.brandPrimary, fontSize: 15),
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
