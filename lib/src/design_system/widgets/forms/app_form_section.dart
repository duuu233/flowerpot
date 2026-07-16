import 'package:flutter/material.dart';

import '../../tokens/app_spacing.dart';

class AppFormSection extends StatelessWidget {
  const AppFormSection({
    required this.children,
    super.key,
    this.title,
    this.description,
    this.spacing = AppSpacing.md,
  });

  final String? title;
  final String? description;
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title != null)
          Text(title!, style: Theme.of(context).textTheme.titleMedium),
        if (description != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(description!, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (title != null || description != null)
          const SizedBox(height: AppSpacing.lg),
        for (var index = 0; index < children.length; index++) ...<Widget>[
          children[index],
          if (index < children.length - 1) SizedBox(height: spacing),
        ],
      ],
    );
  }
}
