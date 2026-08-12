import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../models/device_settings_page_model.dart';
import 'plant_picker_page.dart';
import 'widgets/device_settings_function_list.dart';
import 'widgets/device_settings_summary_card.dart';

class DeviceSettingsPage extends StatelessWidget {
  const DeviceSettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final device = state.deviceById(deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '设置', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final model = DeviceSettingsPageModel.fromDevice(device);
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: '设置',
        leading: const AppBackButton(),
        actions: <Widget>[
          AppIconButton(
            icon: Icons.ios_share_outlined,
            tooltip: '分享设备',
            color: AppColors.textSecondary,
            size: 44,
            onPressed: () => _share(context, device.id),
          ),
        ],
      ),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
              maxWidth: 375,
              padding: const EdgeInsets.fromLTRB(20, 72, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DeviceSettingsSummaryCard(
                    model: model,
                    onMore: () => _showMore(context, device),
                  ),
                  const SizedBox(height: AppSpacing.xl),
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
    if (kind == DeviceSettingsMenuKind.plant) {
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
    final route = switch (kind) {
      DeviceSettingsMenuKind.plant => AppRoutes.plantPicker,
      DeviceSettingsMenuKind.display => AppRoutes.displaySettings,
      DeviceSettingsMenuKind.hearing => AppRoutes.hearingSettings,
      DeviceSettingsMenuKind.touch => AppRoutes.touchSettings,
      DeviceSettingsMenuKind.vibration => AppRoutes.vibrationSettings,
      DeviceSettingsMenuKind.behavior => AppRoutes.behaviorSettings,
      DeviceSettingsMenuKind.other => AppRoutes.deviceOtherSettings,
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
    Navigator.pushNamed(context, AppRoutes.deviceInfo, arguments: device.id);
  }
}
