import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/home_dashboard_model.dart';
import 'home_companion_badge.dart';
import 'home_header.dart';

class HomeUnplantedContent extends StatelessWidget {
  const HomeUnplantedContent({
    required this.model,
    required this.onRefresh,
    required this.onAddPlant,
    super.key,
    this.avatarImage,
    this.onAvatarTap,
    this.onBack,
  });

  final HomeDashboardModel model;
  final ImageProvider<Object>? avatarImage;
  final Future<void> Function() onRefresh;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onBack;
  final VoidCallback onAddPlant;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 360 ? 12.0 : 20.0;
        final contentHeight = constraints.maxHeight < 690
            ? 690.0
            : constraints.maxHeight;
        return RefreshIndicator(
          color: AppColors.brandPrimary,
          onRefresh: onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: SizedBox(
                  height: contentHeight,
                  child: ResponsiveContent(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.xl,
                      horizontalPadding,
                      74,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        HomeHeader(
                          userLabel: model.userLabel,
                          avatarImage: avatarImage,
                          onAvatarTap: onAvatarTap,
                          onBack: onBack,
                        ),
                        const SizedBox(height: 37),
                        _UnplantedHero(model: model),
                        const SizedBox(height: 15),
                        Text(
                          model.emptyTitle,
                          textAlign: TextAlign.center,
                          style: AppTypography.emptyStateTitle.copyWith(
                            fontSize: 26,
                            height: 1.45,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          model.emptyMessage,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(
                            height: 1.75,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        AppPrimaryButton(
                          label: model.addPlantLabel,
                          onPressed: onAddPlant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UnplantedHero extends StatelessWidget {
  const _UnplantedHero({required this.model});

  final HomeDashboardModel model;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 263,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: <Widget>[
              Positioned(
                top: 78,
                left: (constraints.maxWidth - 106) / 2,
                child: Image.asset(
                  AppAssets.smartPlanterDevice,
                  width: 106,
                  height: 106,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  semanticLabel: 'YSplanter 设备',
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: HomeCompanionBadge(
                    companionDays: model.companionDays,
                    battery: model.battery,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
