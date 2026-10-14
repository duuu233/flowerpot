import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/behavior_settings_page_model.dart';
import 'device_online_guard.dart';
import 'widgets/behavior_schedule_card.dart';
import 'widgets/schedule_slot_dialog.dart';
import 'widgets/standby_settings_card.dart';

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

  /// 休眠那张卡自己的在途标记：它和午休 / 夜间不是同一个 DP，互相不该锁住。
  bool _standbyUpdating = false;

  Future<void> _setEnabled(BehaviorScheduleKind kind, bool value) async {
    final key = switch (kind) {
      BehaviorScheduleKind.nap => 'napEnabled',
      BehaviorScheduleKind.night => 'nightEnabled',
    };
    await _update(kind, key, value);
  }

  /// 开始和结束在同一个弹层里改（和割草计划「编辑周X」同一套滚轮，见 [showScheduleSlotDialog]）。
  ///
  /// [start] 只是点的哪一格，弹层里两端都能改：分成两个系统时间选择器时，
  /// 用户改完开始才发现时段只剩十分钟，或者不小心跨了午夜。
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
    return showScheduleSlotDialog(context, title: title, initial: initial);
  }

  /// 开关即时下发（和午休 / 夜间的开关一致，拨完就该看到结果）。
  Future<void> _setStandbyEnabled(bool value) async =>
      _updateStandby('standby', value);

  /// 延迟时间点开弹窗改，滚动过程中不发 DP——每一格发一条只会把指令堆在链路上，
  /// 按弹窗里的「保存」才写一次。
  Future<void> _editStandbyDelay(int current) async {
    if (_standbyUpdating) return;
    final minutes = await showStandbyDelayDialog(
      context,
      initialMinutes: current,
    );
    if (!mounted || minutes == null || minutes == current) return;
    await _updateStandby('standbyDelay', minutes);
  }

  Future<void> _updateStandby(String key, Object value) async {
    if (_standbyUpdating) return;
    setState(() => _standbyUpdating = true);
    final result = await FlowerpotScope.of(
      context,
    ).updateSetting(widget.deviceId, key, value);
    if (!mounted) return;
    setState(() => _standbyUpdating = false);
    if (!result.success) {
      showDeviceActionResult(context, result);
    }
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
      showDeviceActionResult(context, result);
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
      body: DeviceOnlineBody(
        deviceId: widget.deviceId,
        child: SingleChildScrollView(
          key: const Key('behavior-settings-scroll-view'),
          child: ResponsiveContent(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              27,
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
                const SizedBox(height: 12),
                // 休眠是「多久没人理就睡」，和午休 / 夜间这两个时段同属行为，所以
                // 直接摊在这一页上，版式和交互跟着上面两张卡走（DP 151 / 152）。
                StandbySettingsCard(
                  enabled: device.settings.standbyEnabled,
                  delayMinutes: device.settings.standbyDelayMinutes,
                  updating: _standbyUpdating,
                  onEnabledChanged: _setStandbyEnabled,
                  onDelayTap: () =>
                      _editStandbyDelay(device.settings.standbyDelayMinutes),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
