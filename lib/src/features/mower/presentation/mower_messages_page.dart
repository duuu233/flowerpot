import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../mower_device.dart';
import 'mower_machine_logs_view.dart';
import 'widgets/mower_bottom_nav.dart';

class MowerMessagesPage extends StatelessWidget {
  const MowerMessagesPage({required this.onTabRequested, super.key});

  final ValueChanged<MowerTab> onTabRequested;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '消息通知', leading: AppBackButton()),
      body: MowerMachineLogsView(deviceId: MowerDevice.instance.deviceId),
      bottomNavigationBar: MowerBottomNav(
        current: MowerTab.settings,
        onTap: (tab) {
          Navigator.of(context).pop();
          if (tab != MowerTab.settings) onTabRequested(tab);
        },
      ),
    );
  }
}
