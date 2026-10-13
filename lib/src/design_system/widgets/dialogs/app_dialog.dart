import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_radius.dart';

/// The project's only prompt / confirmation dialog.
///
/// The layout follows the sibling `flutter` project's `AppDialog` — icon box on
/// the left, title and explanation beside it, a button row indented to line up
/// under the text — because Material's [AlertDialog] looks nothing like the
/// rest of these screens: square corners, a left-aligned title in the theme's
/// font scale and two bare text buttons. The one deliberate difference is the
/// palette: YSplanter is teal ([AppColors.brandPrimary]), not the reference
/// project's orange, so the confirm button is a `brandPrimary → brandDark`
/// gradient and the icon box is the accent at 10% opacity.
///
/// Every dialog in the app goes through here. Loading overlays
/// (`AppLoading`) and toasts (`showAppMessage`) are a different concern and
/// stay where they are.
enum AppDialogTone {
  /// Ordinary prompt or confirmation: teal icon box.
  primary,

  /// Delete, unbind, factory reset, sign out: red icon box. Only the *icon*
  /// turns red — the confirm button stays brand-coloured, so a destructive
  /// dialog does not read as a different component.
  danger,
}

extension AppDialogToneStyle on AppDialogTone {
  Color get accent => switch (this) {
    AppDialogTone.primary => AppColors.brandPrimary,
    AppDialogTone.danger => AppColors.danger,
  };

  IconData get fallbackIcon => switch (this) {
    AppDialogTone.primary => Icons.info_outline_rounded,
    AppDialogTone.danger => Icons.error_outline_rounded,
  };
}

/// Shows a confirmation dialog: 「确认」 returns true, 「取消」/barrier/back
/// return null.
///
/// [showCancel] false renders a single full-width confirm button, for
/// notice-only dialogs.
/// [waitForDismissal] waits until the exit transition removes the overlay
/// before returning, for flows that immediately open another dialog.
Future<bool?> showAppDialog(
  BuildContext context, {
  required String title,
  String? message,
  IconData? icon,
  AppDialogTone tone = AppDialogTone.primary,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  TextAlign messageTextAlign = TextAlign.start,
  bool showCancel = true,
  bool stackActions = false,
  bool barrierDismissible = true,
  bool waitForDismissal = false,
  Widget? content,
  Widget? footer,
}) async {
  // Double-tapping 确认 would pop twice and take the page underneath with it.
  var resolved = false;
  ModalRoute<bool>? route;
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .4),
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      route = ModalRoute.of<bool>(dialogContext);
      void close([bool? result]) {
        if (resolved) return;
        resolved = true;
        Navigator.of(dialogContext).pop(result);
      }

      return AppDialog(
        title: title,
        message: message,
        icon: icon,
        tone: tone,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        messageTextAlign: messageTextAlign,
        showCancel: showCancel,
        stackActions: stackActions,
        content: content,
        footer: footer,
        onCancel: close,
        onConfirm: () => close(true),
      );
    },
  );
  if (waitForDismissal) await route?.completed;
  return result;
}

/// Notice dialog: one full-width button, default 「我知道了」.
Future<void> showAppNoticeDialog(
  BuildContext context, {
  required String title,
  String? message,
  IconData? icon,
  AppDialogTone tone = AppDialogTone.primary,
  String confirmLabel = '我知道了',
  bool barrierDismissible = true,
}) async {
  await showAppDialog(
    context,
    title: title,
    message: message,
    icon: icon,
    tone: tone,
    confirmLabel: confirmLabel,
    showCancel: false,
    barrierDismissible: barrierDismissible,
  );
}

/// Prompts for a single line of text. Returns the trimmed value, or null when
/// cancelled or left empty.
Future<String?> showAppInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? initialValue,
  String? hintText,
  int? maxLength,
  IconData icon = Icons.edit_outlined,
  String confirmLabel = '保存',
  TextInputType? keyboardType,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  try {
    final confirmed = await showAppDialog(
      context,
      title: title,
      message: message,
      icon: icon,
      confirmLabel: confirmLabel,
      content: AppDialogTextField(
        controller: controller,
        hintText: hintText,
        maxLength: maxLength,
        keyboardType: keyboardType,
      ),
    );
    if (confirmed != true) return null;
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  } finally {
    controller.dispose();
  }
}

