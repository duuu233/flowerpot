import 'package:flutter/material.dart';

import '../../home/presentation/home_page.dart';
import '../../profile/presentation/mine_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: IndexedStack(
      index: index,
      children: const <Widget>[HomePage(), MinePage()],
    ),
    bottomNavigationBar: Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: NavigationBar(
        height: 68,
        selectedIndex: index,
        backgroundColor: Colors.white.withValues(alpha: .94),
        indicatorColor: Theme.of(
          context,
        ).colorScheme.secondary.withValues(alpha: .28),
        elevation: 8,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.local_florist_outlined),
            selectedIcon: Icon(Icons.local_florist_rounded),
            label: '花园',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
        onDestinationSelected: (value) => setState(() => index = value),
      ),
    ),
  );
}
