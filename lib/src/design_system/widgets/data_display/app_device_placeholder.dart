import 'package:flutter/material.dart';

import '../../tokens/app_assets.dart';

class AppDevicePlaceholder extends StatelessWidget {
  const AppDevicePlaceholder({
    required this.hasPlant,
    super.key,
    this.width = 106,
    this.productName = '设备',
  });

  final bool hasPlant;
  final double width;

  /// 无障碍标签里称呼设备的名字：涂鸦产品名（`FlowerpotState.productNameLabel`）。
  final String productName;

  @override
  Widget build(BuildContext context) {
    final height = hasPlant ? width * 1.29 : width;
    return Semantics(
      label: hasPlant ? '带植物的$productName' : productName,
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
