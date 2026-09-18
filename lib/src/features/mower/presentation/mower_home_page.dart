import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'mower_control_page.dart';
import 'mower_plan_page.dart';
import 'mower_settings_page.dart';
import 'widgets/mower_bottom_nav.dart';

/// 割草机的外壳：底部导航 + 三个一级页（首页 / 割草计划 / 设置）。
///
/// 三页在稿子里各有自己的标题栏和返回箭头，底部导航是同一条，所以外壳只管
/// 那条导航和当前选中项，标题栏由各页自己出。二级页（设备参数、区域设置……）
/// 压在外壳上面，退回来仍停在原来那一栏。
class MowerHomePage extends StatefulWidget {
  const MowerHomePage({super.key, this.initialTab = MowerTab.home});

  final MowerTab initialTab;

  @override
  State<MowerHomePage> createState() => _MowerHomePageState();
}

class _MowerHomePageState extends State<MowerHomePage> {
  late MowerTab _tab = widget.initialTab;

  void _select(MowerTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 导航条本身是半透明白，底下得有页面底色衬着，否则透出来的是黑。
      backgroundColor: AppColors.canvas,
      body: IndexedStack(
        key: const Key('mower-home-stack'),
        index: MowerTab.values.indexOf(_tab),
        children: <Widget>[
          const MowerControlPage(),
          const MowerPlanPage(),
          MowerSettingsPage(onTabRequested: _select),
        ],
      ),
      bottomNavigationBar: MowerBottomNav(current: _tab, onTap: _select),
    );
  }
}
