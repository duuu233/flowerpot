import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../../tuya/tuya_models.dart';
import '../../models/device_settings_page_model.dart';

class DeviceSettingsControlSheet extends StatefulWidget {
  const DeviceSettingsControlSheet({
    required this.kind,
    required this.settings,
    required this.onSettingChanged,
    required this.onPairing,
    required this.onMaintenance,
    super.key,
  });

  final DeviceSettingsMenuKind kind;
  final DeviceControlSettings settings;
  final Future<void> Function(String key, Object value) onSettingChanged;
  final VoidCallback onPairing;
  final ValueChanged<String> onMaintenance;

  @override
  State<DeviceSettingsControlSheet> createState() =>
      _DeviceSettingsControlSheetState();
}

class _DeviceSettingsControlSheetState
    extends State<DeviceSettingsControlSheet> {
  late bool autoBrightness;
  late bool soundInteraction;
  late bool touchInteraction;
  late bool vibration;
  late bool napEnabled;
  late bool nightEnabled;
  late bool weatherService;
  late double soundSensitivity;
  late double touchSensitivity;
  late String temperatureUnit;
  late String clockFormat;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    autoBrightness = settings.autoBrightness;
    soundInteraction = settings.soundInteraction;
    touchInteraction = settings.touchInteraction;
    vibration = settings.vibration;
    napEnabled = settings.napEnabled;
    nightEnabled = settings.nightEnabled;
    weatherService = settings.weatherService;
    soundSensitivity = settings.soundSensitivity.toDouble();
    touchSensitivity = settings.touchSensitivity.toDouble();
    temperatureUnit = settings.temperatureUnit;
    clockFormat = settings.clockFormat;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AppSettingsList(
        showDividers: false,
        showShadow: false,
        children: _children(),
      ),
    );
  }

  List<Widget> _children() => switch (widget.kind) {
    DeviceSettingsMenuKind.display => <Widget>[
      ToggleSettingsTile(
        title: '自动调节亮度',
        icon: Icons.light_mode_outlined,
        value: autoBrightness,
        onChanged: (value) => _setBool(
          key: 'autoBrightness',
          value: value,
          apply: () => autoBrightness = value,
        ),
      ),
    ],
    DeviceSettingsMenuKind.hearing => <Widget>[
      ToggleSettingsTile(
        title: '声音互动',
        icon: Icons.hearing_rounded,
        value: soundInteraction,
        onChanged: (value) => _setBool(
          key: 'soundInteraction',
          value: value,
          apply: () => soundInteraction = value,
        ),
      ),
      _SensitivityControl(
        title: '声音灵敏度',
        value: soundSensitivity,
        onChanged: (value) => setState(() => soundSensitivity = value),
        onChangeEnd: (value) =>
            widget.onSettingChanged('soundSensitivity', value.round()),
      ),
    ],
    DeviceSettingsMenuKind.touch => <Widget>[
      ToggleSettingsTile(
        title: '触摸互动',
        icon: Icons.touch_app_outlined,
        value: touchInteraction,
        onChanged: (value) => _setBool(
          key: 'touchInteraction',
          value: value,
          apply: () => touchInteraction = value,
        ),
      ),
      _SensitivityControl(
        title: '触摸灵敏度',
        value: touchSensitivity,
        onChanged: (value) => setState(() => touchSensitivity = value),
        onChangeEnd: (value) =>
            widget.onSettingChanged('touchSensitivity', value.round()),
      ),
    ],
    DeviceSettingsMenuKind.vibration => <Widget>[
      ToggleSettingsTile(
        title: '振动反馈',
        icon: Icons.vibration_rounded,
        value: vibration,
        onChanged: (value) => _setBool(
          key: 'vibration',
          value: value,
          apply: () => vibration = value,
        ),
      ),
    ],
    DeviceSettingsMenuKind.behavior => <Widget>[
      ToggleSettingsTile(
        title: '中午小憩',
        subtitle: widget.settings.napPeriod,
        icon: Icons.bedtime_outlined,
        value: napEnabled,
        onChanged: (value) => _setBool(
          key: 'napEnabled',
          value: value,
          apply: () => napEnabled = value,
        ),
      ),
      ToggleSettingsTile(
        title: '夜间睡眠',
        subtitle: widget.settings.nightPeriod,
        icon: Icons.nightlight_outlined,
        value: nightEnabled,
        onChanged: (value) => _setBool(
          key: 'nightEnabled',
          value: value,
          apply: () => nightEnabled = value,
        ),
      ),
    ],
    DeviceSettingsMenuKind.other => <Widget>[
      ToggleSettingsTile(
        title: '位置与天气服务',
        icon: Icons.location_on_outlined,
        value: weatherService,
        onChanged: (value) => _setBool(
          key: 'weatherService',
          value: value,
          apply: () => weatherService = value,
        ),
      ),
      AppSettingsTile(
        title: '温度单位',
        icon: Icons.thermostat_rounded,
        value: temperatureUnit == 'celsius' ? '°C' : '°F',
        onTap: _toggleTemperatureUnit,
      ),
      AppSettingsTile(
        title: '时钟模式',
        icon: Icons.schedule_rounded,
        value: clockFormat,
        onTap: _toggleClockFormat,
      ),
      AppSettingsTile(
        title: '水位传感器校准',
        icon: Icons.straighten_rounded,
        onTap: () => widget.onMaintenance('calibrateWaterLevel'),
      ),
      AppSettingsTile(
        title: '重新配网',
        icon: Icons.router_outlined,
        onTap: widget.onPairing,
      ),
    ],
    DeviceSettingsMenuKind.plant => const <Widget>[],
  };

  Future<void> _setBool({
    required String key,
    required bool value,
    required VoidCallback apply,
  }) async {
    setState(apply);
    await widget.onSettingChanged(key, value);
  }

  Future<void> _toggleTemperatureUnit() async {
    final value = temperatureUnit == 'celsius' ? 'fahrenheit' : 'celsius';
    setState(() => temperatureUnit = value);
    await widget.onSettingChanged('temperatureUnit', value);
  }

  Future<void> _toggleClockFormat() async {
    final value = clockFormat == '24h' ? '12h' : '24h';
    setState(() => clockFormat = value);
    await widget.onSettingChanged('clockFormat', value);
  }
}

class _SensitivityControl extends StatelessWidget {
  const _SensitivityControl({
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title)),
              Text(
                '${value.round()}%',
                style: const TextStyle(color: AppColors.brandPrimary),
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
}
