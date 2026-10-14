import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_radius.dart';
import '../../tokens/app_spacing.dart';
import '../data_display/app_option_tile.dart';
import 'app_dialog.dart';
import 'app_dialog_scroll_view.dart';

class AppOption<T> {
  const AppOption({required this.value, required this.label, this.subtitle});

  final T value;
  final String label;
  final String? subtitle;
}

/// Single-choice picker (temperature unit, clock format, language…).
///
/// Same shell as [AppDialog] — the option list simply replaces the icon/title
/// row, since a list of choices already says what the dialog is for and the
/// icon box would push every row 60 px to the right.
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
    barrierColor: Colors.black.withValues(alpha: .4),
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        return Dialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Flexible(
                  child: AppDialogScrollView(
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
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppDialogButton(
                        key: const Key('app-option-dialog-cancel'),
                        label: cancelLabel,
                        textColor: AppColors.textPrimary,
                        background: AppColors.brandSurface,
                        onTap: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppDialogButton(
                        key: const Key('app-option-dialog-confirm'),
                        label: confirmLabel,
                        textColor: AppColors.surface,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            AppColors.brandPrimary,
                            AppColors.brandDark,
                          ],
                        ),
                        onTap: () => Navigator.of(dialogContext).pop(current),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
