import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/user_avatar.dart';
import '../../../state.dart';
import '../../../tuya/tuya_models.dart';
import '../../devices/models/water_status_page_model.dart';
import '../../devices/presentation/plant_picker_page.dart';
import '../models/home_dashboard_model.dart';
import 'widgets/home_care_banner.dart';
import 'widgets/home_empty_device_content.dart';
import 'widgets/home_header.dart';
import 'widgets/home_help_card.dart';
import 'widgets/home_plant_overview.dart';
import 'widgets/home_quick_actions.dart';
import 'widgets/home_unplanted_content.dart';

/// Route arguments for a device page pushed from the device list.
class HomeDeviceArguments {
  const HomeDeviceArguments({required this.deviceId, required this.scene});

  final String deviceId;
  final HomeDashboardScene scene;
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.dashboard,
    this.scene = HomeDashboardScene.withCompanionSummary,
    this.deviceId,
    this.showBackButton = false,
    this.onOpenProfile,
  });

  final HomeDashboardModel? dashboard;
  final HomeDashboardScene scene;

  /// Device to render. Falls back to the currently selected device.
  final String? deviceId;

  /// Pushed device pages show a back button where a root tab shows the
  /// profile entry.
  final bool showBackButton;

  /// Overrides how the profile centre opens, so the shell can switch tabs
  /// instead of stacking another route.
  final VoidCallback? onOpenProfile;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 进页面的检查只跑一次，依赖变化重建时不会再弹一遍。
  bool _entryChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entryChecked) return;
    _entryChecked = true;
    // 首帧之后再跑：这一步要 showDialog，build 过程中推路由是非法的。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_runEntryChecks()),
    );
  }

  /// 进入设备详情页的检查。
  ///
  /// DP 162 报 1 就弹「发现新植物」引导窗——弹不弹完全由设备说了算：App 下发植物
  /// DPID 之后固件会把 162 改回 0 并立即上报；盆里没植物（116 = -1）或用户关掉
  /// 自动检测时固件同样报 0，所以 App 这边不再自己叠加判断条件。
  ///
  /// 之后按 DP 116 的 id 去后端补齐植物的图片与引导文案。光照、需水那些业务数据
  /// 一直跟着设备上报走，不受这一步影响。
  Future<void> _runEntryChecks() async {
    if (!mounted) return;
    final state = FlowerpotScope.of(context);
    final deviceId = widget.deviceId ?? state.selectedDevice?.id;
    if (deviceId == null) return;
    // 先补一次植物资料：引导窗要显示「已检测到 xxx 植物」，名字来自后端目录。
    await state.ensurePlantProfile(deviceId);
    if (!mounted) return;
    await _maybeShowPlantGuide(state, deviceId);
  }

  /// 引导窗正在显示。防止 DP 连续上报时叠出好几个。
  bool _guideShowing = false;

  /// **设备在页面打开期间把 162 改成「要弹」时，也要弹。**
  ///
  /// ⚠️ 2026-09-11 产品反馈「按固件按钮能切换有无植物的场景，但是没有弹窗」——根因就在
  /// 这里：原来只有 `didChangeDependencies` 里那一次 `_entryChecked` 检查，**进页面时查一次
  /// 就再也不查了**。而用户是在页面上按按钮的，DP 162 通过实时上报变成 true，界面上的
  /// 植物场景跟着变了，引导窗却没人再去触发。
  ///
  /// 现在每次 build 之后都看一眼：由「不弹」变成「要弹」就补上。已经在显示时不重复弹。
  Future<void> _maybeShowPlantGuide(FlowerpotState state, String deviceId) async {
    if (_guideShowing || !mounted) return;
    if (!state.plantGuidePending(deviceId)) return;
    _guideShowing = true;
    try {
      // 名字来自后端目录：设备刚报上来的植物可能还没补过资料。
      await state.ensurePlantProfile(deviceId);
      if (!mounted) return;
      // 等资料回来的这段时间里设备可能又改回「不弹」了，再确认一次。
      if (!state.plantGuidePending(deviceId)) return;
      await _showPlantGuide(state, deviceId);
    } finally {
      _guideShowing = false;
    }
  }

  /// 「发现新植物」引导窗。
  ///
  /// 两个按钮都会让固件把 162 改回 0：「确认」直接把设备当前上报的植物 DPID 原样
  /// 回写，「选择植物」跳到选择流程、选完由那条流程下发。用返回键关掉则什么都不
  /// 发，下次进详情页设备还会要求弹。
  ///
  /// **植物 id 为 0（通用植物）是单独一支**：固件只识别出「有植物」但认不出品种，
  /// 后台也不再为 0 建植物数据，所以没有可确认的对象——文案改成「请选择并确认
  /// 植物」，按钮只留「选择植物」。
  Future<void> _showPlantGuide(FlowerpotState state, String deviceId) async {
    final generic = state.reportedPlantId(deviceId) == PlantVariety.generic;
    final name = state.reportedPlantName(deviceId);
    final picked = await showAppDialog(
      context,
      title: '发现新植物',
      message: generic
          ? '已检测到通用植物，请选择并确认植物。'
          : '已检测到${name ?? '新'}植物，请确认植物。',
      confirmLabel: generic ? '选择植物' : '确认',
      cancelLabel: '选择植物',
      showCancel: !generic,
      barrierDismissible: false,
      content: const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '1、选择植物请确保与花盆植物一致',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
            SizedBox(height: 4),
            Text(
              '2、忽略检测结果，可前往设置关闭植物自动检测',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    // 通用植物那一支只有一个按钮，点它就是去选植物。
    if (picked && !generic) {
      final result = await state.confirmDetectedPlant(deviceId);
      if (!mounted) return;
      showAppMessage(
        context,
        result.message,
        tone: result.success ? AppMessageTone.success : AppMessageTone.error,
      );
      return;
    }
    _openAddPlant(context, deviceId);
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final device = widget.deviceId == null
        ? state.selectedDevice
        : state.deviceById(widget.deviceId!);
    // **设备在页面打开期间把 162 改成「要弹」时补上引导窗**（见 [_maybeShowPlantGuide]）。
    // 放在 build 之后跑：showDialog 不能在 build 过程中调。
    final watchedId = widget.deviceId ?? device?.id;
    if (watchedId != null && state.plantGuidePending(watchedId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_maybeShowPlantGuide(state, watchedId));
      });
    }
    final model =
        widget.dashboard ??
        HomeDashboardModel.fromDevice(
          device: device,
          userLabel: state.user?.nickname ?? '用户',
          scene: widget.scene,
          language: state.languageCode,
        );
    final avatarImage = resolveUserAvatar(state.user?.avatarUrl);
    void goBack() => Navigator.of(context).maybePop();
    void openProfile() => Navigator.pushNamed(context, AppRoutes.mine);
    final VoidCallback? onBack = widget.showBackButton ? goBack : null;
    final VoidCallback onAvatarTap = widget.onOpenProfile ?? openProfile;

    return AppPageScaffold(
      background: model.isWithoutDevice
          ? AppPageBackground.white
          : AppPageBackground.home,
      body: model.isWithoutDevice
          ? HomeEmptyDeviceContent(
              userLabel: model.userLabel,
              avatarImage: avatarImage,
              onRefresh: state.refreshDevices,
              onAvatarTap: onAvatarTap,
              onBack: onBack,
              onAddDevice: () =>
                  Navigator.pushNamed(context, AppRoutes.deviceSearch),
            )
          : model.isWithoutPlant
          ? HomeUnplantedContent(
              model: model,
              avatarImage: avatarImage,
              onRefresh: state.refreshDevices,
              onAvatarTap: onAvatarTap,
              onBack: onBack,
              onAddPlant: () => _openAddPlant(context, model.deviceId),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth < 360
                    ? 12.0
                    : 20.0;
                return RefreshIndicator(
                  color: AppColors.brandPrimary,
                  onRefresh: state.refreshDevices,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: <Widget>[
                      SliverToBoxAdapter(
                        child: ResponsiveContent(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            AppSpacing.xl,
                            horizontalPadding,
                            24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              HomeHeader(
                                userLabel: model.userLabel,
                                title: model.deviceName,
                                avatarImage: avatarImage,
                                onAvatarTap: onAvatarTap,
                                onBack: onBack,
                              ),
                              const SizedBox(height: 24),
                              HomePlantOverview(
                                model: model,
                                onMetricTap: (kind) => _openDevice(
                                  context,
                                  model.deviceId,
                                  switch (kind) {
                                    HomeMetricKind.water =>
                                      AppRoutes.waterStatus,
                                    HomeMetricKind.light =>
                                      AppRoutes.lightStatus,
                                    HomeMetricKind.temperature =>
                                      AppRoutes.temperatureStatus,
                                    HomeMetricKind.humidity =>
                                      AppRoutes.humidityStatus,
                                  },
                                ),
                              ),
                              SizedBox(
                                height: model.showCompanionSummary ? 18 : 9,
                              ),
                              HomeCareBanner(
                                title: model.careTitle,
                                messages: model.careMessages,
                                // 盆里没植物时整行换成提示：养护建议是按植物给
                                // 的，没有植物就没有可给的建议。
                                notice: model.plantMissing
                                    ? HomeCareBanner.plantMissingNotice
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              HomeQuickActions(
                                actions: model.actions,
                                onActionTap: (kind) =>
                                    _openAction(context, model.deviceId, kind),
                              ),
                              const SizedBox(height: 12),
                              HomeHelpCard(
                                topics: model.helpTopics,
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.help,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _openAddPlant(BuildContext context, String? deviceId) {
    if (deviceId == null) {
      showAppMessage(context, '请先添加并连接花盆', tone: AppMessageTone.info);
      return;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.plantPicker,
      arguments: PlantPickerArguments(
        deviceId: deviceId,
        mode: PlantPickerMode.add,
      ),
    );
  }

  void _openAction(
    BuildContext context,
    String? deviceId,
    HomeActionKind kind,
  ) {
    final route = switch (kind) {
      HomeActionKind.animation => AppRoutes.animations,
      HomeActionKind.battery => AppRoutes.batteryStatus,
      HomeActionKind.settings => AppRoutes.deviceSettings,
    };
    _openDevice(context, deviceId, route);
  }

  void _openDevice(BuildContext context, String? deviceId, String route) {
    if (deviceId == null) {
      showAppMessage(context, '请先添加并连接花盆', tone: AppMessageTone.info);
      return;
    }
    final arguments = route == AppRoutes.waterStatus
        ? WaterStatusArguments(
            deviceId: deviceId,
            initialMetric: WaterStatusMetric.soilMoisture,
          )
        : deviceId;
    Navigator.pushNamed(context, route, arguments: arguments);
  }
}
