import 'package:flutter/material.dart';

import '../../tokens/app_spacing.dart';
import '../data_display/app_option_tile.dart';

class AppOption<T> {
  const AppOption({required this.value, required this.label, this.subtitle});

  final T value;
  final String label;
  final String? subtitle;
}

Future<T?> showAppOptionDialog<T>(
  BuildContext context, {
  required String title,
  required List<AppOption<T>> options,
  required T selected,
  String cancelLabel = '取消',
  String confirmLabel = '确认',
}) {
  var current = selected;
  return showDialog<T>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (
                    var index = 0;
                    index < options.length;
                    index++
                  ) ...<Widget>[
                    AppOptionTile(
                      label: options[index].label,
                      subtitle: options[index].subtitle,
                      selected: options[index].value == current,
                      onTap: () =>
                          setState(() => current = options[index].value),
                    ),
                    if (index < options.length - 1)
                      const SizedBox(height: AppSpacing.xxs),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(current),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  );
}
