import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    required this.currentIndex,
    required this.destinations,
    required this.onDestinationSelected,
    super.key,
  });

  final int currentIndex;
  final List<NavigationDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      height: 68,
      elevation: 0,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.brandSurface,
      selectedIndex: currentIndex,
      destinations: destinations,
      onDestinationSelected: onDestinationSelected,
    );
  }
}
