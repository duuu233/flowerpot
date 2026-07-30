import 'package:flutter/material.dart';

import '../../tokens/app_assets.dart';

class AppDevicePlaceholder extends StatelessWidget {
  const AppDevicePlaceholder({
    required this.hasPlant,
    super.key,
    this.width = 106,
  });

  final bool hasPlant;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = hasPlant ? width * 1.29 : width;
    return Semantics(
      label: hasPlant ? '带植物的 YSplanter' : 'YSplanter 设备',
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        child: Image.asset(
          hasPlant
              ? AppAssets.smartPlanterWithPlant
              : AppAssets.smartPlanterDevice,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
