import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/led_settings_page_model.dart';
import 'widgets/device_toggle_settings_card.dart';
import 'widgets/setting_orbit_illustration.dart';

/// LED 设置：一张卡、一个开关，版式照搬 `docs/UI/震动设置.png`。
///
/// 背后的功能点见 [LedSettingsPageModel]。
class LedSettingsPage extends StatefulWidget {
  const LedSettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<LedSettingsPage> createState() => _LedSettingsPageState();
}

class _LedSettingsPageState extends State<LedSettingsPage> {
  bool updating = false;

  Future<void> _setLed(bool value) async {
    if (updating) return;
    setState(() => updating = true);
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, 'led', value);
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
        appBar: const AppPageHeader(title: 'LED设置', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final model = LedSettingsPageModel.fromSettings(device.settings);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: 'LED设置', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('led-settings-scroll-view'),
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
                // 原来和「显示」共用 brightness_symbol，两页并排是同一张图。
                symbol: DeviceSettingSymbol.led,
                title: '启用LED',
                status: model.status,
                description: model.description,
                descriptionLines: model.descriptionLines,
                value: model.ledEnabled,
                switchKey: const Key('led-switch'),
                updating: updating,
                onChanged: _setLed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
