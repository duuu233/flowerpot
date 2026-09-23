import 'package:flutter/material.dart';

import '../../mower_ui.dart';

/// 割草机三个一级页。稿子里底部导航就这三颗（`割草机底部导航`）。
enum MowerTab {
  home('首页', MowerAssets.navHomeIcon),
  plan('割草计划', MowerAssets.navPlanIcon),
  settings('设置', MowerAssets.navSettingsIcon);

  const MowerTab(this.label, this.icon);

  final String label;
  final String icon;
}

/// 底部导航。
///
/// ⚠️ 图标是稿子导出的 PNG，不是 Material 字体图标：这三颗（房子 / 带勾的日历 /
/// 齿轮）在 Material 里都找不到同款，混着用两页之间会明显不是一套。
///
/// ⚠️ **三张图导出时的颜色不一样**——「首页」那张取自选中态（青），另外两张取自
/// 未选中态（灰）。所以这里**两种态都显式上色**（`BlendMode.srcIn`，图是单色字形），
/// 不能只给未选中态上色，否则「割草计划」「设置」选中时还是灰的。
class MowerBottomNav extends StatelessWidget {
  const MowerBottomNav({required this.current, required this.onTap, super.key});

  final MowerTab current;
  final ValueChanged<MowerTab> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MowerColors.navFill,
        border: Border(top: BorderSide(color: Color(0x2670AFB5))),
      ),
      child: SafeArea(
        top: false,
        // 稿子（Figma 784:3901）：整条 98 高，内边距 10 / 8，每项 72 高、内容居中。
        // 原来每项靠上下 8 的内边距撑开，整条只有约 83（2026-09-23 按 Figma 核对）。
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: SizedBox(
            height: 80,
            child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final tab in MowerTab.values)
                Expanded(
                  child: _MowerNavItem(
                    tab: tab,
                    active: tab == current,
                    onTap: () => onTap(tab),
                  ),
                ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _MowerNavItem extends StatelessWidget {
  const _MowerNavItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final MowerTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('mower-nav-${tab.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset(
              tab.icon,
              width: 28,
              height: 28,
              filterQuality: FilterQuality.high,
              color: active ? MowerColors.brand : MowerColors.inkSecondary,
              colorBlendMode: BlendMode.srcIn,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                color: active ? MowerColors.brand : MowerColors.inkSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
