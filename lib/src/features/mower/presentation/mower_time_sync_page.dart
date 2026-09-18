import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../mower_demo.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_form.dart';

/// 时间同步（`割草机-时间同步.png` + `割草机-时间同步-时区展开.png`）。
///
/// 时区下拉是**浮在页面上**的，不是把卡片撑开——稿子上展开后的菜单盖住了下面的
/// 「启用夏令制」和保存按钮。所以这里用 [OverlayPortal] + [CompositedTransformFollower]
/// 让菜单跟着输入框走，卡片本身一动不动。
class MowerTimeSyncPage extends StatefulWidget {
  const MowerTimeSyncPage({super.key});

  @override
  State<MowerTimeSyncPage> createState() => _MowerTimeSyncPageState();
}

class _MowerTimeSyncPageState extends State<MowerTimeSyncPage> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _menu = OverlayPortalController();

  bool _enabled = true;
  bool _autoZone = true;
  bool _daylightSaving = false;
  String _timeZone = MowerDemoDevice.timeZone;

  void _pick(String zone) {
    setState(() => _timeZone = zone);
    _menu.hide();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '时间同步', leading: AppBackButton()),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              key: const Key('mower-time-sync-scroll-view'),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: MowerCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    MowerSwitchRow(
                      title: '开启',
                      subtitle: '同步设备时间与当前手机时间',
                      value: _enabled,
                      switchKey: const Key('mower-time-sync-switch'),
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                    const MowerRowDivider(indent: 20),
                    MowerSwitchRow(
                      title: '自动设置',
                      subtitle: '根据所在地区自动选择时区',
                      value: _autoZone,
                      switchKey: const Key('mower-time-sync-auto'),
                      onChanged: (value) => setState(() => _autoZone = value),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Text(
                            '时区',
                            style: TextStyle(
                              color: MowerColors.inkTertiary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _TimeZoneField(
                            link: _link,
                            menu: _menu,
                            value: _timeZone,
                            onSelected: _pick,
                          ),
                        ],
                      ),
                    ),
                    const MowerRowDivider(indent: 20),
                    MowerSwitchRow(
                      title: '启用夏令制',
                      subtitle: '仅在当前时区支持时生效',
                      value: _daylightSaving,
                      switchKey: const Key('mower-time-sync-dst'),
                      onChanged: (value) =>
                          setState(() => _daylightSaving = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: MowerSaveButton(
              buttonKey: const Key('mower-time-sync-save'),
              onPressed: () => showAppMessage(
                context,
                '静态页面：时区不会真的下发',
                tone: AppMessageTone.info,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeZoneField extends StatelessWidget {
  const _TimeZoneField({
    required this.link,
    required this.menu,
    required this.value,
    required this.onSelected,
  });

  final LayerLink link;
  final OverlayPortalController menu;
  final String value;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    // 菜单要和输入框一样宽。宽度从这层 [LayoutBuilder] 拿，闭包直接带进
    // `overlayChildBuilder`——不必为了量一个宽度多走一轮 setState。
    return LayoutBuilder(
      builder: (context, constraints) {
        return CompositedTransformTarget(
          link: link,
          child: OverlayPortal(
            controller: menu,
            overlayChildBuilder: (context) => Stack(
              children: <Widget>[
                // 点菜单以外的地方收起来。
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: menu.hide,
                  ),
                ),
                CompositedTransformFollower(
                  link: link,
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: const Offset(0, 8),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: _TimeZoneMenu(
                        selected: value,
                        onSelected: onSelected,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            child: GestureDetector(
              key: const Key('mower-time-zone-field'),
              onTap: menu.toggle,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .6),
                  border: Border.all(
                    color: MowerColors.brand.withValues(alpha: .35),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: MowerColors.ink,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: MowerColors.inkSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimeZoneMenu extends StatelessWidget {
  const _TimeZoneMenu({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('mower-time-zone-menu'),
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: MowerColors.brand.withValues(alpha: .28)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x241F3338),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < MowerDemoTimeZones.options.length; i++)
              _TimeZoneMenuRow(
                label: MowerDemoTimeZones.options[i],
                selected: MowerDemoTimeZones.options[i] == selected,
                first: i == 0,
                last: i == MowerDemoTimeZones.options.length - 1,
                onTap: () => onSelected(MowerDemoTimeZones.options[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimeZoneMenuRow extends StatelessWidget {
  const _TimeZoneMenuRow({
    required this.label,
    required this.selected,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('mower-time-zone-$label'),
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? MowerColors.chipFill : Colors.transparent,
          border: first
              ? null
              : const Border(top: BorderSide(color: MowerColors.divider)),
          borderRadius: BorderRadius.vertical(
            top: first ? const Radius.circular(11) : Radius.zero,
            bottom: last ? const Radius.circular(11) : Radius.zero,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? MowerColors.brand : MowerColors.ink,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: MowerColors.brand,
              ),
          ],
        ),
      ),
    );
  }
}
