import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../messages/device_messages_view.dart';
import 'widgets/message_monitor_console.dart';

/// 花盆的消息通知（2026-09-28 产品：「给花盆也加一个消息通知页面，照割草机的做」）。
///
/// 入口在设备「设置」页功能列表里的「消息通知」。列表本身和割草机是同一个 [DeviceMessagesView]：
/// 三栏都来自涂鸦消息中心（这台设备的告警档，翻页取全），按平台推送规则的等级分——
/// **日志 = 通知、提醒 = 轻微、告警 = 严重**，认不出等级的归告警；日期筛选默认全部，来推送自动重拉。
/// 花盆没有底部导航。
///
/// 列表下面挂着 [MessageMonitorConsole]（同日产品追加，排查设施）：涂鸦后台「设备消息监控」里那批记录
/// 原样写死，按记录的参数写死去调接口，逐条对 App 这边查不查得到。联调完删掉这一个 `footer` 即可。
class DeviceMessagesPage extends StatelessWidget {
  const DeviceMessagesPage({
    required this.deviceId,
    super.key,
    this.showMonitorConsole = true,
  });

  final String deviceId;

  /// 底部挂不挂调试台（用例里只看列表时关掉）。
  final bool showMonitorConsole;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '消息通知', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: DeviceMessagesView(
        deviceId: deviceId,
        pageName: '花盆-消息通知',
        keyPrefix: 'device-messages',
        logsEntry: false,
        footer: showMonitorConsole ? const MessageMonitorConsole() : null,
      ),
    );
  }
}
