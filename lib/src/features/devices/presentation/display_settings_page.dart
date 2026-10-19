import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/display_settings_page_model.dart';
import 'device_online_guard.dart';
import 'widgets/display_settings_card.dart';

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  bool updating = false;
  bool updatingBrightness = false;
  double? pendingBrightness;

  void _previewBrightness(double value) {
    setState(() => pendingBrightness = value);
  }

  /// DP168 手动亮度：松手才下发，0~100。
  Future<void> _setBrightness(double value) async {
    if (updatingBrightness) return;
    final brightness = value.round().clamp(0, 100);
    setState(() {
      updatingBrightness = true;
      pendingBrightness = brightness.toDouble();
    });
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'manualBrightness', brightness);
    if (!mounted) return;
    setState(() {
      updatingBrightness = false;
      pendingBrightness = null;
    });
    if (!result.success) {
      showDeviceActionResult(context, result);
    }
  }

  Future<void> _setAutoBrightness(bool value) async {
    if (updating) return;
    setState(() => updating = true);
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'autoBrightness', value);
    if (!mounted) return;
    setState(() => updating = false);
    if (!result.success) {
      showDeviceActionResult(context, result);
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
      body: DeviceOnlineBody(
        deviceId: widget.deviceId,
        child: SingleChildScrollView(
          key: const Key('display-settings-scroll-view'),
          child: ResponsiveContent(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              27,
              AppSpacing.pageMargin,
              40,
            ),
            child: DisplaySettingsCard(
              model: model,
              brightness:
                  pendingBrightness ?? model.manualBrightness.toDouble(),
              updating: updating,
              updatingBrightness: updatingBrightness,
              onAutoBrightnessChanged: _setAutoBrightness,
              onBrightnessChanged: _previewBrightness,
              onBrightnessChangeEnd: _setBrightness,
            ),
          ),
        ),
      ),
    );
  }
}
