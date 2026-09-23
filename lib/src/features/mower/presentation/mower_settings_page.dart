import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/widgets/blocking_progress.dart';
import '../../../tuya/tuya_models.dart';
import '../../devices/presentation/device_online_guard.dart';
import '../mower_ui.dart';
import '../mower_device.dart';
import '../mower_dp.dart';
import 'mower_firmware.dart';
import 'mower_messages_page.dart';
import 'widgets/mower_bottom_nav.dart';
import 'widgets/mower_card.dart';

/// 割草机设置页（`割草机-设置.png`）。
///
/// 八项设置一张卡、消息通知单独一张、最后是删除设备。
///
/// | 入口 | 这一轮的去处 |
/// | --- | --- |
/// | 设备参数 / 区域设置 / 雨淋设置 / 时间同步 / 语言切换 | 各自的页面（已接 DP） |
/// | 帮助中心 | 帮助中心页，**按割草机的产品 ID 拉常见问题**（[MowerDp.productId]） |
/// | 设备升级 | 涂鸦 OTA，和花盆同一套（`upgradeMowerFirmware`，2026-09-23） |
/// | 删除设备 | 和花盆「移除设备」同一套：涂鸦解绑 + 删后台记录（2026-09-23） |
/// | 重新配网 | **暂时隐藏**（2026-09-23 产品） |
class MowerSettingsPage extends StatelessWidget {
  const MowerSettingsPage({required this.onTabRequested, super.key});

  /// 消息通知页底部那条导航点了「首页 / 割草计划」时，退回来并切到那一栏。
  final ValueChanged<MowerTab> onTabRequested;

  static const List<String> _entries = <String>[
    '设备参数',
    '区域设置',
    '雨淋设置',
    // '重新配网' 暂时隐藏（2026-09-23 产品）。
    '时间同步',
    '设备升级',
    '语言切换',
    '帮助中心',
  ];

  Future<void> _open(BuildContext context, String entry) async {
    if (entry == '设备升级') {
      final id = MowerDevice.instance.deviceId;
      if (id != null) await upgradeMowerFirmware(context, id);
      return;
    }
    if (entry == '帮助中心') {
      // 帮助中心按**产品**筛常见问题：割草机要带自己的产品 ID，不能跟着花盆那条走
      // （后台 getBasicData 的 deviceIdList 里两款都有，见 FlowerpotState._faqProductId）。
      await Navigator.of(
        context,
      ).pushNamed(AppRoutes.help, arguments: MowerDp.productId);
      return;
    }
    final route = switch (entry) {
      '设备参数' => AppRoutes.mowerParameters,
      '区域设置' => AppRoutes.mowerZones,
      '雨淋设置' => AppRoutes.mowerRain,
      '时间同步' => AppRoutes.mowerTimeSync,
      '语言切换' => AppRoutes.mowerLanguage,
      _ => null,
    };
    if (route == null) {
      MowerDevice.instance.logUnsupported(FlowerpotScope.of(context), entry);
      showAppMessage(context, '当前还没有支持的 DPID', tone: AppMessageTone.info);
      return;
    }
    await Navigator.of(context).pushNamed(route);
  }

  static bool _firmwareBadge(BuildContext context) {
    final id = MowerDevice.instance.deviceId;
    if (id == null) return false;
    final state = FlowerpotScope.of(context);
    return state.hasFirmwareUpdate(id) &&
        state.otaProgressFor(id)?.status != OtaStatus.running;
  }

  /// 删除设备：和花盆「移除设备」同一套（2026-09-23 产品：「跟花盆一样的啊，只是产品 ID 不一样」）——
  /// 确认 → 涂鸦解绑（`removeDevice`）+ 删后台记录 → 回到首页。
  /// 不走花盆的「恢复出厂」那条：它要先发花盆的 DP 141，割草机没有这个 DP。
  Future<void> _removeDevice(BuildContext context) async {
    final id = MowerDevice.instance.deviceId;
    if (id == null) return;
    final state = FlowerpotScope.of(context);
    final name = state.deviceById(id)?.name ?? '';
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除设备',
      message: '删除后需要重新配网才能使用“$name”，确定继续吗？',
      confirmLabel: '删除设备',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    state.logMowerInteraction('删除 → 割草机 $id（涂鸦解绑 + 删后台记录）');
    // 不可逆，点一次就够。
    final result = await withBlockingProgress(
      context,
      () => state.removeDevice(id, resetFactory: false),
    );
    if (result == null) return;
    state.logMowerInteraction(
      result.success ? '删除 ✓ ${result.message}' : '删除 ✗ ${result.message}',
    );
    if (!context.mounted) return;
    if (!result.success) {
      showDeviceActionResult(context, result);
      return;
    }
    showAppMessage(context, result.message, tone: AppMessageTone.success);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 消息通知要把「退回来切到哪一栏」带进去，所以这一页直接 push，不走
  /// [AppRoutes]：命名路由那边统一生成 `MaterialPageRoute<dynamic>`，塞不进回调。
  Future<void> _openMessages(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MowerMessagesPage(onTabRequested: onTabRequested),
        settings: const RouteSettings(name: '/mower/messages'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: '设置',
        leading: const AppBackButton(),
        actions: <Widget>[
          Center(
            child: GestureDetector(
              key: const Key('mower-settings-help'),
              onTap: () => unawaited(_open(context, '帮助中心')),
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const Text(
                  '?',
                  style: TextStyle(
                    color: MowerColors.brand,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        key: const Key('mower-settings-scroll-view'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MowerCard(
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < _entries.length; i++) ...<Widget>[
                    MowerSettingsRow(
                      label: _entries[i],
                      // 有新固件就在「设备升级」亮红点（与花盆「固件版本更新」同口径：
                      // 升级进行中不亮）。
                      badge: _entries[i] == '设备升级' && _firmwareBadge(context),
                      onTap: () => unawaited(_open(context, _entries[i])),
                    ),
                    if (i != _entries.length - 1) const MowerRowDivider(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            MowerCard(
              child: MowerSettingsRow(
                label: '消息通知',
                height: 48,
                onTap: () => unawaited(_openMessages(context)),
              ),
            ),
            const SizedBox(height: 12),
            _DeleteDeviceButton(
              onTap: () => unawaited(_removeDevice(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置卡里的一行：左边标题、右边箭头。
class MowerSettingsRow extends StatelessWidget {
  const MowerSettingsRow({
    required this.label,
    required this.onTap,
    super.key,
    this.height = 56,
    this.badge = false,
  });

  final String label;
  final VoidCallback onTap;
  final double height;

  /// 行尾箭头前的小红点（和花盆设置行同一个 [AppNoticeDot]）。
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('mower-settings-$label'),
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: MowerColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (badge) ...<Widget>[
                const AppNoticeDot(semanticLabel: '有新固件'),
                const SizedBox(width: 6),
              ],
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: MowerColors.inkSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteDeviceButton extends StatelessWidget {
  const _DeleteDeviceButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        key: const Key('mower-settings-delete'),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: .72),
          foregroundColor: MowerColors.danger,
          side: const BorderSide(color: MowerColors.dangerBorder),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        child: const Text('删除设备'),
      ),
    );
  }
}
