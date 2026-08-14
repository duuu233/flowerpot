import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import 'home_header.dart';

class HomeEmptyDeviceContent extends StatelessWidget {
  const HomeEmptyDeviceContent({
    required this.userLabel,
    required this.onRefresh,
    required this.onAvatarTap,
    required this.onAddDevice,
    super.key,
    this.avatarImage,
  });

  final String userLabel;
  final ImageProvider<Object>? avatarImage;
  final Future<void> Function() onRefresh;
  final VoidCallback onAvatarTap;
  final VoidCallback onAddDevice;

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
            key: const Key('empty-device-scroll-view'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: SizedBox(
                  height: contentHeight,
                  child: ResponsiveContent(
                    maxWidth: 375,
                    padding: EdgeInsets.zero,
                    child: Stack(
                      children: <Widget>[
                        Positioned(
                          top: AppSpacing.huge,
                          left: horizontalPadding,
                          right: horizontalPadding,
                          child: HomeHeader(
                            userLabel: userLabel,
                            avatarImage: avatarImage,
                            onAvatarTap: onAvatarTap,
                          ),
                        ),
                        const Positioned(
                          top: 78,
                          left: 0,
                          right: 0,
                          child: Center(child: _EmptyDeviceRadar()),
                        ),
                        const Positioned(
                          top: 325,
                          left: 12,
                          right: 12,
                          child: Text(
                            '暂无设备',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const Positioned(
                          top: 365,
                          left: 18,
                          right: 18,
                          child: Text(
                            '还没有连接智能花盆，请先添加设备开始养护吧',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        ),
                        Positioned(
                          left: horizontalPadding,
                          right: horizontalPadding,
                          bottom: 12,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                height: 50,
                                child: AppPrimaryButton(
                                  key: const Key('add-device-button'),
                                  label: '添加设备',
                                  onPressed: onAddDevice,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxl),
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                                child: _EmptyDeviceTipCard(),
                              ),
                            ],
                          ),
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

class _EmptyDeviceRadar extends StatelessWidget {
  const _EmptyDeviceRadar();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.settingOrbitBackground,
      width: 244,
      height: 244,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
  }
}

class _EmptyDeviceTipCard extends StatelessWidget {
  const _EmptyDeviceTipCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('empty-device-tip-card'),
      decoration: const BoxDecoration(
        color: AppColors.brandSurfaceAlt,
        borderRadius: AppRadius.card,
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _QuestionBubble(),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '小提示',
                    style: TextStyle(
                      color: AppColors.brandPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    '1. 打开设备电源\n2. 请将设备放在手机附近',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.6,
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
      width: 30,
      height: 30,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '提示',
    );
  }
}
