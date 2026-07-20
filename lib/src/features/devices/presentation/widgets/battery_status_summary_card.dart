import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/battery_status_page_model.dart';

class BatteryStatusSummaryCard extends StatelessWidget {
  const BatteryStatusSummaryCard({required this.model, super.key});

  final BatteryStatusPageModel model;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderRadius: AppRadius.card,
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const SizedBox(
                width: 112,
                child: Center(
                  child: AppDevicePlaceholder(hasPlant: true, width: 84),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const ChargingBatteryBadge(size: 40),
                        const SizedBox(width: AppSpacing.md),
                        Flexible(
                          child: Text(
                            model.status,
                            style: AppTypography.deviceTitle.copyWith(
                              color: AppColors.brandPrimary,
                              fontSize: 19,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      model.description,
                      style: AppTypography.body.copyWith(
                        height: 1.55,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Divider(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              const SizedBox(width: 28),
              const ChargingBatteryBadge(size: 48),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: '${model.battery}',
                              style: AppTypography.deviceTitle.copyWith(
                                fontSize: 21,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: ' %',
                              style: AppTypography.body.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '当前电池状态',
                          style: AppTypography.body.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ChargingBatteryBadge extends StatelessWidget {
  const ChargingBatteryBadge({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.brandSurface,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: const _ChargingBatteryPainter()),
      ),
    );
  }
}

class _ChargingBatteryPainter extends CustomPainter {
  const _ChargingBatteryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 48;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * .48, size.height * .5),
        width: 26 * scale,
        height: 14 * scale,
      ),
      Radius.circular(1.5 * scale),
    );
    final color = Paint()..color = AppColors.brandPrimary;
    canvas.drawRRect(body, color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * .79, size.height * .5),
          width: 3 * scale,
          height: 7 * scale,
        ),
        Radius.circular(scale),
      ),
      color,
    );
    final bolt = Path()
      ..moveTo(size.width * .49, size.height * .31)
      ..lineTo(size.width * .38, size.height * .52)
      ..lineTo(size.width * .48, size.height * .52)
      ..lineTo(size.width * .43, size.height * .70)
      ..lineTo(size.width * .60, size.height * .45)
      ..lineTo(size.width * .50, size.height * .45)
      ..close();
    canvas.drawPath(bolt, Paint()..color = AppColors.surface);
  }

  @override
  bool shouldRepaint(_ChargingBatteryPainter oldDelegate) => false;
}
