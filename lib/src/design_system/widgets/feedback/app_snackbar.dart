import 'package:flutter/material.dart';

import '../../../shared/widgets/app_toast.dart';

enum AppMessageTone { success, error, info }

void showAppMessage(
  BuildContext context,
  String message, {
  AppMessageTone tone = AppMessageTone.success,
}) {
  final toastTone = switch (tone) {
    AppMessageTone.success => AppToastTone.success,
    AppMessageTone.error => AppToastTone.error,
    AppMessageTone.info => AppToastTone.info,
  };
  AppToast.show(context, message, tone: toastTone);
}
