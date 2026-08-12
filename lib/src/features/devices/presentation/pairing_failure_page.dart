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
      background: AppPageBackground.account,
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
                        key: Key('pairing-failure-title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
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
    return Image.asset(
      AppAssets.pairingFailureIllustration,
      width: 235,
      height: 235,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
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
