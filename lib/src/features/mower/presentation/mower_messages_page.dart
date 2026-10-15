import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../messages/device_messages_view.dart';

/// 按当前设备查询涂鸦历史消息，三栏与花盆共用原有等级和日期规则。
class MowerMessagesPage extends StatelessWidget {
  const MowerMessagesPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '消息通知', leading: AppBackButton()),
      body: DeviceMessagesView(
        deviceId: deviceId,
        pageName: '割草机-消息通知',
        keyPrefix: 'mower-messages',
      ),
    );
  }
}
