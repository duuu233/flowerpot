import 'package:flutter/material.dart';

import '../../devices/presentation/device_online_guard.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../mower_ui.dart';
import '../mower_device.dart';
import '../mower_dp.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_form.dart';

/// 时间同步（`割草机-时间同步.png` + `割草机-时间同步-时区展开.png`）。
///
/// | 控件 | DP |
/// | --- | --- |
/// | 开启 | DP106 time_sync_enable |
/// | 自动设置 | **没有对应 DP**，端上本地开关（见下） |
/// | 时区 | DP107 timezone（25 枚举，序号 20 = UTC+8） |
/// | 启用夏令制 | DP108 dst_enable |
/// | 保存 | 按 V2.2 §9.6 的顺序发 106 → 107 → 108 → **114（UTC 秒字符串）** |
///
/// ⚠️ **「自动设置」没有 DPID**：协议里只有 106/107/108/114 四条，没有"自动选时区"。
/// 所以它是端上的开关——**开着就跟手机时区走**（用户不用选），关掉才让用户从下面那张
/// 本地时区表里挑（2026-09-18 用户口径：没开自动设置时用前端缓存的时区数据）。
/// 不论开关如何，最终下发的都是 DP107 那个枚举值。
///
/// ⚠️ **DP106 关着时设备会拒收 DP114**，所以关的时候不发时间戳，只发开关（日志里记一行）。
class MowerTimeSyncPage extends StatefulWidget {
  const MowerTimeSyncPage({super.key});

  @override
  State<MowerTimeSyncPage> createState() => _MowerTimeSyncPageState();
}

class _MowerTimeSyncPageState extends State<MowerTimeSyncPage> {
  MowerDevice get _device => MowerDevice.instance;

  final LayerLink _link = LayerLink();
  final OverlayPortalController _menu = OverlayPortalController();

  late bool _enabled = _device.timeSyncEnable;
  late bool _dst = _device.dstEnable;
  late int _timezoneIndex = _device.timezoneIndex;

  /// 「自动设置」：端上开关，开着就跟手机时区走。
  bool _autoZone = true;

