import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/behavior_settings_page_model.dart';
import 'widgets/behavior_schedule_card.dart';
import 'widgets/schedule_slot_dialog.dart';

/// 打开时段编辑弹窗。测试注入自己的实现来跳过真正的弹窗。
typedef BehaviorSlotEditor =
    Future<ScheduleSlot?> Function(
      BuildContext context,
      String title,
      ScheduleSlot initial,
    );

class BehaviorSettingsPage extends StatefulWidget {
  const BehaviorSettingsPage({
    required this.deviceId,
    super.key,
    this.slotEditor,
  });

  final String deviceId;

  /// 注入点，默认是 [showScheduleSlotDialog]。
  final BehaviorSlotEditor? slotEditor;

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

  /// 开始和结束在同一个弹窗里改（`编辑周四时段2` 的版式）。
  ///
  /// [start] 只决定弹窗里哪一根滑条更值得先看，两端都能改：分成两个系统时间
  /// 选择器时，用户改完开始才发现时段只剩十分钟，或者不小心跨了午夜。
  Future<void> _editSlot(
    BehaviorSchedulePageModel schedule, {
    required bool start,
  }) async {
    if (updating.contains(schedule.kind)) return;
    final editor = widget.slotEditor ?? _showSlotDialog;
    final edited = await editor(
      context,
      '编辑${schedule.title}',
      ScheduleSlot(
        startMinutes: schedule.start.totalMinutes,
        endMinutes: schedule.end.totalMinutes,
      ),
    );
    if (!mounted || edited == null) return;
    final key = switch (schedule.kind) {
      BehaviorScheduleKind.nap => 'napPeriod',
      BehaviorScheduleKind.night => 'nightPeriod',
    };
    await _update(schedule.kind, key, edited.period);
  }

  Future<ScheduleSlot?> _showSlotDialog(
    BuildContext context,
    String title,
    ScheduleSlot initial,
  ) {
    // 花盆的两个时段都删不掉，也没有第二个时段，所以删除按钮和冲突提示都不传。
    return showScheduleSlotDialog(context, title: title, initial: initial);
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
                onStartTimeTap: () => _editSlot(model.nap, start: true),
                onEndTimeTap: () => _editSlot(model.nap, start: false),
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
                onStartTimeTap: () => _editSlot(model.night, start: true),
                onEndTimeTap: () => _editSlot(model.night, start: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
