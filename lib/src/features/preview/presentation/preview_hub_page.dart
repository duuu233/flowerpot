import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../../auth/presentation/auth_page.dart';
import '../../auth/presentation/password_page.dart';
import '../../devices/models/water_status_page_model.dart';
import '../../devices/presentation/device_list_page.dart';
import '../../devices/presentation/plant_detail_page.dart';
import '../../devices/presentation/plant_picker_page.dart';
import '../../devices/presentation/reports_page.dart';
import '../../home/models/home_dashboard_model.dart';
import '../../home/presentation/home_page.dart';
import '../../profile/presentation/app_settings_page.dart';
import '../../profile/presentation/login_password_page.dart';
import '../../profile/presentation/modify_password_page.dart';
import '../preview_config.dart';
import 'preview_return_overlay.dart';

class PreviewHubPage extends StatefulWidget {
  const PreviewHubPage({super.key});

  @override
  State<PreviewHubPage> createState() => _PreviewHubPageState();
}

class _PreviewHubPageState extends State<PreviewHubPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final demoReady = state.demoMode && state.selectedDevice != null;
    final sections = _visibleSections(_query);
    final visibleCount = sections.fold<int>(
      0,
      (count, section) => count + section.scenarios.length,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF3F0E4),
      body: CustomScrollView(
        key: const Key('preview-hub-scroll-view'),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _PreviewHero(
              totalCount: _scenarioCount,
              demoReady: demoReady,
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SearchHeaderDelegate(
              controller: _searchController,
              query: _query,
              visibleCount: visibleCount,
              onChanged: (value) => setState(() => _query = value),
              onClear: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            ),
          ),
          if (sections.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: _NoResults())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 48),
              sliver: SliverList.separated(
                itemCount: sections.length,
                separatorBuilder: (_, _) => const SizedBox(height: 24),
                itemBuilder: (context, index) => _PreviewSectionCard(
                  section: sections[index],
                  demoReady: demoReady,
                  onOpen: (scenario) => _openScenario(context, scenario),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openScenario(BuildContext context, _PreviewScenario scenario) {
    if (scenario.route != null) {
      Navigator.pushNamed(
        context,
        scenario.route!,
        arguments: scenario.arguments,
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/preview/${scenario.id}'),
        builder: (routeContext) =>
            PreviewReturnOverlay(child: scenario.builder!(routeContext)),
      ),
    );
  }
}

class _PreviewHero extends StatelessWidget {
  const _PreviewHero({required this.totalCount, required this.demoReady});

  final int totalCount;
  final bool demoReady;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF173F35),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'STATIC PAGE LAB',
                          style: TextStyle(
                            color: Color(0xFFC9DC9B),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '页面场景\n调试目录',
                          style: TextStyle(
                            color: Color(0xFFF5F1DF),
                            fontSize: 34,
                            height: 1.06,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.8,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '共 $totalCount 个入口 · 点击场景即可独立检查样式',
                          style: const TextStyle(
                            color: Color(0xBFF5F1DF),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 78,
                    height: 106,
                    decoration: BoxDecoration(
                      color: const Color(0xFF244E42),
                      border: Border.all(color: const Color(0x337CE0AF)),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: const Icon(
                      Icons.eco_rounded,
                      size: 42,
                      color: Color(0xFFC9DC9B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: demoReady
                      ? const Color(0xFF244E42)
                      : const Color(0xFF534B2D),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    if (demoReady)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFFC9DC9B),
                        size: 17,
                      )
                    else
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFF3C969),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        demoReady ? '演示数据已就绪，设备相关页面可以直接打开' : '正在准备本地演示设备…',
                        style: const TextStyle(
                          color: Color(0xFFEAE7D5),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
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

class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SearchHeaderDelegate({
    required this.controller,
    required this.query,
    required this.visibleCount,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final int visibleCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  double get minExtent => 82;

  @override
  double get maxExtent => 82;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(
      child: ColoredBox(
        color: const Color(0xFFF3F0E4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: TextField(
            key: const Key('preview-search-field'),
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索页面或状态',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      tooltip: '清空搜索',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(right: 13),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          '$visibleCount',
                          style: const TextStyle(
                            color: Color(0xFF6C776F),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
              filled: true,
              fillColor: const Color(0xFFFFFDF6),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFFD8D4C7)),
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFFD8D4C7)),
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(
                  color: Color(0xFF37725D),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate oldDelegate) =>
      oldDelegate.query != query || oldDelegate.visibleCount != visibleCount;
}

class _PreviewSectionCard extends StatelessWidget {
  const _PreviewSectionCard({
    required this.section,
    required this.demoReady,
    required this.onOpen,
  });

  final _PreviewSection section;
  final bool demoReady;
  final ValueChanged<_PreviewScenario> onOpen;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCD7C8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D173F35),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: section.accent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(section.icon, color: section.accent, size: 21),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          section.title,
                          style: const TextStyle(
                            color: Color(0xFF1C2F28),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${section.scenarios.length} 个页面场景',
                          style: const TextStyle(
                            color: Color(0xFF788078),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            for (var index = 0; index < section.scenarios.length; index++) ...[
              _ScenarioButton(
                scenario: section.scenarios[index],
                enabled: !section.scenarios[index].requiresDevice || demoReady,
                accent: section.accent,
                onTap: () => onOpen(section.scenarios[index]),
              ),
              if (index != section.scenarios.length - 1)
                const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScenarioButton extends StatelessWidget {
  const _ScenarioButton({
    required this.scenario,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  final _PreviewScenario scenario;
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? const Color(0xFFF6F3E9) : const Color(0xFFF0EEE7),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('preview-scenario-${scenario.id}'),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 6,
                height: 34,
                decoration: BoxDecoration(
                  color: enabled ? accent : const Color(0xFFB8B8B1),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      scenario.title,
                      style: TextStyle(
                        color: enabled
                            ? const Color(0xFF20322B)
                            : const Color(0xFF8D918D),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    if (scenario.description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        enabled ? scenario.description! : '演示设备准备中',
                        style: const TextStyle(
                          color: Color(0xFF7A817B),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                enabled ? Icons.arrow_outward_rounded : Icons.hourglass_top,
                color: enabled ? accent : const Color(0xFFA4A7A2),
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.manage_search_rounded,
              size: 46,
              color: Color(0xFF718078),
            ),
            SizedBox(height: 12),
            Text(
              '没有匹配的页面场景',
              style: TextStyle(
                color: Color(0xFF43544C),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSection {
  const _PreviewSection({
    required this.title,
    required this.icon,
    required this.accent,
    required this.scenarios,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final List<_PreviewScenario> scenarios;

  _PreviewSection withScenarios(List<_PreviewScenario> value) =>
      _PreviewSection(
        title: title,
        icon: icon,
        accent: accent,
        scenarios: value,
      );
}

class _PreviewScenario {
  const _PreviewScenario.named({
    required this.id,
    required this.title,
    required this.route,
    this.description,
    this.arguments,
    this.requiresDevice = false,
  }) : builder = null;

  const _PreviewScenario.page({
    required this.id,
    required this.title,
    required this.builder,
    this.description,
    this.requiresDevice = false,
  }) : route = null,
       arguments = null;

  final String id;
  final String title;
  final String? description;
  final String? route;
  final Object? arguments;
  final WidgetBuilder? builder;
  final bool requiresDevice;

  bool matches(String query) {
    final target = '$title ${description ?? ''} $id'.toLowerCase();
    return target.contains(query);
  }
}

List<_PreviewSection> _visibleSections(String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return _previewSections;
  return <_PreviewSection>[
    for (final section in _previewSections)
      if (section.scenarios.any((scenario) => scenario.matches(normalized)))
        section.withScenarios(
          section.scenarios
              .where((scenario) => scenario.matches(normalized))
              .toList(growable: false),
        ),
  ];
}

int get _scenarioCount => _previewSections.fold<int>(
  0,
  (count, section) => count + section.scenarios.length,
);

const _deviceId = StaticPreviewConfig.demoDeviceId;
const _pairingRequest = PairingRequest(
  ssid: 'YSplanter Preview Wi-Fi',
  password: 'preview123',
);

final List<_PreviewSection> _previewSections = <_PreviewSection>[
  _PreviewSection(
    title: '账号与入口',
    icon: Icons.key_rounded,
    accent: const Color(0xFFB26A43),
    scenarios: <_PreviewScenario>[
      const _PreviewScenario.named(
        id: 'auth-code',
        title: '登录页-验证码登录',
        route: AppRoutes.auth,
        description: '登录页默认状态',
      ),
      _PreviewScenario.page(
        id: 'auth-password',
        title: '登录页-密码登录',
        description: '直接展示密码输入状态',
        builder: (_) => const AuthPage(initialCodeLogin: false),
      ),
      const _PreviewScenario.named(
        id: 'register',
        title: '注册页',
        route: AppRoutes.register,
      ),
      const _PreviewScenario.named(
        id: 'forgot-password-phone',
        title: '忘记密码',
        route: AppRoutes.password,
      ),
      const _PreviewScenario.named(
        id: 'forgot-password-email',
        title: '忘记密码-邮箱',
        route: AppRoutes.password,
        arguments: PasswordArguments(region: LoginRegion.overseas),
      ),
    ],
  ),
  _PreviewSection(
    title: '首页场景',
    icon: Icons.home_rounded,
    accent: const Color(0xFF33735E),
    scenarios: <_PreviewScenario>[
      const _PreviewScenario.named(
        id: 'shell-home',
        title: '首页-Shell入口',
        route: AppRoutes.shell,
        description: '保留后续串联真实流程时的首页入口',
        requiresDevice: true,
      ),
      _PreviewScenario.page(
        id: 'home-companion',
        title: '首页-已添加植物',
        description: '显示陪伴天数与电量摘要',
        requiresDevice: true,
        builder: (_) =>
            const HomePage(scene: HomeDashboardScene.withCompanionSummary),
      ),
      _PreviewScenario.page(
        id: 'home-compact',
        title: '首页-已添加植物-1',
        description: '隐藏陪伴摘要的另一种首页状态',
        requiresDevice: true,
        builder: (_) =>
            const HomePage(scene: HomeDashboardScene.withoutCompanionSummary),
      ),
      _PreviewScenario.page(
        id: 'home-without-plant',
        title: '首页-未添加植物',
        description: '设备存在，等待选择植物',
        requiresDevice: true,
        builder: (_) => const HomePage(scene: HomeDashboardScene.withoutPlant),
      ),
      _PreviewScenario.page(
        id: 'home-without-device',
        title: '登录后无设备',
        description: '空设备引导状态',
        builder: (_) => HomePage(
          dashboard: HomeDashboardModel.fromDevice(
            device: null,
            userLabel: '植物守护者',
          ),
        ),
      ),
    ],
  ),
  _PreviewSection(
    title: '配网流程',
    icon: Icons.wifi_tethering_rounded,
    accent: const Color(0xFF3D7191),
    scenarios: <_PreviewScenario>[
      const _PreviewScenario.named(
        id: 'pairing',
        title: '连接Wi-Fi',
        route: AppRoutes.pairing,
      ),
      const _PreviewScenario.named(
        id: 'device-search',
        title: '搜索附近设备',
        route: AppRoutes.deviceSearch,
        arguments: _pairingRequest,
      ),
      const _PreviewScenario.named(
        id: 'device-selection',
        title: '选择设备',
        route: AppRoutes.deviceSelection,
        arguments: _pairingRequest,
      ),
      const _PreviewScenario.named(
        id: 'pairing-failure',
        title: '连接设备失败',
        route: AppRoutes.pairingFailure,
        arguments: _pairingRequest,
      ),
      const _PreviewScenario.named(
        id: 'pairing-success',
        title: '连接设备成功',
        route: AppRoutes.pairingSuccess,
        arguments: _deviceId,
        requiresDevice: true,
      ),
    ],
  ),
  _PreviewSection(
    title: '植物与设备',
    icon: Icons.local_florist_rounded,
    accent: const Color(0xFF62813A),
    scenarios: <_PreviewScenario>[
      const _PreviewScenario.named(
        id: 'device-list',
        title: '设备列表页面',
        route: AppRoutes.deviceList,
        requiresDevice: true,
      ),
      _PreviewScenario.page(
        id: 'device-list-empty',
        title: '设备列表页面-空状态',
        description: '没有已绑定设备',
        builder: (_) => const DeviceListPage(devices: <SmartPlanterDevice>[]),
      ),
      _PreviewScenario.page(
        id: 'plant-picker-add',
        title: '添加植物',
        requiresDevice: true,
        builder: (_) => const PlantPickerPage(
          deviceId: _deviceId,
          mode: PlantPickerMode.add,
        ),
      ),
      _PreviewScenario.page(
        id: 'plant-picker-select',
        title: '选择植物',
        requiresDevice: true,
        builder: (_) => const PlantPickerPage(
          deviceId: _deviceId,
          mode: PlantPickerMode.select,
        ),
      ),
      _PreviewScenario.named(
        id: 'plant-detail-unbound',
        title: '植物详情-未绑定',
        route: AppRoutes.plantDetail,
        arguments: PlantDetailArguments(plant: PlantCatalog.items.first),
      ),
      _PreviewScenario.named(
        id: 'plant-detail-bound',
        title: '植物详情',
        route: AppRoutes.plantDetail,
        arguments: PlantDetailArguments(
          plant: PlantCatalog.items.first,
          bound: true,
        ),
      ),
      const _PreviewScenario.named(
        id: 'device-info',
        title: '更多设备信息',
        route: AppRoutes.deviceInfo,
        arguments: _deviceId,
        requiresDevice: true,
      ),
    ],
  ),
  _PreviewSection(
    title: '传感器与报表',
    icon: Icons.monitor_heart_rounded,
    accent: const Color(0xFF24858A),
    scenarios: <_PreviewScenario>[
      const _PreviewScenario.named(
        id: 'water-level',
        title: '需水状态-水仓水位变化',
        route: AppRoutes.waterStatus,
        arguments: WaterStatusArguments(
          deviceId: _deviceId,
          initialMetric: WaterStatusMetric.waterLevel,
        ),
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'soil-moisture',
        title: '需水状态-土壤湿度变化',
        route: AppRoutes.waterStatus,
        arguments: WaterStatusArguments(
          deviceId: _deviceId,
          initialMetric: WaterStatusMetric.soilMoisture,
        ),
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'light-status',
        title: '光照状态',
        route: AppRoutes.lightStatus,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'temperature-status',
        title: '空气温度',
        route: AppRoutes.temperatureStatus,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'humidity-status',
        title: '相对湿度',
        route: AppRoutes.humidityStatus,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'battery-status',
        title: '电池状态',
        route: AppRoutes.batteryStatus,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      for (final metric in SensorMetric.values)
        _PreviewScenario.named(
          id: 'report-${metric.name}',
          title: '数据报表-${_metricLabel(metric)}',
          route: AppRoutes.reports,
          arguments: ReportArguments(deviceId: _deviceId, metric: metric),
          requiresDevice: true,
        ),
    ],
  ),
  _PreviewSection(
    title: '设备设置',
    icon: Icons.tune_rounded,
    accent: const Color(0xFF6B66A8),
    scenarios: <_PreviewScenario>[
      const _PreviewScenario.named(
        id: 'device-settings',
        title: '设置',
        route: AppRoutes.deviceSettings,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'display-settings',
        title: '显示',
        route: AppRoutes.displaySettings,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'hearing-settings',
        title: '听觉感知',
        route: AppRoutes.hearingSettings,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'touch-settings',
        title: '触觉感知',
        route: AppRoutes.touchSettings,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'vibration-settings',
        title: '震动设置',
        route: AppRoutes.vibrationSettings,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'behavior-settings',
        title: '行为',
        route: AppRoutes.behaviorSettings,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'other-settings',
        title: '其他设置',
        route: AppRoutes.deviceOtherSettings,
        arguments: _deviceId,
        requiresDevice: true,
      ),
      const _PreviewScenario.named(
        id: 'animations',
        title: '定制动画',
        route: AppRoutes.animations,
        arguments: _deviceId,
        requiresDevice: true,
      ),
    ],
  ),
  _PreviewSection(
    title: '个人中心',
    icon: Icons.person_rounded,
    accent: const Color(0xFFA05267),
    scenarios: <_PreviewScenario>[
      const _PreviewScenario.named(
        id: 'mine',
        title: '我的',
        route: AppRoutes.mine,
      ),
      const _PreviewScenario.named(
        id: 'profile',
        title: '个人信息',
        route: AppRoutes.profile,
      ),
      const _PreviewScenario.named(
        id: 'account-security',
        title: '账号与安全',
        route: AppRoutes.settings,
      ),
      const _PreviewScenario.named(
        id: 'login-password',
        title: '登录密码',
        route: AppRoutes.loginPassword,
        arguments: LoginPasswordArguments(account: '138****8000'),
      ),
      const _PreviewScenario.named(
        id: 'modify-password',
        title: '修改密码',
        route: AppRoutes.modifyPassword,
        arguments: ModifyPasswordArguments(account: '13800138000'),
      ),
      const _PreviewScenario.named(
        id: 'help',
        title: '帮助中心',
        route: AppRoutes.help,
      ),
      const _PreviewScenario.named(
        id: 'privacy',
        title: '隐私政策',
        route: AppRoutes.privacy,
      ),
      const _PreviewScenario.named(
        id: 'agreement',
        title: '用户协议',
        route: AppRoutes.agreement,
      ),
      const _PreviewScenario.named(
        id: 'about',
        title: '关于YSplanter',
        route: AppRoutes.about,
      ),
      _PreviewScenario.page(
        id: 'legacy-app-settings',
        title: '应用设置-旧入口',
        description: '保留现有 AppSettingsPage 供样式对照',
        builder: (_) => const AppSettingsPage(),
      ),
    ],
  ),
];

String _metricLabel(SensorMetric metric) => switch (metric) {
  SensorMetric.waterLevel => '水仓水位',
  SensorMetric.soilMoisture => '土壤湿度',
  SensorMetric.light => '光照强度',
  SensorMetric.ppfd => 'PPFD',
  SensorMetric.dli => 'DLI',
  SensorMetric.temperature => '空气温度',
  SensorMetric.humidity => '相对湿度',
  SensorMetric.battery => '电池电量',
};
