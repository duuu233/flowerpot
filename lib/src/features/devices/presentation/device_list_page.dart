import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../state.dart';
import '../../../tuya/tuya_models.dart';
import '../../home/models/home_dashboard_model.dart';
import '../../home/presentation/home_page.dart';

class DeviceListPage extends StatelessWidget {
  const DeviceListPage({super.key, this.devices, this.onOpenProfile});

  final List<SmartPlanterDevice>? devices;

  /// Lets the shell switch to the profile tab instead of stacking a route.
  final VoidCallback? onOpenProfile;

  /// Opens the device page. A planter without a plant lands on the "no plant
  /// yet" screen first; picking a plant there continues to the detail page.
  void _openDevice(
    BuildContext context,
    FlowerpotState state,
    SmartPlanterDevice device,
  ) {
    state.selectDevice(device.id);
    Navigator.pushNamed(
      context,
      AppRoutes.deviceHome,
      arguments: HomeDeviceArguments(
        deviceId: device.id,
        scene: state.hasPlant(device.id)
            ? HomeDashboardScene.withCompanionSummary
            : HomeDashboardScene.withoutPlant,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final items = devices ?? state.devices;
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: '设备列表',
        // This is the root screen: the Figma frame draws a back chevron here,
        // but there is nothing to pop back to, so the slot holds the profile
        // entry instead. Do not re-add the chevron from the design.
        automaticallyImplyLeading: false,
        leading: _ProfileEntryButton(
          avatarImage: resolveUserAvatar(state.user?.avatarUrl),
          onPressed:
              onOpenProfile ??
              () => Navigator.pushNamed(context, AppRoutes.mine),
        ),
        actions: <Widget>[
          _AddDeviceButton(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.deviceSearch),
          ),
        ],
      ),
      background: AppPageBackground.standard,
      body: RefreshIndicator(
        color: AppColors.brandPrimary,
        onRefresh: state.refreshDevices,
        child: ResponsiveContent(
          maxWidth: 375,
          padding: EdgeInsets.zero,
          child: items.isEmpty
              ? const _EmptyDeviceList()
              : ListView.separated(
                  key: const Key('device-list-view'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 35, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final device = items[index];
                    return _DeviceListCard(
                      key: Key('device-list-item-${device.id}'),
                      device: device,
                      onTap: () => _openDevice(context, state, device),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _ProfileEntryButton extends StatelessWidget {
  const _ProfileEntryButton({required this.onPressed, this.avatarImage});

  final VoidCallback onPressed;
  final ImageProvider<Object>? avatarImage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: '个人中心',
        child: AppAvatar(
          key: const Key('device-list-profile-button'),
          size: 32,
          imageProvider: avatarImage,
          fallback: Image.asset(
            AppAssets.profileAvatarIcon,
            width: 32,
            height: 32,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
          backgroundColor: AppColors.brandSurface,
          onTap: onPressed,
        ),
      ),
    );
  }
}

class _AddDeviceButton extends StatelessWidget {
  const _AddDeviceButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: IconButton(
        key: const Key('device-list-add-button'),
        tooltip: '添加设备',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(40),
          padding: EdgeInsets.zero,
        ),
        icon: Image.asset(
          AppAssets.addIcon,
          width: 30,
          height: 30,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _DeviceListCard extends StatelessWidget {
  const _DeviceListCard({required this.device, required this.onTap, super.key});

  final SmartPlanterDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 92,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 17, 7),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 52,
                  child: Center(
                    child: Image.asset(
                      AppAssets.smartPlanterWithPlant,
                      width: 48,
                      height: 62,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      semanticLabel: '带植物的 YSplanter',
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _OnlinePill(online: device.online),
                    ],
                  ),
                ),
                const AppTrailingChevron(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnlinePill extends StatelessWidget {
  const _OnlinePill({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final foreground = online
        ? AppColors.brandPrimary
        : AppColors.textSecondary;
    final background = online
        ? AppColors.brandSurface
        : AppColors.divider.withValues(alpha: .72);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.full,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 7),
            ),
            const SizedBox(width: 7),
            Text(
              online ? '在线' : '离线',
              style: TextStyle(color: foreground, fontSize: 14, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDeviceList extends StatelessWidget {
  const _EmptyDeviceList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 180, 20, 24),
      children: <Widget>[
        Image.asset(
          AppAssets.devicePlanterIcon,
          key: const Key('empty-device-list-illustration'),
          width: 54,
          height: 54,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: 16),
        const Text(
          '暂无设备',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
