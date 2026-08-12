import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import 'plant_picker_page.dart';

class PairingSuccessPage extends StatelessWidget {
  const PairingSuccessPage({required this.deviceId, super.key});

  final String deviceId;

  void _addPlant(BuildContext context) {
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.plantPicker,
      arguments: PlantPickerArguments(
        deviceId: deviceId,
        mode: PlantPickerMode.add,
      ),
    );
  }

  void _returnHome(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.shell, (_) => false);
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
                        key: Key('pairing-success-title'),
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
    return Image.asset(
      AppAssets.pairingSuccessIllustration,
      width: 235,
      height: 235,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
  }
}
