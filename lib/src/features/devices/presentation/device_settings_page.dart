import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';

class DeviceSettingsPage extends StatefulWidget {
  const DeviceSettingsPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  double? soundDraft;
  double? touchDraft;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final device = state.deviceById(widget.deviceId);
    if (device == null) {
      return const Scaffold(body: Center(child: Text('设备不存在或已解绑')));
    }
    final settings = device.settings;
    soundDraft ??= settings.soundSensitivity.toDouble();
    touchDraft ??= settings.touchSensitivity.toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('设备设置')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            children: <Widget>[
              SettingGroup(
                title: '设备',
                children: <Widget>[
                  SettingTile(
                    icon: Icons.eco_outlined,
                    title: device.name,
                    subtitle:
                        '${device.plant.name} · 已陪伴 ${device.companionDays} 天',
                    onTap: () => _rename(context, device),
                  ),
                  SettingTile(
                    icon: Icons.local_florist_outlined,
                    title: '选择植物',
                    subtitle: device.plant.name,
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.plantPicker,
                      arguments: device.id,
                    ),
                  ),
                  SettingTile(
                    icon: Icons.memory_rounded,
                    title: '设备详细信息',
                    subtitle: '固件、MAC、设备 ID',
                    onTap: () => _deviceInfo(context, device),
                  ),
                  SettingTile(
                    icon: Icons.system_update_alt_rounded,
                    title: '固件版本 OTA',
                    subtitle: '当前 ${device.firmwareVersion}',
                    onTap: () => _firmware(context, device),
                  ),
                  SettingTile(
                    icon: Icons.share_outlined,
                    title: '分享设备',
                    subtitle: '生成链接，无需重新配网',
                    onTap: () => _share(context, device.id),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingGroup(
                title: '显示',
                children: <Widget>[
                  SettingTile(
                    icon: Icons.brightness_6_outlined,
                    title: '自动屏幕亮度',
                    trailing: Switch(
                      value: settings.autoBrightness,
                      onChanged: (value) =>
                          _setting(context, 'autoBrightness', value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingGroup(
                title: '听觉感知',
                children: <Widget>[
                  SettingTile(
                    icon: Icons.hearing_rounded,
                    title: '声音互动',
                    trailing: Switch(
                      value: settings.soundInteraction,
                      onChanged: (value) =>
                          _setting(context, 'soundInteraction', value),
                    ),
                  ),
                  _SliderSetting(
                    title: '声音灵敏度',
                    value: soundDraft!,
                    onChanged: (value) => setState(() => soundDraft = value),
                    onChangeEnd: (value) =>
                        _setting(context, 'soundSensitivity', value.round()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingGroup(
                title: '触觉感知',
                children: <Widget>[
                  SettingTile(
                    icon: Icons.touch_app_outlined,
                    title: '触摸交互',
                    trailing: Switch(
                      value: settings.touchInteraction,
                      onChanged: (value) =>
                          _setting(context, 'touchInteraction', value),
                    ),
                  ),
                  _SliderSetting(
                    title: '触摸灵敏度',
                    value: touchDraft!,
                    onChanged: (value) => setState(() => touchDraft = value),
                    onChangeEnd: (value) =>
                        _setting(context, 'touchSensitivity', value.round()),
                  ),
                  SettingTile(
                    icon: Icons.vibration_rounded,
                    title: '振动反馈',
                    trailing: Switch(
                      value: settings.vibration,
                      onChanged: (value) =>
                          _setting(context, 'vibration', value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingGroup(
                title: '行为',
                children: <Widget>[
                  SettingTile(
                    icon: Icons.bedtime_outlined,
                    title: '中午小憩',
                    subtitle: settings.napPeriod,
                    trailing: Switch(
                      value: settings.napEnabled,
                      onChanged: (value) =>
                          _setting(context, 'napEnabled', value),
                    ),
                    onTap: () => _period(
                      context,
                      '中午小憩',
                      settings.napPeriod,
                      'napPeriod',
                    ),
                  ),
                  SettingTile(
                    icon: Icons.nightlight_outlined,
                    title: '夜间睡眠',
                    subtitle: settings.nightPeriod,
                    trailing: Switch(
                      value: settings.nightEnabled,
                      onChanged: (value) =>
                          _setting(context, 'nightEnabled', value),
                    ),
                    onTap: () => _period(
                      context,
                      '夜间睡眠',
                      settings.nightPeriod,
                      'nightPeriod',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingGroup(
                title: '本地化',
                children: <Widget>[
                  SettingTile(
                    icon: Icons.location_on_outlined,
                    title: '位置与天气服务',
                    trailing: Switch(
                      value: settings.weatherService,
                      onChanged: (value) =>
                          _setting(context, 'weatherService', value),
                    ),
                  ),
                  SettingTile(
                    icon: Icons.my_location_rounded,
                    title: '重置位置',
                    subtitle: '重新获取当前位置与天气',
                    onTap: () => showAppMessage(context, '位置与天气已更新'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingGroup(
                title: '其他设置',
                children: <Widget>[
                  SettingTile(
                    icon: Icons.thermostat_rounded,
                    title: '温度单位',
                    trailing: SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment(value: 'celsius', label: Text('°C')),
                        ButtonSegment(value: 'fahrenheit', label: Text('°F')),
                      ],
                      selected: <String>{settings.temperatureUnit},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) =>
                          _setting(context, 'temperatureUnit', value.first),
                    ),
                  ),
                  SettingTile(
                    icon: Icons.schedule_rounded,
                    title: '时钟模式',
                    trailing: SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment(value: '24h', label: Text('24h')),
                        ButtonSegment(value: '12h', label: Text('12h')),
                      ],
                      selected: <String>{settings.clockFormat},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) =>
                          _setting(context, 'clockFormat', value.first),
                    ),
                  ),
                  SettingTile(
                    icon: Icons.straighten_rounded,
                    title: '水位传感器校准',
                    onTap: () => _maintenance(context, 'calibrateWaterLevel'),
                  ),
                  SettingTile(
                    icon: Icons.build_circle_outlined,
                    title: '修复系统文件',
                    onTap: () => _maintenance(context, 'repairSystem'),
                  ),
                  SettingTile(
                    icon: Icons.router_outlined,
                    title: '重新配网',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.pairing),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingGroup(
                children: <Widget>[
                  SettingTile(
                    icon: Icons.link_off_rounded,
                    title: '解绑设备',
                    danger: true,
                    onTap: () => _remove(context, device, reset: false),
                  ),
                  SettingTile(
                    icon: Icons.restore_rounded,
                    title: '恢复出厂设置',
                    subtitle: '解绑并清除设备数据',
                    danger: true,
                    onTap: () => _remove(context, device, reset: true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setting(BuildContext context, String key, Object value) async {
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, key, value);
    if (context.mounted && !result.success) {
      showAppMessage(context, result.message, success: false);
    }
  }

  Future<void> _rename(BuildContext context, SmartPlanterDevice device) async {
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
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
      showAppMessage(context, result.message, success: result.success);
    }
  }

  void _deviceInfo(BuildContext context, SmartPlanterDevice device) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('设备详细信息', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 18),
            _InfoRow('设备 ID', device.id),
            _InfoRow('产品 PID', device.productId),
            _InfoRow('MAC 地址', device.macAddress),
            _InfoRow('固件版本', device.firmwareVersion),
            _InfoRow('信号强度', '${device.signal}%'),
          ],
        ),
      ),
    );
  }

  Future<void> _firmware(
    BuildContext context,
    SmartPlanterDevice device,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final version = await FlowerpotScope.of(context).checkFirmware(device.id);
    if (!context.mounted) return;
    Navigator.pop(context);
    if (version == null || version == device.firmwareVersion) {
      showAppMessage(context, '当前已是最新版本');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现新固件'),
        content: Text('${device.firmwareVersion} → $version\n升级期间请保持设备充电并在线。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始升级'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final result = await FlowerpotScope.of(
      context,
    ).upgradeFirmware(device.id, version);
    if (context.mounted) {
      showAppMessage(context, result.message, success: result.success);
    }
  }

  Future<void> _share(BuildContext context, String id) async {
    final result = await FlowerpotScope.of(context).createShareLink(id);
    if (!context.mounted) return;
    if (!result.success) {
      showAppMessage(context, result.message, success: false);
      return;
    }
    await Clipboard.setData(ClipboardData(text: result.message));
    if (context.mounted) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('分享链接已生成'),
          content: SelectableText(
            '${result.message}\n\n链接已复制。被分享用户登录后可查看设备，无需重新配网。',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _period(
    BuildContext context,
    String title,
    String current,
    String key,
  ) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title时间段'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '例如 12:30-13:30'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && context.mounted) {
      await _setting(context, key, value);
    }
  }

  Future<void> _maintenance(BuildContext context, String action) async {
    final result = await FlowerpotScope.of(
      context,
    ).runMaintenance(widget.deviceId, action);
    if (context.mounted) {
      showAppMessage(context, result.message, success: result.success);
    }
  }

  Future<void> _remove(
    BuildContext context,
    SmartPlanterDevice device, {
    required bool reset,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
        title: Text(reset ? '恢复出厂设置？' : '解绑设备？'),
        content: Text(
          reset ? '设备数据和用户关系都会被清除，设备将重新进入配网模式。' : '设备会从当前账号移除，但保留设备本地数据。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await FlowerpotScope.of(
      context,
    ).removeDevice(device.id, resetFactory: reset);
    if (!context.mounted) return;
    showAppMessage(context, result.message, success: result.success);
    if (result.success) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.shell, (_) => false);
    }
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String title;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
    child: Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${value.round()}%',
              style: const TextStyle(
                color: AppColors.leaf,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 100,
          divisions: 20,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: <Widget>[
        SizedBox(width: 86, child: Text(label)),
        Expanded(
          child: SelectableText(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