  @override
  void initState() {
    super.initState();
    if (_autoZone) _timezoneIndex = _phoneTimezoneIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FlowerpotScope.of(context)
        ..logPageEntry('割草机-时间同步')
        ..logMowerInteraction(
          '读取 ← 割草机-时间同步 '
          'DP${MowerDp.timeSyncEnable}=$_enabled，'
          'DP${MowerDp.timezone}=${MowerTimezone.codeOf(_timezoneIndex)}，'
          'DP${MowerDp.dstEnable}=$_dst，'
          'DP${MowerDp.deviceTime}=${_device.deviceTimeUtcSeconds ?? '未对过时'}'
          '（自动设置=$_autoZone，无对应 DPID）',
        );
    });
  }

  int get _phoneTimezoneIndex =>
      MowerTimezone.fromDeviceOffset(DateTime.now().timeZoneOffset);

  void _save() {
    final state = FlowerpotScope.of(context);
    _device.setTimeSync(
      state,
      enable: _enabled,
      timezoneIndex: _timezoneIndex,
      dst: _dst,
    );
    showAppMessage(
      context,
      _enabled
          ? '已下发 DP${MowerDp.timeSyncEnable} / DP${MowerDp.timezone} / DP${MowerDp.dstEnable} / DP${MowerDp.deviceTime}'
          : '已下发 DP${MowerDp.timeSyncEnable} / DP${MowerDp.timezone} / DP${MowerDp.dstEnable}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '时间同步', leading: AppBackButton()),
      body: DeviceOnlineBody(
        deviceId: MowerDevice.instance.deviceId,
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                key: const Key('mower-time-sync-scroll-view'),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: MowerCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      MowerSwitchRow(
                        title: '开启',
                        subtitle: '同步设备时间与当前手机时间（DP${MowerDp.timeSyncEnable}）',
                        value: _enabled,
                        switchKey: const Key('mower-time-sync-switch'),
                        onChanged: (value) => setState(() => _enabled = value),
                      ),
                      const MowerRowDivider(indent: 20),
                      MowerSwitchRow(
                        title: '自动设置',
                        subtitle: '根据手机所在地区自动选择时区（端上本地，无对应 DPID）',
                        value: _autoZone,
                        switchKey: const Key('mower-time-sync-auto'),
                        onChanged: (value) => setState(() {
                          _autoZone = value;
                          if (value) _timezoneIndex = _phoneTimezoneIndex;
                          if (value) _menu.hide();
                        }),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              '时区（DP${MowerDp.timezone} ${MowerTimezone.codeOf(_timezoneIndex)}）',
                              style: const TextStyle(
                                color: MowerColors.inkTertiary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _TimeZoneField(
                              link: _link,
                              menu: _menu,
                              index: _timezoneIndex,
                              // 自动设置开着时不让选：那时时区跟手机走。
                              enabled: !_autoZone,
                              onSelected: (index) => setState(() {
                                _timezoneIndex = index;
                                _menu.hide();
                              }),
                            ),
                          ],
                        ),
                      ),
                      const MowerRowDivider(indent: 20),
                      MowerSwitchRow(
                        title: '启用夏令制',
                        subtitle: '仅在当前时区支持时生效（DP${MowerDp.dstEnable}）',
                        value: _dst,
                        switchKey: const Key('mower-time-sync-dst'),
                        onChanged: (value) => setState(() => _dst = value),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            MowerSaveBar(
              child: MowerSaveButton(
                buttonKey: const Key('mower-time-sync-save'),
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeZoneField extends StatelessWidget {
  const _TimeZoneField({
    required this.link,
    required this.menu,
    required this.index,
    required this.enabled,
    required this.onSelected,
  });

  final LayerLink link;
  final OverlayPortalController menu;
  final int index;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // 菜单要和输入框一样宽，宽度从这层 LayoutBuilder 拿，闭包直接带进 overlayChildBuilder。
    return LayoutBuilder(
      builder: (context, constraints) {
        return CompositedTransformTarget(
          link: link,
          child: OverlayPortal(
            controller: menu,
            overlayChildBuilder: (context) => Stack(
              children: <Widget>[
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
                  offset: const Offset(0, 4),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: _TimeZoneMenu(
                        selected: index,
                        onSelected: onSelected,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            child: Opacity(
              opacity: enabled ? 1 : .5,
              child: GestureDetector(
                key: const Key('mower-time-zone-field'),
                onTap: enabled ? menu.toggle : null,
                // 稿子 735:2559 时区框 48 高、圆角 10。
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .6),
                    border: Border.all(
                      color: MowerColors.brand.withValues(alpha: .35),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          MowerTimezone.labelOf(index),
                          key: const Key('mower-time-zone-value'),
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
          ),
        );
      },
    );
  }
}

/// 时区列表：**端上本地的 25 条**（DP107 的枚举全集），不依赖设备下发。
class _TimeZoneMenu extends StatelessWidget {
  const _TimeZoneMenu({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('mower-time-zone-menu'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        // 稿子 738:2620 下拉菜单最高 276（6 行 × 46）。
        constraints: const BoxConstraints(maxHeight: 276),
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
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: MowerTimezone.count,
          itemBuilder: (context, index) => _TimeZoneMenuRow(
            index: index,
            selected: index == selected,
            onTap: () => onSelected(index),
          ),
        ),
      ),
    );
  }
}

class _TimeZoneMenuRow extends StatelessWidget {
  const _TimeZoneMenuRow({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('mower-time-zone-$index'),
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? MowerColors.chipFill : Colors.transparent,
          border: index == 0
              ? null
              : const Border(top: BorderSide(color: MowerColors.divider)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                MowerTimezone.labelOf(index),
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
