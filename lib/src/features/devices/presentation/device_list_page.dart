import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../state.dart';
import '../../../tuya/tuya_models.dart';

class DeviceListPage extends StatelessWidget {
  const DeviceListPage({super.key, this.devices});

  final List<SmartPlanterDevice>? devices;

  void _openDevice(
    BuildContext context,
    FlowerpotState state,
    SmartPlanterDevice device,
  ) {
    state.selectDevice(device.id);
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.shell, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final items = devices ?? state.devices;
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: '设备列表',
        leading: const AppBackButton(),
        actions: <Widget>[
          _AddDeviceButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.pairing),
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
                  padding: const EdgeInsets.fromLTRB(20, 72, 20, 24),
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
          width: 40,
          height: 40,
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
            padding: const EdgeInsets.fromLTRB(18, 7, 17, 7),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 58,
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
                const SizedBox(width: 16),
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
      children: const <Widget>[
        Icon(
          Icons.devices_other_rounded,
          color: AppColors.brandPrimary,
          size: 54,
        ),
        SizedBox(height: 16),
        Text(
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
