import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'widgets/device_toggle_settings_card.dart';
import 'widgets/setting_orbit_illustration.dart';

/// 自动检测植物：一张卡、一个开关，版式与 `LED设置` 一致。
///
/// 背后是 DP 163 `plant_detect_switch`（平台尚未导出，DP 号是本地占位）。关掉之后
/// 设备报 162 = 1 时首页不再弹「植物确认」。改到独立页面之前它是设置页列表里的一
/// 行开关，和其余「点进去再改」的功能行混在一起。
class PlantDetectionSettingsPage extends StatefulWidget {
  const PlantDetectionSettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<PlantDetectionSettingsPage> createState() =>
      _PlantDetectionSettingsPageState();
}

class _PlantDetectionSettingsPageState
    extends State<PlantDetectionSettingsPage> {
  bool updating = false;

  Future<void> _setEnabled(bool value) async {
    if (updating) return;
    setState(() => updating = true);
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'plantDetection', value);
    if (!mounted) return;
    setState(() => updating = false);
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: AppPageHeader(
          title: l10n.plantDetection,
          leading: const AppBackButton(),
        ),
        body: AppErrorView(
          title: l10n.deviceNotFound,
          message: l10n.deviceNotFoundMessage,
        ),
      );
    }
    final enabled = device.settings.plantDetection;
    final description = l10n.plantDetectionDescription;
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: l10n.plantDetection,
        leading: const AppBackButton(),
      ),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('plant-detection-settings-scroll-view'),
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
              DeviceToggleSettingsCard(
                symbol: DeviceSettingSymbol.plant,
                title: l10n.plantDetectionSwitchTitle,
                status: enabled ? l10n.on : l10n.off,
                description: description,
                descriptionLines: description.split('\n'),
                value: enabled,
                switchKey: const Key('plant-detection-switch'),
                updating: updating,
                onChanged: _setEnabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
