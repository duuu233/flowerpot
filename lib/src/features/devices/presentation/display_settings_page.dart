import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/display_settings_page_model.dart';
import 'widgets/display_settings_card.dart';

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  bool updating = false;

  Future<void> _setAutoBrightness(bool value) async {
    if (updating) return;
    setState(() => updating = true);
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'autoBrightness', value);
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
        appBar: const AppPageHeader(title: '显示', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final model = DisplaySettingsPageModel.fromSettings(device.settings);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '显示', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('display-settings-scroll-view'),
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            37,
            AppSpacing.pageMargin,
            40,
          ),
          child: DisplaySettingsCard(
            model: model,
            updating: updating,
            onAutoBrightnessChanged: _setAutoBrightness,
          ),
        ),
      ),
    );
  }
}
