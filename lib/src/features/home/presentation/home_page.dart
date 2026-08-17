import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/user_avatar.dart';
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

class HomePage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final device = deviceId == null
        ? state.selectedDevice
        : state.deviceById(deviceId!);
    final model =
        dashboard ??
        HomeDashboardModel.fromDevice(
          device: device,
          userLabel: state.user?.nickname ?? '用户',
          scene: scene,
        );
    final avatarImage = resolveUserAvatar(state.user?.avatarUrl);
    void goBack() => Navigator.of(context).maybePop();
    void openProfile() => Navigator.pushNamed(context, AppRoutes.mine);
    final VoidCallback? onBack = showBackButton ? goBack : null;
    final VoidCallback onAvatarTap = onOpenProfile ?? openProfile;

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
                          maxWidth: 375,
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            AppSpacing.huge,
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
