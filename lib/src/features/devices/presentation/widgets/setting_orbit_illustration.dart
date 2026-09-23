import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

enum DeviceSettingSymbol { brightness, sound, vibration, touch, plant, led }

class DeviceSettingOrbitIllustration extends StatelessWidget {
  const DeviceSettingOrbitIllustration({required this.symbol, super.key});

  static const double orbitSize = 159;

  /// 卡片顶到轨道外圈的距离（稿子 23）。卡片里插图区仍是 184 高：23 + 159 = 182。
  static const double topInset = 23;

  final DeviceSettingSymbol symbol;

  @override
  Widget build(BuildContext context) {
    // 稿子（246:6815 / 247:7033 / 244:6485 / 246:6931）轨道外圈 159（素材 318 = 159@2x），
    // 原来画到 184 大了 16%；中间符号按同一比例 ×0.86（听觉声波 78 → 稿子 65×62）。
    final baseSize = switch (symbol) {
      DeviceSettingSymbol.brightness => 62.0,
      DeviceSettingSymbol.sound => 78.0,
      DeviceSettingSymbol.vibration => 76.0,
      DeviceSettingSymbol.touch => 68.0,
      DeviceSettingSymbol.plant => 66.0,
      DeviceSettingSymbol.led => 66.0,
    };
    final symbolSize = baseSize * orbitSize / 184;
    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Image.asset(
            AppAssets.settingOrbitBackground,
            width: orbitSize,
            height: orbitSize,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
          if (_assetFor(symbol) case final String asset)
            Image.asset(
              asset,
              width: symbolSize,
              height: symbolSize,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: _semanticLabelFor(symbol),
            )
          else
            Icon(
              _iconFor(symbol),
              size: symbolSize,
              color: AppColors.brandPrimary,
              semanticLabel: _semanticLabelFor(symbol),
            ),
        ],
      ),
    );
  }

  /// 没有专属素材的符号返回 null，改用 [_iconFor] 画一个矢量图标。
  ///
  /// LED 和自动检测植物就是这种情况：LED 原来和「显示」共用 `brightness_symbol`，
  /// 两页并排看是同一张图；自动检测植物没有对应素材。等 UI 出正式插画后，把这里
  /// 补上 asset 即可，页面不用改。
  String? _assetFor(DeviceSettingSymbol symbol) => switch (symbol) {
    DeviceSettingSymbol.brightness => AppAssets.brightnessSymbol,
    DeviceSettingSymbol.sound => AppAssets.hearingWaveformSymbol,
    DeviceSettingSymbol.vibration => AppAssets.vibrationSymbol,
    DeviceSettingSymbol.touch => AppAssets.touchGestureSymbol,
    DeviceSettingSymbol.plant || DeviceSettingSymbol.led => null,
  };

  IconData _iconFor(DeviceSettingSymbol symbol) => switch (symbol) {
    DeviceSettingSymbol.led => Icons.lightbulb_outline,
    DeviceSettingSymbol.plant => Icons.eco_outlined,
    _ => Icons.settings_outlined,
  };

  String _semanticLabelFor(DeviceSettingSymbol symbol) => switch (symbol) {
    DeviceSettingSymbol.brightness => '显示亮度',
    DeviceSettingSymbol.sound => '听觉感知',
    DeviceSettingSymbol.vibration => '震动设置',
    DeviceSettingSymbol.touch => '触觉感知',
    DeviceSettingSymbol.plant => '自动检测植物',
    DeviceSettingSymbol.led => 'LED',
  };
}
