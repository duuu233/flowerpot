import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    return AppBackground(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: state.refreshDevices,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 110),
                sliver: SliverList.list(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '早上好，${state.user?.nickname ?? '植物守护者'}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '今天也要好好生长',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: () =>
                              showAppMessage(context, '目前没有新的设备消息'),
                          icon: const Icon(Icons.notifications_none_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    GlassCard(
                      color: AppColors.ink,
                      child: Row(
                        children: <Widget>[
                          const ContainerWeatherIcon(),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '杭州市 · 多云',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '26°  空气湿度 63%',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatusPill(
                            label: '适合通风',
                            icon: Icons.air_rounded,
                            color: AppColors.lime,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    SectionTitle(
                      '我的设备',
                      trailing: TextButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, AppRoutes.pairing),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('添加'),
                      ),
                    ),
                    if (state.devices.isEmpty)
                      _EmptyDevices(
                        onAdd: () =>
                            Navigator.pushNamed(context, AppRoutes.pairing),
                      )
                    else
                      for (final device in state.devices) ...<Widget>[
                        _DeviceCard(
                          device: device,
                          onTap: () {
                            state.selectDevice(device.id);
                            Navigator.pushNamed(
                              context,
                              AppRoutes.device,
                              arguments: device.id,
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                    if (state.demoMode) ...<Widget>[
                      const SizedBox(height: 8),
                      const Center(
                        child: StatusPill(
                          label: '当前为体验数据 · 接入密钥后切换真实设备',
                          icon: Icons.science_outlined,
                          color: AppColors.sun,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContainerWeatherIcon extends StatelessWidget {
  const ContainerWeatherIcon({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 50,
    height: 50,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Icon(Icons.cloud_outlined, color: AppColors.lime),
  );
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onTap});

  final SmartPlanterDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlassCard(
    onTap: onTap,
    padding: const EdgeInsets.all(18),
    child: Column(
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 104,
              height: 112,
              decoration: BoxDecoration(
                color: device.plant.color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: PlantIllustration(
                size: 100,
                leafColor: device.plant.color,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          device.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${device.plant.name} · 已陪伴 ${device.companionDays} 天'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: <Widget>[
                      StatusPill(
                        label: device.online ? '在线' : '离线',
                        icon: Icons.wifi_rounded,
                        color: device.online ? AppColors.leaf : AppColors.muted,
                      ),
                      StatusPill(
                        label: device.charging
                            ? '充电中 ${device.battery}%'
                            : '电量 ${device.battery}%',
                        icon: device.charging
                            ? Icons.bolt_rounded
                            : Icons.battery_5_bar_rounded,
                        color: device.battery < 20
                            ? AppColors.danger
                            : AppColors.water,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _MiniMetric(
                label: '土壤',
                value: '${device.sensors.soilMoisture}%',
              ),
              const SizedBox(height: 28, child: VerticalDivider()),
              _MiniMetric(label: '水仓', value: '${device.sensors.waterLevel}%'),
              const SizedBox(height: 28, child: VerticalDivider()),
              _MiniMetric(
                label: '温度',
                value: '${device.sensors.airTemperature.toStringAsFixed(1)}°',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text(
        value,
        style: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
    ],
  );
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => GlassCard(
    child: Column(
      children: <Widget>[
        const PlantIllustration(size: 138, leafColor: AppColors.muted),
        Text('还没有连接花盆', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('添加一台设备，开始记录植物的每一天。'),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加设备'),
        ),
      ],
    ),
  );
}
