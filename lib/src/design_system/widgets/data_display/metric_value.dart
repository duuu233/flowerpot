import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';

class MetricValue extends StatelessWidget {
  const MetricValue({
    required this.value,
    required this.unit,
    super.key,
    this.label,
    this.color = AppColors.textPrimary,
  });

  final String value;
  final String unit;
  final String? label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: color),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(unit, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
        if (label != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(label!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}
