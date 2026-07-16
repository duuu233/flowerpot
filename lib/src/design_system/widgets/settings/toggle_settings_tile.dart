import 'package:flutter/material.dart';

import 'app_settings_tile.dart';

class ToggleSettingsTile extends StatelessWidget {
  const ToggleSettingsTile({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.icon,
    this.subtitle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return AppSettingsTile(
      title: title,
      icon: icon,
      subtitle: subtitle,
      trailing: Switch(value: value, onChanged: onChanged),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}