/// The dialog body. Use [showAppDialog] unless the dialog has to be embedded in
/// a page that draws its own barrier.
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.onConfirm,
    super.key,
    this.message,
    this.icon,
    this.tone = AppDialogTone.primary,
    this.confirmLabel = '确认',
    this.cancelLabel = '取消',
    this.messageTextAlign = TextAlign.start,
    this.showCancel = true,
    this.stackActions = false,
    this.content,
    this.footer,
    this.onCancel,
    this.confirmKey = const Key('app-dialog-confirm'),
    this.cancelKey = const Key('app-dialog-cancel'),
  });

  final String title;
  final String? message;
  final IconData? icon;
  final AppDialogTone tone;
  final String confirmLabel;
  final String cancelLabel;
  final TextAlign messageTextAlign;
  final bool showCancel;

  /// 长确认文案时纵向排列两颗全宽按钮，保持文案完整。
  final bool stackActions;

  /// Custom content under the explanation — an input field, a picker — laid
  /// out full width.
  final Widget? content;

  /// 画在**按钮下面**的一小段补充说明。
  ///
  /// 和 [content] 的区别只有位置：[content] 在正文和按钮之间，这个在按钮之后。
  /// 「未检测到植物」那个弹窗的「忽略检测结果，可前往设置关闭植物自动检测」就摆在
  /// 这里（2026-09-12 产品指定的版式）。
  final Widget? footer;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  /// Overridable so a screen-specific dialog keeps the button keys its own
  /// tests already drive.
  final Key confirmKey;
  final Key cancelKey;

  @override
  Widget build(BuildContext context) {
    final accent = tone.accent;
    final text = message?.trim() ?? '';
    final confirmButton = AppDialogButton(
      key: confirmKey,
      label: confirmLabel,
      textColor: AppColors.surface,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[AppColors.brandPrimary, AppColors.brandDark],
      ),
      onTap: onConfirm,
    );
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: SizedBox.square(
                    dimension: 46,
                    child: Icon(
                      icon ?? tone.fallbackIcon,
                      color: accent,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      if (text.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 7),
                        Text(
                          text,
                          textAlign: messageTextAlign,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (content case final Widget body) ...<Widget>[
              const SizedBox(height: 16),
              body,
            ],
            const SizedBox(height: 20),
            Padding(
              // Lines the buttons up with the text column rather than the
              // icon box.
              padding: EdgeInsets.only(left: stackActions ? 0 : 60),
              child: showCancel && stackActions
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        confirmButton,
                        const SizedBox(height: 12),
                        AppDialogButton(
                          key: cancelKey,
                          label: cancelLabel,
                          textColor: AppColors.textPrimary,
                          background: AppColors.brandSurface,
                          onTap: onCancel,
                        ),
                      ],
                    )
                  : showCancel
                  ? Row(
                      children: <Widget>[
                        Expanded(
                          child: AppDialogButton(
                            key: cancelKey,
                            label: cancelLabel,
                            textColor: AppColors.textPrimary,
                            background: AppColors.brandSurface,
                            onTap: onCancel,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: confirmButton),
                      ],
                    )
                  : confirmButton,
            ),
            if (footer case final Widget note) ...<Widget>[
              const SizedBox(height: 12),
              Padding(
                // 和按钮对齐，同样避开左边的图标框。
                padding: const EdgeInsets.only(left: 60),
                child: note,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Input field for [AppDialog.content].
class AppDialogTextField extends StatelessWidget {
  const AppDialogTextField({
    required this.controller,
    super.key,
    this.hintText,
    this.maxLength,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String? hintText;
  final int? maxLength;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: AppRadius.small,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          maxLines: maxLines,
          keyboardType: keyboardType,
          cursorColor: AppColors.brandPrimary,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.3,
          ),
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            // The counter adds a line of height glued to the card's bottom
            // edge; screens that need a count draw their own.
            counterText: '',
            hintText: hintText,
            hintStyle: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill button used by [AppDialog] and by the dialogs that build their own
/// action row (option picker, schedule editor).
class AppDialogButton extends StatelessWidget {
  const AppDialogButton({
    required this.label,
    required this.textColor,
    required this.onTap,
    super.key,
    this.background,
    this.gradient,
  });

  final String label;
  final Color textColor;
  final VoidCallback? onTap;
  final Color? background;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        gradient: gradient,
        borderRadius: AppRadius.full,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.full,
        child: InkWell(
          borderRadius: AppRadius.full,
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
