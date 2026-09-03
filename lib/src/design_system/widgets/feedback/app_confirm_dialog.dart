import 'package:flutter/material.dart';

import '../dialogs/app_dialog.dart';

/// Yes/no confirmation, as a plain bool for the call sites that only branch on
/// "did the user agree".
///
/// The visuals live in [AppDialog]; this is the thin wrapper the app already
/// called everywhere, kept so no page has to learn a new signature.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = '取消',
  String confirmLabel = '确认',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showAppDialog(
    context,
    title: title,
    message: message,
    icon: icon,
    tone: destructive ? AppDialogTone.danger : AppDialogTone.primary,
    cancelLabel: cancelLabel,
    confirmLabel: confirmLabel,
  );
  return result ?? false;
}
