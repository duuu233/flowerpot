import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../devices/presentation/device_list_page.dart';
import '../../home/presentation/home_page.dart';

/// Root screen after login.
///
/// There is no bottom tab bar: the device list is the home screen, and it
/// falls back to the "no device yet" screen until a planter is bound. Both
/// pages put the profile entry behind the avatar in their header, which pushes
/// the profile page as an ordinary route, so device pages stack on top of this
/// screen instead of replacing a tab.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    return state.devices.isEmpty ? const HomePage() : const DeviceListPage();
  }
}
