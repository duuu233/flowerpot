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
  /// DP 162 报 1（异常）说明设备判定盆里的植物和 App 添加的不是同一种，此时设备
  /// **还没有**上报新的植物标识，先问用户怎么处置；正常、已处置，或者用户已经在
  /// 设置里关掉自动检测植物时直接跳过。
  ///
  /// 处置完再按 DP 116 的值去后端补齐植物的图片与引导文案。光照、需水那些业务
  /// 数据一直跟着设备上报走，不受这一步影响。
  Future<void> _runEntryChecks() async {
    if (!mounted) return;
    final state = FlowerpotScope.of(context);
    final deviceId = widget.deviceId ?? state.selectedDevice?.id;
    if (deviceId == null || !state.hasPlant(deviceId)) return;
    if (state.plantConfirmState(deviceId) == PlantConfirmState.mismatch &&
        state.plantDetectionEnabled(deviceId)) {
      await _resolvePlantMismatch(state, deviceId);
      if (!mounted) return;
    }
    await state.ensurePlantProfile(deviceId);
  }

  /// 植物不一致的两级弹窗。
  ///
  /// 第一级给「确认」和「忽略」，两条都要再过一次二次确认才真正下发：162 一写
  /// 下去，设备就会照着换植物或者压掉这次检测，不该由一次误触决定。二次确认里
  /// 取消就什么都不发，下次进详情页再问一次。
  ///
  /// 第一级的返回值只有「确认」是 true，忽略和系统返回键都是 null，两者都走忽略
  /// 分支——真正的闸门是第二级，返回键最多让用户多看一个可取消的确认框。
  Future<void> _resolvePlantMismatch(
    FlowerpotState state,
    String deviceId,
  ) async {
    final picked = await showAppDialog(
      context,
      title: '植物确认',
      message: '检测到花盆植物与app添加植物不一致，是否以花盆里的植物为准？',
      confirmLabel: '确认',
      cancelLabel: '忽略',
      barrierDismissible: false,
    );
    if (!mounted) return;
    final answer = picked == true
        ? PlantConfirmState.confirmed
        : PlantConfirmState.ignored;
    final settled = await showAppDialog(
      context,
      title: answer == PlantConfirmState.confirmed ? '确认同步花盆植物' : '确认忽略本次检测',
      message: answer == PlantConfirmState.confirmed
          ? '确认后将以花盆里检测到的植物为准，重新读取植物信息。'
          : '确认忽略此次检测，如有需要可以前往设置关闭植物自动检测',
      confirmLabel: '确认',
      barrierDismissible: false,
    );
    if (!mounted || settled != true) return;
    final result = await state.answerPlantConfirm(deviceId, answer);
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final device = widget.deviceId == null
        ? state.selectedDevice
        : state.deviceById(widget.deviceId!);
    final model =
        widget.dashboard ??
        HomeDashboardModel.fromDevice(
          device: device,
          userLabel: state.user?.nickname ?? '用户',
          scene: widget.scene,
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
                              HomeCareBanner(message: model.careMessage),
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
