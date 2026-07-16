import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../models/device_settings_page_model.dart';
import 'widgets/device_settings_control_sheet.dart';
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
      Navigator.pushNamed(context, AppRoutes.plantPicker, arguments: device.id);
      return;
    }
    showAppBottomSheet<void>(
      context,
      title: _titleFor(kind),
      builder: (sheetContext) => DeviceSettingsControlSheet(
        kind: kind,
        settings: device.settings,
        onSettingChanged: (key, value) => _setting(context, key, value),
        onPairing: () {
          Navigator.pop(sheetContext);
          Navigator.pushNamed(context, AppRoutes.pairing);
        },
        onMaintenance: (action) => _maintenance(context, action),
      ),
    );
  }

  String _titleFor(DeviceSettingsMenuKind kind) => switch (kind) {
    DeviceSettingsMenuKind.plant => '选择植物',
    DeviceSettingsMenuKind.display => '显示',
    DeviceSettingsMenuKind.hearing => '听觉感知',
    DeviceSettingsMenuKind.touch => '触觉感知',
    DeviceSettingsMenuKind.vibration => '震动设置',
    DeviceSettingsMenuKind.behavior => '行为',
    DeviceSettingsMenuKind.other => '其他设置',
  };

  Future<void> _setting(BuildContext context, String key, Object value) async {
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(deviceId, key, value);
    if (context.mounted && !result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
    }
  }

  Future<void> _maintenance(BuildContext context, String action) async {
    final result = await FlowerpotScope.of(
      context,
    ).runMaintenance(deviceId, action);
    if (context.mounted) {
      showAppMessage(
        context,
        result.message,
        tone: result.success ? AppMessageTone.success : AppMessageTone.error,
      );
    }
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
    showAppBottomSheet<void>(
      context,
      title: '更多',
      builder: (sheetContext) => AppSettingsList(
        showShadow: false,
        children: <Widget>[
          AppSettingsTile(
            title: '设备名称',
            icon: Icons.edit_outlined,
            value: device.name,
            onTap: () {
              Navigator.pop(sheetContext);
              _rename(context, device);
            },
          ),
          AppSettingsTile(
            title: '当前植物',
            icon: Icons.eco_outlined,
            value: device.plant.name,
            onTap: () {
              Navigator.pop(sheetContext);
              Navigator.pushNamed(
                context,
                AppRoutes.plantPicker,
                arguments: device.id,
              );
            },
          ),
          AppSettingsTile(
            title: '固件版本',
            icon: Icons.memory_rounded,
            value: device.firmwareVersion,
          ),
          AppSettingsTile(
            title: '设备 ID',
            icon: Icons.info_outline_rounded,
            value: device.id,
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, SmartPlanterDevice device) async {
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
        ),
        actions: <Widget>[
          AppTextButton(
            label: '取消',
            onPressed: () => Navigator.pop(dialogContext),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !context.mounted) return;
    final result = await FlowerpotScope.of(
      context,
    ).renameDevice(device.id, name);
    if (context.mounted) {
      showAppMessage(
        context,
        result.message,
        tone: result.success ? AppMessageTone.success : AppMessageTone.error,
      );
    }
  }
}
