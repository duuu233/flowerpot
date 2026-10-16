import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../mower_device.dart';
import '../../devices/presentation/device_online_guard.dart';
import 'mower_control_page.dart';
import 'mower_plan_page.dart';
import 'mower_settings_page.dart';
import 'widgets/mower_bottom_nav.dart';

/// [MowerHomePage] 的路由参数：打开哪一台割草机（2026-09-21）。
///
/// 2026-09-23 起**必须带**：静态演示入口已删，割草机页面只服务设备列表里的真机。
class MowerHomeArguments {
  const MowerHomeArguments({required this.deviceId});

  /// 涂鸦设备 ID。
  final String deviceId;
}

/// 割草机的外壳：底部导航 + 三个一级页（首页 / 割草计划 / 设置）。
///
/// 三页在稿子里各有自己的标题栏和返回箭头，底部导航是同一条，所以外壳只管
/// 那条导航和当前选中项，标题栏由各页自己出。二级页（设备参数、区域设置……）
/// 压在外壳上面，退回来仍停在原来那一栏。
///
/// 外壳还负责把 `MowerDevice` 绑到这台设备上（进来 bind、退出 release），并把下发失败
/// 统一弹出来——二级页压在外壳上面时外壳仍然活着，所以一处就够。
class MowerHomePage extends StatefulWidget {
  const MowerHomePage({
    required this.deviceId,
    super.key,
    this.initialTab = MowerTab.home,
    this.now = DateTime.now,
  });

  final MowerTab initialTab;

  final DateTime Function() now;

  /// 涂鸦设备 ID。
  final String deviceId;

  /// 外部要求切到某一栏（固件升级提醒点「立刻更新」要切到「设置」，2026-09-23）。
  /// 设一个值，外壳切过去后清回 null。
  static final ValueNotifier<MowerTab?> tabRequests = ValueNotifier<MowerTab?>(
    null,
  );

  @override
  State<MowerHomePage> createState() => _MowerHomePageState();
}

class _MowerHomePageState extends State<MowerHomePage> {
  late MowerTab _tab = widget.initialTab;
  StreamSubscription<String>? _failures;

  @override
  void initState() {
    super.initState();
    MowerHomePage.tabRequests.addListener(_onTabRequest);
    _failures = MowerDevice.instance.failures.listen((message) {
      if (!mounted) return;
      if (message == deviceOfflineMessage) {
        showMowerOfflineNotice(context);
      } else {
        showAppMessage(context, message, tone: AppMessageTone.error);
      }
    });
    // 放到首帧之后：bind 会 notifyListeners，在构建期间通知会让正在建的页面报错。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        MowerDevice.instance.bind(
          FlowerpotScope.of(context),
          owner: this,
          deviceId: widget.deviceId,
        ),
      );
    });
  }

  void _onTabRequest() {
    final tab = MowerHomePage.tabRequests.value;
    if (tab == null || !mounted) return;
    MowerHomePage.tabRequests.value = null;
    _select(tab);
  }

  @override
  void dispose() {
    MowerHomePage.tabRequests.removeListener(_onTabRequest);
    unawaited(_failures?.cancel());
    MowerDevice.instance.release(this);
    super.dispose();
  }

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
          // 只在停在「首页」这一栏时弹 DP18 设备告警（见 MowerControlPage）
          MowerControlPage(active: _tab == MowerTab.home, now: widget.now),
          const MowerPlanPage(),
          MowerSettingsPage(deviceId: widget.deviceId),
        ],
      ),
      bottomNavigationBar: MowerBottomNav(current: _tab, onTap: _select),
    );
  }
}
