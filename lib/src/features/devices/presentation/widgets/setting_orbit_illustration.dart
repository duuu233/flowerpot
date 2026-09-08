import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

enum DeviceSettingSymbol { brightness, sound, vibration, touch, plant }

class DeviceSettingOrbitIllustration extends StatelessWidget {
  const DeviceSettingOrbitIllustration({required this.symbol, super.key});

  final DeviceSettingSymbol symbol;

  @override
  Widget build(BuildContext context) {
    final symbolSize = switch (symbol) {
      DeviceSettingSymbol.brightness => 62.0,
      DeviceSettingSymbol.sound => 78.0,
      DeviceSettingSymbol.vibration => 76.0,
      DeviceSettingSymbol.touch => 68.0,
      DeviceSettingSymbol.plant => 66.0,
    };
    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Image.asset(
            AppAssets.settingOrbitBackground,
            width: 184,
            height: 184,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
          Image.asset(
            _assetFor(symbol),
            width: symbolSize,
            height: symbolSize,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: _semanticLabelFor(symbol),
          ),
        ],
      ),
    );
  }

  String _assetFor(DeviceSettingSymbol symbol) => switch (symbol) {
    DeviceSettingSymbol.brightness => AppAssets.brightnessSymbol,
    DeviceSettingSymbol.sound => AppAssets.hearingWaveformSymbol,
    DeviceSettingSymbol.vibration => AppAssets.vibrationSymbol,
    DeviceSettingSymbol.touch => AppAssets.touchGestureSymbol,
    DeviceSettingSymbol.plant => AppAssets.selectPlantIcon,
  };

  String _semanticLabelFor(DeviceSettingSymbol symbol) => switch (symbol) {
    DeviceSettingSymbol.brightness => '显示亮度',
    DeviceSettingSymbol.sound => '听觉感知',
    DeviceSettingSymbol.vibration => '震动设置',
    DeviceSettingSymbol.touch => '触觉感知',
    DeviceSettingSymbol.plant => '自动检测植物',
  };
}
