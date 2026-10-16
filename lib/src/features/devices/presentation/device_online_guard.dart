import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';

/// 设备离线时统一的提示文案。
const String deviceOfflineMessage = '设备已离线';

final Set<NavigatorState> _offlineNoticeNavigators = <NavigatorState>{};

/// 割草机离线仍可浏览和编辑；提交时提示，留在当前页且保留草稿。
/// 同一导航栈只显示一张离线提示，关闭后再次操作仍会提示。
void showMowerOfflineNotice(BuildContext context) {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (!_offlineNoticeNavigators.add(navigator)) return;
  unawaited(
    showAppNoticeDialog(
      context,
      title: '提示',
      message: deviceOfflineMessage,
      icon: Icons.wifi_off_rounded,
    ).whenComplete(() => _offlineNoticeNavigators.remove(navigator)),
  );
}

/// 设备在线门禁。**页面侧的统一入口**。
///
/// 产品口径（2026-09-12）：设备列表页、设备详情页能点进去的相关页面，以及任何
/// 下发 DP 的动作，都要先判断设备在不在线；不在线就提示「设备已离线」并回到设备
/// 列表页。
///
/// 割草机例外（2026-10-16）：正文可交互，提交离线时弹框并留在当前页面。
/// 在线判断本身只有一处——[FlowerpotState.isDeviceOnline]，DP 下发那一路在
/// `FlowerpotState._publishDps` 里用的是同一个方法，所以页面漏加这道门禁时指令
/// 也发不出去。这里只负责提示和跳转。
///
/// 返回 true 表示可以继续；false 表示已经提示过、并且（除非本来就在最外层）已经
/// 退回设备列表页，调用方直接 return 即可。
bool ensureDeviceOnline(BuildContext context, String deviceId) {
  final state = FlowerpotScope.of(context);
  if (state.isDeviceOnline(deviceId)) return true;
  final device = state.deviceById(deviceId);
  if (device != null && state.isMowerDevice(device)) {
    showMowerOfflineNotice(context);
    return false;
  }
  showAppMessage(context, deviceOfflineMessage, tone: AppMessageTone.error);
  backToDeviceList(context);
  return false;
}

/// 退回设备列表页。
///
/// 列表页是 shell 的首页（有设备时 `AppShell` 画的就是它），所以退到最外层那一层
/// 就是列表页——不额外 push 一个 `/devices/list`，免得栈里出现两个列表。
void backToDeviceList(BuildContext context) {
  final navigator = Navigator.of(context);
  if (!navigator.canPop()) return;
  navigator.popUntil((route) => route.isFirst);
}

/// [FlowerpotState._publishDps] 拦下离线设备时用的错误码。
const String deviceOfflineCode = 'device_offline';

/// 统一处理一次设备操作的结果。
///
/// 下发 DP 之前状态层已经判过在线，离线时抛出的 `device_offline` 一路带着 code
/// 回到这里，所以页面不用各自再判一次——失败就提示，是离线就再退回设备列表页。
///
/// [announceSuccess] 对应原来写成
/// `tone: result.success ? AppMessageTone.success : AppMessageTone.error` 的那些
/// 调用：成功时也要弹一条。默认只在失败时提示。
void showDeviceActionResult(
  BuildContext context,
  ActionResult result, {
  bool announceSuccess = false,
  String? deviceId,
}) {
  if (result.success) {
    if (announceSuccess) showAppMessage(context, result.message);
    return;
  }
  final device = deviceId == null
      ? null
      : FlowerpotScope.of(context).deviceById(deviceId);
  if (result.code == deviceOfflineCode &&
      device != null &&
      FlowerpotScope.of(context).isMowerDevice(device)) {
    showMowerOfflineNotice(context);
    return;
  }
  showAppMessage(context, result.message, tone: AppMessageTone.error);
  if (result.code == deviceOfflineCode) backToDeviceList(context);
}

/// 花盆离线正文只读；割草机页面不按列表online限制交互。
/// 标题栏和返回导航保留，恢复在线后自动放行。
class DeviceOnlineBody extends StatelessWidget {
  const DeviceOnlineBody({
    required this.deviceId,
    required this.child,
    super.key,
  });
  final String? deviceId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final online = deviceId != null && state.isDeviceOnline(deviceId!);
    final device = deviceId == null ? null : state.deviceById(deviceId!);
    if (online || (device != null && state.isMowerDevice(device))) return child;
    return Column(
      children: [
        if (!online)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('设备已离线，暂时无法操作', key: Key('device-offline-read-only')),
          ),
        Expanded(
          child: AbsorbPointer(
            absorbing: !online,
            child: ExcludeFocus(
              excluding: !online,
              child: Opacity(opacity: online ? 1 : .45, child: child),
            ),
          ),
        ),
      ],
    );
  }
}
