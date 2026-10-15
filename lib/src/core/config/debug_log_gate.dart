import 'package:flutter/foundation.dart';

/// 构建时统一控制联调界面与应用调试日志；未传参数时保留现有联调能力。
abstract final class DebugLogGate {
  /// 用户包传 --dart-define=APP_DEBUG_TOOLS=false，运行中不可重新打开。
  static const bool enabled = bool.fromEnvironment(
    'APP_DEBUG_TOOLS',
    defaultValue: true,
  );

  static bool _interactionLog = true;

  /// 保留现有运行时/测试开关，但不能越过构建时总闸。
  static bool get interactionLog => enabled && _interactionLog;
  static set interactionLog(bool value) => _interactionLog = value;

  static void log(String? message, {int? wrapWidth}) {
    if (enabled) debugPrint(message, wrapWidth: wrapWidth);
  }

  static void reset() => _interactionLog = true;
}
