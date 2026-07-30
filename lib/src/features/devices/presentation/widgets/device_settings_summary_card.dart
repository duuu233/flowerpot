import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/device_settings_page_model.dart';

class DeviceSettingsSummaryCard extends StatelessWidget {
  const DeviceSettingsSummaryCard({
    required this.model,
    required this.onMore,
    super.key,
  });

  final DeviceSettingsPageModel model;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 106,
      child: AppSurfaceCard(
        onTap: onMore,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        borderRadius: AppRadius.large,
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 70,
              child: Center(
                child: AppDevicePlaceholder(hasPlant: true, width: 58),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    model.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.deviceTitle.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AppStatusChip(
                      label: '已陪伴${model.companionDays}天',
                      textStyle: AppTypography.compactBody.copyWith(
                        color: AppColors.brandPrimary,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '更多',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Image.asset(
              AppAssets.chevronRightIcon,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ],
        ),
      ),
    );
  }
}
