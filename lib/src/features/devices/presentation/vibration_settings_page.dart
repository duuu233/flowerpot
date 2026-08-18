import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/vibration_settings_page_model.dart';
import 'widgets/vibration_settings_card.dart';

class VibrationSettingsPage extends StatefulWidget {
  const VibrationSettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<VibrationSettingsPage> createState() => _VibrationSettingsPageState();
}

class _VibrationSettingsPageState extends State<VibrationSettingsPage> {
  bool updating = false;

  Future<void> _setVibration(bool value) async {
    if (updating) return;
    setState(() => updating = true);
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'vibration', value);
    if (!mounted) return;
    setState(() => updating = false);
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '震动设置', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final model = VibrationSettingsPageModel.fromSettings(device.settings);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '震动设置', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('vibration-settings-scroll-view'),
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            37,
            AppSpacing.pageMargin,
            40,
          ),
          child: VibrationSettingsCard(
            model: model,
            updating: updating,
            onVibrationChanged: _setVibration,
          ),
        ),
      ),
    );
  }
}
