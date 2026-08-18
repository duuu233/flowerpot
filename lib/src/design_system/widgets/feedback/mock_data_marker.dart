import 'package:flutter/material.dart';

import '../../../core/config/debug_tools_config.dart';
import '../../tokens/app_colors.dart';
import '../../tokens/app_radius.dart';
import '../../tokens/app_spacing.dart';
import '../../tokens/app_typography.dart';

/// Development markers that separate simulated content from real SDK data.
///
/// These are deliberately not `App`-prefixed product components: they exist so
/// a screen full of placeholder values cannot be mistaken for a real device
/// during SDK integration, and they disappear from release builds unless
/// [DebugToolsConfig] is explicitly turned on.
///
/// Use [MockDataBanner] when a whole page or section is simulated, and
/// [MockDataBadge] next to a single value. [LiveDataBadge] marks the opposite —
/// the few places that really do reach the native bridge.
class MockDataBadge extends StatelessWidget {
  const MockDataBadge({super.key, this.label = '测试数据', this.visible = true});

  final String label;

  /// Set false when the surrounding value happens to be real, for example a
  /// page that shows mock numbers only while the mock backend answers.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible || !DebugToolsConfig.enabled) return const SizedBox.shrink();
    return _MarkerChip(
      label: label,
      icon: Icons.science_outlined,
      foreground: AppColors.warning,
      background: AppColors.warningSurface,
    );
  }
}

/// Marks content that genuinely comes from the native Tuya bridge, so the real
/// steps of a flow stand out from the simulated ones around them.
class LiveDataBadge extends StatelessWidget {
  const LiveDataBadge({super.key, this.label = '真实 SDK', this.visible = true});

  final String label;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible || !DebugToolsConfig.enabled) return const SizedBox.shrink();
    return _MarkerChip(
      label: label,
      icon: Icons.verified_outlined,
      foreground: AppColors.success,
      background: AppColors.successSurface,
    );
  }
}

/// Full-width notice for a page or section whose content is simulated.
class MockDataBanner extends StatelessWidget {
  const MockDataBanner({
    required this.message,
    super.key,
    this.title = '模拟数据',
    this.visible = true,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
  });

  final String message;
  final String title;
  final bool visible;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!visible || !DebugToolsConfig.enabled) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.warningSurface,
          borderRadius: AppRadius.card,
          border: Border.all(color: AppColors.warningSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.science_outlined,
                size: 16,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTypography.smallBody.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      message,
                      style: AppTypography.smallBody.copyWith(
                        color: AppColors.textSecondary,
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
  }
}

class _MarkerChip extends StatelessWidget {
  const _MarkerChip({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.full,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label,
              style: AppTypography.smallBody.copyWith(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
