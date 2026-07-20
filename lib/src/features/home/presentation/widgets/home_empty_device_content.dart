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
  });

  final String userLabel;
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
                          top: 16,
                          left: horizontalPadding,
                          right: horizontalPadding,
                          child: HomeHeader(
                            userLabel: userLabel,
                            showGenericAvatar: true,
                            onAvatarTap: onAvatarTap,
                          ),
                        ),
                        const Positioned(
                          top: 88,
                          left: 0,
                          right: 0,
                          child: Center(child: _EmptyDeviceRadar()),
                        ),
                        const Positioned(
                          top: 304,
                          left: 12,
                          right: 12,
                          child: Text(
                            '暂无设备',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const Positioned(
                          top: 350,
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
                          bottom: 135,
                          child: SizedBox(
                            height: 50,
                            child: AppPrimaryButton(
                              key: const Key('add-device-button'),
                              label: '添加设备',
                              onPressed: onAddDevice,
                            ),
                          ),
                        ),
                        Positioned(
                          left: horizontalPadding + 8,
                          right: horizontalPadding + 8,
                          bottom: 10,
                          child: const _EmptyDeviceTipCard(),
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
    return const SizedBox.square(
      dimension: 230,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _RadarDisc(size: 226, opacity: .24),
          _RadarDisc(size: 174, opacity: .35),
          _RadarDisc(size: 126, opacity: .48),
          Positioned(left: 24, top: 30, child: _RadarDot(size: 9)),
          Positioned(right: 22, top: 51, child: _RadarDot(size: 10)),
          Positioned(left: 36, bottom: 20, child: _RadarDot(size: 14)),
          Positioned(right: 30, bottom: 32, child: _RadarDot(size: 8)),
          _EmptyWifiHub(),
        ],
      ),
    );
  }
}

class _RadarDisc extends StatelessWidget {
  const _RadarDisc({required this.size, required this.opacity});

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

class _RadarDot extends StatelessWidget {
  const _RadarDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandSoft.withValues(alpha: .45),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _EmptyWifiHub extends StatelessWidget {
  const _EmptyWifiHub();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          const Positioned(
            top: 0,
            child: Icon(
              Icons.wifi_rounded,
              color: AppColors.brandPrimary,
              size: 57,
            ),
          ),
          Container(
            width: 72,
            height: 33,
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

class _EmptyDeviceTipCard extends StatelessWidget {
  const _EmptyDeviceTipCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.brandSurfaceAlt,
        borderRadius: AppRadius.card,
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, 13),
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
                    '1. 打开设备电源\n2. 请将设备放在手机附近',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
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
              angle: .785,
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
