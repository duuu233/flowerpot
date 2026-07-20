import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';

class PairingSuccessPage extends StatelessWidget {
  const PairingSuccessPage({required this.deviceId, super.key});

  final String deviceId;

  void _addPlant(BuildContext context) {
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.plantPicker,
      arguments: deviceId,
    );
  }

  void _returnHome(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.shell, (_) => false);
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
            key: const Key('pairing-success-scroll-view'),
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
                      child: Center(child: _SuccessRadar()),
                    ),
                    const Positioned(
                      top: 315,
                      left: 12,
                      right: 12,
                      child: Text(
                        '连接成功',
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
                        '设备已成功连接，可以开始添加植物了',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                    Positioned(
                      left: horizontalPadding,
                      right: horizontalPadding,
                      bottom: 75,
                      child: SizedBox(
                        height: 50,
                        child: FilledButton(
                          key: const Key('success-add-plant-button'),
                          onPressed: () => _addPlant(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brandPrimary,
                            foregroundColor: AppColors.surface,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 19),
                          ),
                          child: const Text('添加植物'),
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
                          key: const Key('success-return-home-button'),
                          onPressed: () => _returnHome(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.brandPrimary,
                            side: const BorderSide(
                              color: AppColors.brandPrimary,
                            ),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 19),
                          ),
                          child: const Text('返回首页'),
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

class _SuccessRadar extends StatelessWidget {
  const _SuccessRadar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 235,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _SuccessDisc(size: 230, opacity: .24),
          _SuccessDisc(size: 176, opacity: .35),
          _SuccessDisc(size: 126, opacity: .48),
          Positioned(left: 26, top: 29, child: _SuccessDot(size: 9)),
          Positioned(right: 25, top: 49, child: _SuccessDot(size: 10)),
          Positioned(left: 35, bottom: 18, child: _SuccessDot(size: 14)),
          Positioned(right: 31, bottom: 29, child: _SuccessDot(size: 8)),
          _SuccessWifiHub(),
        ],
      ),
    );
  }
}

class _SuccessDisc extends StatelessWidget {
  const _SuccessDisc({required this.size, required this.opacity});

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

class _SuccessDot extends StatelessWidget {
  const _SuccessDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandSoft.withValues(alpha: .42),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _SuccessWifiHub extends StatelessWidget {
  const _SuccessWifiHub();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            left: 9,
            top: 4,
            child: SizedBox(
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
            ),
          ),
          const Positioned(
            right: 3,
            bottom: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.brandPrimary,
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: AppColors.surface, width: 1.5),
                ),
              ),
              child: SizedBox.square(
                dimension: 39,
                child: Icon(
                  Icons.check_rounded,
                  color: AppColors.surface,
                  size: 29,
                ),
              ),
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
