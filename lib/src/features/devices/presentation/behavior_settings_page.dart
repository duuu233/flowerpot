import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/behavior_settings_page_model.dart';
import 'widgets/behavior_schedule_card.dart';

typedef BehaviorTimePicker =
    Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initialTime);

class BehaviorSettingsPage extends StatefulWidget {
  const BehaviorSettingsPage({
    required this.deviceId,
    super.key,
    this.timePicker,
  });

  final String deviceId;
  final BehaviorTimePicker? timePicker;

  @override
  State<BehaviorSettingsPage> createState() => _BehaviorSettingsPageState();
}

class _BehaviorSettingsPageState extends State<BehaviorSettingsPage> {
  final Set<BehaviorScheduleKind> updating = <BehaviorScheduleKind>{};

  Future<void> _setEnabled(BehaviorScheduleKind kind, bool value) async {
    final key = switch (kind) {
      BehaviorScheduleKind.nap => 'napEnabled',
      BehaviorScheduleKind.night => 'nightEnabled',
    };
    await _update(kind, key, value);
  }

  Future<void> _pickTime(
    BehaviorSchedulePageModel schedule, {
    required bool start,
  }) async {
    if (updating.contains(schedule.kind)) return;
    final current = start ? schedule.start : schedule.end;
    final initial = TimeOfDay(hour: current.hour, minute: current.minute);
    final picked = await (widget.timePicker ?? _showTimePicker)(
      context,
      initial,
    );
    if (!mounted || picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    final period = start
        ? '$value-${schedule.end.label}'
        : '${schedule.start.label}-$value';
    final key = switch (schedule.kind) {
      BehaviorScheduleKind.nap => 'napPeriod',
      BehaviorScheduleKind.night => 'nightPeriod',
    };
    await _update(schedule.kind, key, period);
  }

  Future<TimeOfDay?> _showTimePicker(
    BuildContext context,
    TimeOfDay initialTime,
  ) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
  }

  Future<void> _update(
    BehaviorScheduleKind kind,
    String key,
    Object value,
  ) async {
    if (updating.contains(kind)) return;
    setState(() => updating.add(kind));
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, key, value);
    if (!mounted) return;
    setState(() => updating.remove(kind));
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(widget.deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '行为', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final model = BehaviorSettingsPageModel.fromSettings(device.settings);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '行为', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('behavior-settings-scroll-view'),
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            37,
            AppSpacing.pageMargin,
            40,
          ),
          child: Column(
            children: <Widget>[
              BehaviorScheduleCard(
                model: model.nap,
                switchKey: const Key('nap-switch'),
                startTimeKey: const Key('nap-start-time'),
                endTimeKey: const Key('nap-end-time'),
                updating: updating.contains(BehaviorScheduleKind.nap),
                onEnabledChanged: (value) =>
                    _setEnabled(BehaviorScheduleKind.nap, value),
                onStartTimeTap: () => _pickTime(model.nap, start: true),
                onEndTimeTap: () => _pickTime(model.nap, start: false),
              ),
              const SizedBox(height: 12),
              BehaviorScheduleCard(
                model: model.night,
                switchKey: const Key('night-switch'),
                startTimeKey: const Key('night-start-time'),
                endTimeKey: const Key('night-end-time'),
                updating: updating.contains(BehaviorScheduleKind.night),
                onEnabledChanged: (value) =>
                    _setEnabled(BehaviorScheduleKind.night, value),
                onStartTimeTap: () => _pickTime(model.night, start: true),
                onEndTimeTap: () => _pickTime(model.night, start: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
