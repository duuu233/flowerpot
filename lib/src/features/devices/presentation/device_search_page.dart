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
    if (widget.request != null) {
      _discoveryTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.deviceSelection,
          arguments: widget.request,
        );
      });
    }
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
      background: AppPageBackground.standard,
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
                        size: compact ? 224 : 286,
                      ),
                      SizedBox(height: compact ? 12 : 20),
                      Text(
                        '搜索附近设备…',
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
                        '请保持手机蓝牙和Wi-Fi已开启，并让设备处于配网状态',
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
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) => CustomPaint(
                  painter: _RadarPainter(progress: animation.value),
                ),
              ),
            ),
            const _SearchingWifiHub(),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .43;
    final ringPaint = Paint()..style = PaintingStyle.fill;

    ringPaint.color = AppColors.brandSurface.withValues(alpha: .28);
    canvas.drawCircle(center, radius, ringPaint);
    ringPaint.color = AppColors.brandSurface.withValues(alpha: .42);
    canvas.drawCircle(center, radius * .70, ringPaint);
    ringPaint.color = AppColors.brandSurface.withValues(alpha: .58);
    canvas.drawCircle(center, radius * .43, ringPaint);

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

    final dotPaint = Paint()
      ..color = AppColors.brandSoft.withValues(alpha: .42);
    final dots = <Offset>[
      Offset(size.width * .15, size.height * .18),
      Offset(size.width * .86, size.height * .28),
      Offset(size.width * .17, size.height * .68),
      Offset(size.width * .79, size.height * .83),
    ];
    final dotSizes = <double>[4.5, 5.5, 4.5, 4.5];
    for (var index = 0; index < dots.length; index++) {
      canvas.drawCircle(dots[index], dotSizes[index], dotPaint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _SearchingWifiHub extends StatelessWidget {
  const _SearchingWifiHub();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 82,
      height: 82,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          const Positioned(
            top: 0,
            child: Icon(
              Icons.wifi_rounded,
              color: AppColors.brandPrimary,
              size: 58,
            ),
          ),
          Container(
            width: 72,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.brandPrimary,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _HubDot(),
                SizedBox(width: 9),
                _HubDot(),
                SizedBox(width: 9),
                _HubDot(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HubDot extends StatelessWidget {
  const _HubDot();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(dimension: 7),
    );
  }
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
    return SizedBox.square(
      dimension: 34,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 4,
            bottom: 4,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: const SizedBox.square(
                dimension: 9,
                child: ColoredBox(color: AppColors.brandPrimary),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.topCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.brandPrimary,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: 30,
                child: Icon(
                  Icons.question_mark_rounded,
                  color: AppColors.surface,
                  size: 19,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
