import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
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

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    this.dashboard,
    this.scene = HomeDashboardScene.withCompanionSummary,
  });

  final HomeDashboardModel? dashboard;
  final HomeDashboardScene scene;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final model =
        dashboard ??
        HomeDashboardModel.fromDevice(
          device: state.selectedDevice,
          userLabel: state.user?.nickname ?? '用户',
          scene: scene,
        );
    final avatarImage = _avatarImage(state.user?.avatarUrl);

    return AppPageScaffold(
      background: model.isWithoutDevice
          ? AppPageBackground.white
          : AppPageBackground.home,
      body: model.isWithoutDevice
          ? HomeEmptyDeviceContent(
              userLabel: model.userLabel,
              avatarImage: avatarImage,
              onRefresh: state.refreshDevices,
              onAvatarTap: () => Navigator.pushNamed(context, AppRoutes.mine),
              onAddDevice: () =>
                  Navigator.pushNamed(context, AppRoutes.pairing),
            )
          : model.isWithoutPlant
          ? HomeUnplantedContent(
              model: model,
              avatarImage: avatarImage,
              onRefresh: state.refreshDevices,
              onAvatarTap: () => Navigator.pushNamed(context, AppRoutes.mine),
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
                                onAvatarTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.mine,
                                ),
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

  ImageProvider<Object>? _avatarImage(String? path) {
    final value = path?.trim();
    if (value == null || value.isEmpty) return null;
    final file = File(value);
    if (file.existsSync()) return FileImage(file);
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(value);
    }
    return null;
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
