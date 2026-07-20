import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';

class PairingFailurePage extends StatelessWidget {
  const PairingFailurePage({super.key, this.request});

  final PairingRequest? request;

  void _retry(BuildContext context) {
    Navigator.pushReplacementNamed(context, AppRoutes.pairing);
  }

  void _returnToDevices(BuildContext context) {
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.deviceSelection,
      arguments: request,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '连接设备', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentHeight = constraints.maxHeight < 690
              ? 690.0
              : constraints.maxHeight;
          final horizontalPadding = constraints.maxWidth < 360 ? 12.0 : 20.0;
          return SingleChildScrollView(
            key: const Key('pairing-failure-scroll-view'),
            child: SizedBox(
              height: contentHeight,
              child: ResponsiveContent(
                maxWidth: 375,
                padding: EdgeInsets.zero,
                child: Stack(
                  children: <Widget>[
                    const Positioned(
                      top: 70,
                      left: 0,
                      right: 0,
                      child: Center(child: _FailureRadar()),
                    ),
                    const Positioned(
                      top: 315,
                      left: 12,
                      right: 12,
                      child: Text(
                        '配网失败，请重试',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const Positioned(
                      top: 362,
                      left: 16,
                      right: 16,
                      child: Text(
                        '设备未能成功连接到当前Wi-Fi网络',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 400,
                      left: horizontalPadding + 8,
                      right: horizontalPadding + 8,
                      child: const _FailureTipCard(),
                    ),
                    Positioned(
                      left: horizontalPadding,
                      right: horizontalPadding,
                      bottom: 75,
                      child: SizedBox(
                        height: 50,
                        child: FilledButton(
                          key: const Key('retry-pairing-button'),
                          onPressed: () => _retry(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brandPrimary,
                            foregroundColor: AppColors.surface,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 19),
                          ),
                          child: const Text('重新配网'),
                        ),
                      ),
                    ),
                    Positioned(
                      left: horizontalPadding,
                      right: horizontalPadding,
                      bottom: 10,
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          key: const Key('return-device-selection-button'),
                          onPressed: () => _returnToDevices(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.brandPrimary,
                            side: const BorderSide(
                              color: AppColors.brandPrimary,
                            ),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 19),
                          ),
                          child: const Text('返回选择设备'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FailureRadar extends StatelessWidget {
  const _FailureRadar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 235,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _FailureDisc(size: 230, opacity: .24),
          _FailureDisc(size: 176, opacity: .35),
          _FailureDisc(size: 126, opacity: .48),
          Positioned(left: 26, top: 29, child: _FailureDot(size: 9)),
          Positioned(right: 25, top: 49, child: _FailureDot(size: 10)),
          Positioned(left: 35, bottom: 18, child: _FailureDot(size: 14)),
          Positioned(right: 31, bottom: 29, child: _FailureDot(size: 8)),
          _FailedWifiHub(),
          Positioned(
            left: 36,
            bottom: 51,
            child: _StatusBubble(
              color: AppColors.danger,
              icon: Icons.priority_high_rounded,
            ),
          ),
          Positioned(
            right: 35,
            bottom: 51,
            child: _StatusBubble(
              color: AppColors.brandPrimary,
              icon: Icons.refresh_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureDisc extends StatelessWidget {
  const _FailureDisc({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandSurface.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _FailureDot extends StatelessWidget {
  const _FailureDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandSoft.withValues(alpha: .46),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _FailedWifiHub extends StatelessWidget {
  const _FailedWifiHub();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 90,
      child: CustomPaint(painter: _FailedWifiHubPainter()),
    );
  }
}

class _FailedWifiHubPainter extends CustomPainter {
  const _FailedWifiHubPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.brandPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.butt;
    for (final spec in const <(Rect, double)>[
      (Rect.fromLTWH(10, 5, 70, 58), .76),
      (Rect.fromLTWH(22, 21, 46, 39), .66),
      (Rect.fromLTWH(32, 36, 26, 22), .52),
    ]) {
      canvas.drawArc(spec.$1, 3.72, spec.$2, false, paint);
      canvas.drawArc(spec.$1, 3.72 + spec.$2 + .46, spec.$2, false, paint);
    }

    final bodyPaint = Paint()
      ..color = AppColors.brandPrimary
      ..style = PaintingStyle.fill;
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(10, 57, 70, 31),
      const Radius.circular(14),
    );
    canvas.drawRRect(body, bodyPaint);
    canvas.drawRect(const Rect.fromLTWH(23, 77, 44, 13), bodyPaint);
    final dotPaint = Paint()..color = AppColors.surface;
    for (final x in const <double>[31, 45, 59]) {
      canvas.drawCircle(Offset(x, 72), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_FailedWifiHubPainter oldDelegate) => false;
}

class _StatusBubble extends StatelessWidget {
  const _StatusBubble({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 1.2),
      ),
      child: SizedBox.square(
        dimension: 35,
        child: Icon(icon, color: AppColors.surface, size: 25),
      ),
    );
  }
}

class _FailureTipCard extends StatelessWidget {
  const _FailureTipCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.brandSurfaceAlt,
        borderRadius: AppRadius.card,
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _QuestionBubble(),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '小提示',
                    style: TextStyle(
                      color: AppColors.brandPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. 请靠近路由器，确保信号强度良好\n'
                    '2. 请检查Wi-Fi密码是否正确\n'
                    '3. 请检查设备是否已接通电源\n'
                    '4. 请检查设备是否连接2.4GHzWi-Fi网络',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.75,
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
