import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// Stands in for a trend chart whose series came back empty.
///
/// Five of the eight report metrics — temperature, humidity, battery, PPFD and
/// DLI — have no history function point in this product's DP table, and the
/// three that do (water level, soil moisture, light) stay empty until the
/// device has reported a full window. Plotting the current reading as a
/// single-point line made both cases look like a measured trend, so the card
/// says there is nothing yet instead.
class MetricHistoryEmptyCard extends StatelessWidget {
  const MetricHistoryEmptyCard({
    required this.title,
    super.key,
    this.message = '设备还没有上报这段时间的历史数据。',
    this.height = 220,
  });

  final String title;
  final String message;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: SizedBox(
        height: height,
        child: AppEmptyState(title: title, message: message),
      ),
    );
  }
}
