import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../core/config/debug_tools_config.dart';
import '../../../design_system/design_system.dart';
import '../../devices/presentation/device_list_page.dart';
import '../../home/presentation/home_page.dart';
import '../../profile/presentation/mine_page.dart';

/// Root shell with the bottom tab bar.
///
/// The first tab is the home tab: it shows the "no device yet" screen until a
/// planter is bound, and the device list once there is one. The device list is
/// the home screen from that point on, so device pages are pushed on top of
/// this shell rather than replacing it.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

  void _openProfileTab() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    // Mock mode is called out at the shell level because every number the tabs
    // below render is simulated, which is invisible once a page shows it as a
    // sensor reading.
    final mockBackend = DebugToolsConfig.enabled && state.usingMockBackend;
    final tabs = IndexedStack(
      index: _index,
      children: <Widget>[
        state.devices.isEmpty
            ? HomePage(onOpenProfile: _openProfileTab)
            : DeviceListPage(onOpenProfile: _openProfileTab),
        const MinePage(showBackButton: false),
      ],
    );
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: <Widget>[
          if (mockBackend)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: MockDataBanner(
                  key: const Key('shell-mock-backend-ribbon'),
                  title: state.demoMode
                      ? '体验模式 · Mock 后端'
                      : 'Mock 后端（未启用 TUYA_ENABLED）',
                  message: '设备、传感器、报表和固件信息都由本地模拟数据生成，不代表真实设备。',
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          // The ribbon already consumed the status-bar inset; without this the
          // tab pages would add it a second time under their own SafeArea.
          Expanded(
            child: mockBackend
                ? MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: tabs,
                  )
                : tabs,
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavigation(
        key: const Key('app-shell-bottom-navigation'),
        currentIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
