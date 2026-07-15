import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';
import 'reports_page.dart';

class DeviceDashboardPage extends StatelessWidget {
  const DeviceDashboardPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final device = state.deviceById(deviceId);
    if (device == null) {
      return const Scaffold(body: Center(child: Text('设备不存在或已解绑')));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(device.name),
        actions: <Widget>[
          IconButton(
            tooltip: '设备设置',
            onPressed: () => Navigator.pushNamed(
              context,
              AppRoutes.deviceSettings,
              arguments: device.id,
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
            children: <Widget>[
              _HeroCard(device: device),
              const SizedBox(height: 24),
              SectionTitle(
                '生长状态',
                trailing: IconButton(
                  tooltip: '状态说明',
                  onPressed: () => _showFaq(context, device),
                  icon: const Icon(Icons.help_outline_rounded),
                ),
              ),
              GridView.count(
                crossAxisCount: 2,
                childAspectRatio: .94,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  MetricTile(
                    title: '需水状态',
                    value: '${device.sensors.soilMoisture}%',
                    status:
                        device.sensors.soilMoisture >=
                            device.plant.moistureTarget - 8
                        ? '水分刚刚好'
                        : '需要补水',
                    icon: Icons.water_drop_outlined,
                    color: AppColors.water,
                    onTap: () =>
                        _openReport(context, device, SensorMetric.soilMoisture),
                  ),
                  MetricTile(
                    title: '当前水仓',
                    value: '${device.sensors.waterLevel}%',
                    status: device.sensors.waterLevel > 25 ? '储水充足' : '请添加水',
                    icon: Icons.water_outlined,
                    color: const Color(0xFF3887BE),
                    onTap: () =>
                        _openReport(context, device, SensorMetric.waterLevel),
                  ),
                  MetricTile(
                    title: '环境光照',
                    value: '${device.sensors.illuminance} lx',
                    status: device.sensors.illuminance > 500 ? '环境明亮' : '环境偏暗',
                    icon: Icons.light_mode_outlined,
                    color: AppColors.sun,
                    onTap: () =>
                        _openReport(context, device, SensorMetric.light),
                  ),
                  MetricTile(
                    title: 'PPFD',
                    value: '${device.sensors.ppfd}',
                    status: device.sensors.ppfd >= device.plant.lightTarget * .7
                        ? '光照适宜'
                        : '光照偏弱',
                    icon: Icons.wb_sunny_outlined,
                    color: AppColors.sun,
                    onTap: () =>
                        _openReport(context, device, SensorMetric.ppfd),
                  ),
                  MetricTile(
                    title: 'DLI 日光积分',
                    value: (device.sensors.ppfd * .0432).toStringAsFixed(1),
                    status: '按 12 小时估算',
                    icon: Icons.bar_chart_rounded,
                    color: const Color(0xFFE29A45),
                    onTap: () => _openReport(context, device, SensorMetric.dli),
                  ),
                  MetricTile(
                    title: '空气温度',
                    value:
                        '${device.sensors.airTemperature.toStringAsFixed(1)}°C',
                    status: device.sensors.airTemperature < 29
                        ? '温度舒适'
                        : '温度偏高',
                    icon: Icons.thermostat_rounded,
                    color: AppColors.danger,
                    onTap: () =>
                        _openReport(context, device, SensorMetric.temperature),
                  ),
                  MetricTile(
                    title: '相对湿度',
                    value: '${device.sensors.relativeHumidity}%',
                    status: '空气状态良好',
                    icon: Icons.air_rounded,
                    color: const Color(0xFF7F8BC4),
                    onTap: () =>
                        _openReport(context, device, SensorMetric.humidity),
                  ),
                  MetricTile(
                    title: '电池状态',
                    value: '${device.battery}%',
                    status: device.charging
                        ? '正在充电'
                        : device.battery > 30
                        ? '电量充足'
                        : '建议充电',
                    icon: device.charging
                        ? Icons.battery_charging_full_rounded
                        : Icons.battery_5_bar_rounded,
                    color: device.battery > 30
                        ? AppColors.leaf
                        : AppColors.danger,
                    onTap: () =>
                        _openReport(context, device, SensorMetric.battery),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const SectionTitle('更多功能'),
              Row(
                children: <Widget>[
                  Expanded(
                    child: GlassCard(
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.animations,
                        arguments: device.id,
                      ),
                      child: const Column(
                        children: <Widget>[
                          Icon(
                            Icons.animation_rounded,
                            color: AppColors.leaf,
                            size: 30,
                          ),
                          SizedBox(height: 8),
                          Text(
                            '定制动画',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassCard(
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.plantPicker,
                        arguments: device.id,
                      ),
                      child: const Column(
                        children: <Widget>[
                          Icon(
                            Icons.eco_outlined,
                            color: AppColors.leaf,
                            size: 30,
                          ),
                          SizedBox(height: 8),
                          Text(
                            '选择植物',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReport(
    BuildContext context,
    SmartPlanterDevice device,
    SensorMetric metric,
  ) {
    Navigator.pushNamed(
      context,
      AppRoutes.reports,
      arguments: ReportArguments(deviceId: device.id, metric: metric),
    );
  }

  void _showFaq(BuildContext context, SmartPlanterDevice device) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('如何理解生长状态？', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 18),
            _FaqRow(
              icon: Icons.water_drop_outlined,
              title: '需水状态',
              text: '综合土壤湿度与${device.plant.name}的目标湿度判断；水仓有水不代表土壤无需补水。',
            ),
            const _FaqRow(
              icon: Icons.wb_sunny_outlined,
              title: '光照状态',
              text: 'PPFD 表示植物可利用的瞬时光强；DLI 是一天累计获得的有效光照。',
            ),
            const _FaqRow(
              icon: Icons.battery_5_bar_rounded,
              title: '电池状态',
              text: '低于 20% 时建议及时充电，充电期间仍可正常查看传感器数据。',
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.device});

  final SmartPlanterDevice device;

  @override
  Widget build(BuildContext context) => GlassCard(
    color: AppColors.ink,
    padding: const EdgeInsets.fromLTRB(18, 18, 10, 10),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    StatusPill(
                      label: device.online ? '在线 · 信号 ${device.signal}%' : '离线',
                      icon: Icons.wifi_rounded,
                      color: device.online ? AppColors.lime : Colors.white54,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  device.plant.name,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontSize: 29,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  device.plant.latinName,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 16),
                Text(
                  '我们已相伴 ${device.companionDays} 天',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  '杭州 · 26° 多云',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        PlantIllustration(size: 156, leafColor: device.plant.color),
      ],
    ),
  );
}

class _FaqRow extends StatelessWidget {
  const _FaqRow({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: AppColors.leaf),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(text),
            ],
          ),
        ),
      ],
    ),
  );
}
