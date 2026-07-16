import 'package:flutter/material.dart';

import '../../tokens/app_spacing.dart';

class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    required this.value,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final Widget label;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox.square(
            dimension: 24,
            child: Checkbox(value: value, onChanged: onChanged),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: label),
        ],
      ),
    );
  }
}
