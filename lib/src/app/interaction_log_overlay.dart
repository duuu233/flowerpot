import 'package:flutter/material.dart';

import '../design_system/design_system.dart';
import '../features/home/presentation/widgets/interaction_log_panel.dart';
import '../routes/app_routes.dart';
import '../state.dart';
import 'flowerpot_app.dart';

/// **全局联调日志（临时）。**
///
/// 2026-09-12 产品先要「设备详情页底部加日志框」，随后追加「一些交互多、比较复杂
/// 的页面也要加」「只要内容多的就都需要」。逐页往 `children` 里插面板试过一轮：十
/// 个候选页里有三个的结构对不上，插进去还容易落到嵌套列表里去，而且每加一个新页
/// 面就得再补一次。所以改成挂在 [MaterialApp.builder] 上的一层浮层——**一处改动，
/// 所有页面都有**，也不动任何页面的布局。
///
/// 默认是左下角一颗小药丸，点开才展开日志框，正常使用时不挡视线。
///
/// ⚠️ **临时设施**，流程验通后连同 [FlowerpotState.interactionLog] 一起去掉。
class InteractionLogOverlay extends StatefulWidget {
  const InteractionLogOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<InteractionLogOverlay> createState() => _InteractionLogOverlayState();
}

class _InteractionLogOverlayState extends State<InteractionLogOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.maybeOf(context);
    // 闪屏和登录页没有设备交互，不挂。
    if (state == null || !state.authenticated) return widget.child;

    return Stack(
      // Navigator 是唯一的非定位子件，必须撑满；默认的 loose 会让它按自身意愿
      // 取尺寸，整个 App 就塌了。
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        Positioned(
          left: 12,
          right: _open ? 12 : null,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: Material(
              type: MaterialType.transparency,
              child: _open
                  ? InteractionLogPanel(
                      onClose: () => setState(() => _open = false),
                    )
                  : _LogPill(
                      count: state.interactionLog.length,
                      onTap: () => setState(() => _open = true),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LogPill extends StatelessWidget {
  const _LogPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('interaction-log-pill'),
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '联调日志 $count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 进页面时把这一页对应的功能点和当前取到的值写进日志。
///
/// 产品的原话是「例如设置页面，刚进来的时候就要读取功能设置对应的 DPID 是什么、
/// 接收到的值是什么」。挂成 [NavigatorObserver] 而不是每页调一次，理由同上：路由
/// 表在这一处就全了，新增页面只加一行映射。
class InteractionLogRouteObserver extends NavigatorObserver {
  InteractionLogRouteObserver(this.state);

  final FlowerpotState state;

  /// 各页面用到的设置键，和页面里 `updateSetting(...)` 的那几个一一对应。
  static const Map<String, List<String>> pageSettingKeys =
      <String, List<String>>{
        AppRoutes.displaySettings: <String>['autoBrightness'],
        AppRoutes.hearingSettings: <String>[
          'soundInteraction',
          'soundSensitivity',
        ],
        AppRoutes.touchSettings: <String>[
          'touchInteraction',
          'touchSensitivity',
        ],
        AppRoutes.vibrationSettings: <String>[
          'vibration',
          'touchKeyVibration',
          'touchPlantVibration',
        ],
        AppRoutes.ledSettings: <String>['led'],
        AppRoutes.plantDetectionSettings: <String>['plantDetection'],
        AppRoutes.behaviorSettings: <String>[
          'napEnabled',
          'napPeriod',
          'nightEnabled',
          'nightPeriod',
          'standby',
          'standbyDelay',
        ],
        AppRoutes.deviceOtherSettings: <String>[
          'temperatureUnit',
          'clockFormat',
        ],
        // 设备设置页一进来就要把整页菜单的值都读出来，所以列全。
        AppRoutes.deviceSettings: <String>[
          'plantDetection',
          'autoBrightness',
          'soundInteraction',
          'touchInteraction',
          'vibration',
          'napEnabled',
          'nightEnabled',
          'standby',
        ],
      };

  static const Map<String, String> pageLabels = <String, String>{
    AppRoutes.deviceHome: '设备详情',
    AppRoutes.deviceInfo: '设备信息',
    AppRoutes.deviceSettings: '设备设置',
    AppRoutes.deviceOtherSettings: '其他设置',
    AppRoutes.displaySettings: '显示设置',
    AppRoutes.hearingSettings: '听觉设置',
    AppRoutes.touchSettings: '触摸设置',
    AppRoutes.vibrationSettings: '震动设置',
    AppRoutes.ledSettings: 'LED设置',
    AppRoutes.plantDetectionSettings: '自动检测植物',
    AppRoutes.behaviorSettings: '行为设置',
    AppRoutes.animations: '定制动画',
    AppRoutes.reports: '报表',
    AppRoutes.plantPicker: '选择植物',
    AppRoutes.plantDetail: '植物详情',
    AppRoutes.memorial: '纪念日',
    AppRoutes.memorialEdit: '编辑纪念日',
    AppRoutes.lightStatus: '光照',
    AppRoutes.waterStatus: '水位',
    AppRoutes.temperatureStatus: '温度',
    AppRoutes.humidityStatus: '湿度',
    AppRoutes.batteryStatus: '电量',
    AppRoutes.deviceSearch: '搜索设备',
    AppRoutes.pairing: '配网',
  };

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _logRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) _logRoute(previousRoute);
  }

  void _logRoute(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || !name.startsWith('/devices/')) return;
    final label = pageLabels[name] ?? name;
    final keys = pageSettingKeys[name];
    final arguments = route.settings.arguments;

    // didPush 发生在一帧当中，直接 notifyListeners 会撞上「build 期间
    // markNeedsBuild」，所以推到帧末再记。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (keys == null || arguments is! String) {
        state.logPageEntry(label);
        return;
      }
      state.logSettingsSnapshot(arguments, label, keys);
    });
  }
}
