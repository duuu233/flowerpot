import 'package:flutter/foundation.dart';

/// 正在显示的 OTA 进度弹层（设置页「设备升级 / 固件版本更新」打开的底部进度层）。
///
/// 2026-10-26 产品：进度层开着、正在执行 OTA 时，所有 OTA 提醒弹窗都不弹——升级提醒
/// （`FirmwareReminderHost`）和割草机 DP116 拒绝 / 失败提示都由它判断；进度层自己会显示结果。
abstract final class OtaProgressLayer {
  /// 设备 ID → 打开着的进度层个数。变化时通知，提醒宿主据此重新评估。
  static final ValueNotifier<Map<String, int>> open =
      ValueNotifier<Map<String, int>>(const <String, int>{});

  static bool get anyOpen => open.value.isNotEmpty;

  static bool isOpenFor(String? deviceId) =>
      deviceId != null && open.value.containsKey(deviceId);

  static void opened(String deviceId) {
    final next = Map<String, int>.of(open.value);
    next[deviceId] = (next[deviceId] ?? 0) + 1;
    open.value = next;
  }

  static void closed(String deviceId) {
    final count = open.value[deviceId];
    if (count == null) return;
    final next = Map<String, int>.of(open.value);
    if (count <= 1) {
      next.remove(deviceId);
    } else {
      next[deviceId] = count - 1;
    }
    open.value = next;
  }

  @visibleForTesting
  static void resetForTest() => open.value = const <String, int>{};
}
