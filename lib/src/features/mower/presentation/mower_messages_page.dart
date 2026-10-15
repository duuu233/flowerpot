import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'mower_machine_logs_view.dart';

class MowerMessagesPage extends StatelessWidget {
  const MowerMessagesPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '消息通知', leading: AppBackButton()),
      body: MowerMachineLogsView(deviceId: deviceId),
    );
  }
}
