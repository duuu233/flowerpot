import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../../home/presentation/widgets/home_care_banner.dart';
import '../models/device_settings_page_model.dart';
import 'device_online_guard.dart';
import 'plant_picker_page.dart';
import 'widgets/device_settings_function_list.dart';
import 'widgets/device_settings_summary_card.dart';

/// 分享设备入口的开关。
///
/// 产品要求先隐藏、后期再做，所以留着 [_DeviceSettingsPageState._share] 和这里的
/// 按钮，把开关翻成 true 就恢复，不用重新写一遍分享链路。
const bool _shareEntryEnabled = false;

class DeviceSettingsPage extends StatefulWidget {
  const DeviceSettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage>
    with NetworkRetryAware<DeviceSettingsPage> {
  @override
  void initState() {
    super.initState();
    // 固件版本藏在「其他设置」里，用户不点进去就不知道有没有新版本。所以一进
    // 设置页就静默问一次涂鸦（App 不直接问设备），有新版本就在那一行点红点。
    // 失败无声，见 FlowerpotState.refreshFirmwareUpdate。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FlowerpotScope.of(context).refreshFirmwareUpdate(widget.deviceId);
    });
  }

  /// 「网络异常」弹窗点「重试」：重读设备，再问一次有没有新固件。
  @override
  Future<void> reloadForNetworkRetry() async {
    final state = FlowerpotScope.of(context);
    await state.reloadDevices();
    if (!mounted) return;
    await state.refreshFirmwareUpdate(widget.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = widget.deviceId;
    final state = FlowerpotScope.of(context);
    final device = state.deviceById(deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '设置', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final model = DeviceSettingsPageModel.fromDevice(
      device,
      firmwareUpdate: state.hasFirmwareUpdate(deviceId),
    );
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: '设置',
        leading: const AppBackButton(),
        actions: _shareEntryEnabled
            ? <Widget>[
                AppIconButton(
                  icon: Icons.ios_share_outlined,
                  tooltip: '分享设备',
                  color: AppColors.textSecondary,
                  size: 44,
                  onPressed: () => _share(context, device.id),
                ),
              ]
            : null,
      ),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                37,
                AppSpacing.pageMargin,
                40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DeviceSettingsSummaryCard(
                    model: model,
                    onMore: () => _showMore(context, device),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DeviceSettingsFunctionList(
                    items: model.menuItems,
                    onItemTap: (kind) => _openMenu(context, device, kind),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openMenu(
    BuildContext context,
    SmartPlanterDevice device,
    DeviceSettingsMenuKind kind,
  ) {
    // 每一项点进去都要先确认设备在线。
    if (!ensureDeviceOnline(context, device.id)) {
      return;
    }
    if (kind == DeviceSettingsMenuKind.plant) {
      // 盆里没有植物（DP 116 == -1）时不让选：选了也会被设备下一次上报覆盖，
      // 用户该做的是先把植物种进去。
      if (FlowerpotScope.of(context).plantMissing(device.id)) {
        showAppMessage(
          context,
          HomeCareBanner.plantMissingNotice,
          tone: AppMessageTone.info,
        );
        return;
      }
      Navigator.pushNamed(
        context,
        AppRoutes.plantPicker,
        arguments: PlantPickerArguments(
          deviceId: device.id,
          mode: PlantPickerMode.select,
        ),
      );
      return;
    }
    final String route = switch (kind) {
      DeviceSettingsMenuKind.plant => AppRoutes.plantPicker,
      DeviceSettingsMenuKind.display => AppRoutes.displaySettings,
      DeviceSettingsMenuKind.led => AppRoutes.ledSettings,
      DeviceSettingsMenuKind.hearing => AppRoutes.hearingSettings,
      DeviceSettingsMenuKind.touch => AppRoutes.touchSettings,
      DeviceSettingsMenuKind.vibration => AppRoutes.vibrationSettings,
      DeviceSettingsMenuKind.behavior => AppRoutes.behaviorSettings,
      DeviceSettingsMenuKind.memorial => AppRoutes.memorial,
      DeviceSettingsMenuKind.other => AppRoutes.deviceOtherSettings,
      DeviceSettingsMenuKind.plantDetection => AppRoutes.plantDetectionSettings,
    };
    Navigator.pushNamed(context, route, arguments: device.id);
  }

  Future<void> _share(BuildContext context, String id) async {
    final result = await FlowerpotScope.of(context).createShareLink(id);
    if (!context.mounted) return;
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
      return;
    }
    await Clipboard.setData(ClipboardData(text: result.message));
    if (context.mounted) {
      showAppMessage(context, '分享链接已复制');
    }
  }

  void _showMore(BuildContext context, SmartPlanterDevice device) {
    if (!ensureDeviceOnline(context, device.id)) return;
    Navigator.pushNamed(context, AppRoutes.deviceInfo, arguments: device.id);
  }
}
