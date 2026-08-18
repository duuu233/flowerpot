import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';

class DeviceSearchPage extends StatefulWidget {
  const DeviceSearchPage({super.key, this.request});

  final PairingRequest? request;

  @override
  State<DeviceSearchPage> createState() => _DeviceSearchPageState();
}

class _DeviceSearchPageState extends State<DeviceSearchPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarController;
  Timer? _discoveryTimer;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    // Discovery is the first pairing step now, so the scan always advances to
    // the device list; Wi-Fi credentials are collected after a device is
    // connected.
    _discoveryTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.deviceSelection,
        arguments: widget.request,
      );
    });
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '搜索设备', leading: AppBackButton()),
      background: AppPageBackground.account,
      body: ResponsiveContent(
        maxWidth: 375,
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            return Stack(
              key: const Key('device-search-content'),
              children: <Widget>[
                Positioned(
                  top: compact ? 54 : 84,
                  left: 12,
                  right: 12,
                  child: Column(
                    children: <Widget>[
                      _SearchRadar(
                        animation: _radarController,
                        size: compact ? 176 : 200,
                      ),
                      SizedBox(height: compact ? 12 : 20),
                      Text(
                        '搜索附近设备...',
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
                      const Text(
                        '请让设备进入配网状态，并确认手机连接的是2.4GHz Wi-Fi',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: compact ? 10 : 18,
                  child: const _SearchTipCard(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SearchRadar extends StatelessWidget {
  const _SearchRadar({required this.animation, required this.size});

  final Animation<double> animation;
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
