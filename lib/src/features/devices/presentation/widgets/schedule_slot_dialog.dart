import 'package:flutter/material.dart';

import '../../../mower/presentation/widgets/time_edit_sheet.dart';

/// One edited time slot, in minutes past midnight.
class ScheduleSlot {
  const ScheduleSlot({required this.startMinutes, required this.endMinutes});

  final int startMinutes;
  final int endMinutes;

  /// 结束早于开始 = 跨夜（夜间睡眠就是这样），时长要绕过午夜算。
  int get durationMinutes => endMinutes > startMinutes
      ? endMinutes - startMinutes
      : ScheduleSlotDialog.minutesInDay - startMinutes + endMinutes;

  String get startLabel => ScheduleSlotDialog.clockLabel(startMinutes);
  String get endLabel => ScheduleSlotDialog.clockLabel(endMinutes);

  /// `HH:MM-HH:MM`，直接可以交给 `TuyaConfig.settingDps` 写回 DP。
  String get period => '$startLabel-$endLabel';
}

/// 行为页的时段编辑弹层（「编辑中午小憩」「编辑夜间睡眠」）。
///
/// **交互和样子照割草计划的「编辑周X」**（2026-10-08 用户：「编辑中午小憩弹出框改成割草计划
/// 页面的编辑时间段的那种交互和效果，同时可以滚动选择小时和分钟」）：从底部弹出，开始 / 结束
/// 各一组「小时 : 分钟」滚轮、1 分钟一格，下面实时显示时长，按「保存」才回传——滚动过程中不发 DP。
/// 外壳、滚轮、时长条直接用割草计划那一份（`time_edit_sheet.dart`），不另写；两个时段走的是
/// 这同一个弹层，所以夜间睡眠也跟着换了。
///
/// 原来是居中弹窗 + 两根 5 分钟一档的滑条（`编辑周四时段2.png` 的版式）。割草计划弹层里的
/// 「启用时段 / 修边 / 复制整周」花盆没有（开关在页面卡片上），这里只放时间。
Future<ScheduleSlot?> showScheduleSlotDialog(
  BuildContext context, {
  required String title,
  required ScheduleSlot initial,
}) {
  return showTimeEditSheet<ScheduleSlot>(
    context,
    builder: (_) => ScheduleSlotDialog(title: title, initial: initial),
  );
}

class ScheduleSlotDialog extends StatefulWidget {
  const ScheduleSlotDialog({
    required this.title,
    required this.initial,
    super.key,
  });

  static const int minutesInDay = 24 * 60;

  final String title;
  final ScheduleSlot initial;

  static String clockLabel(int minutes) {
    final wrapped = minutes % minutesInDay;
    final hour = (wrapped ~/ 60).toString().padLeft(2, '0');
    final minute = (wrapped % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  State<ScheduleSlotDialog> createState() => _ScheduleSlotDialogState();
}

class _ScheduleSlotDialogState extends State<ScheduleSlotDialog> {
  // 滚轮只有 00:00–23:59，进来先归到一天之内。
  late int _start =
      widget.initial.startMinutes % ScheduleSlotDialog.minutesInDay;
  late int _end = widget.initial.endMinutes % ScheduleSlotDialog.minutesInDay;

  ScheduleSlot get _slot => ScheduleSlot(startMinutes: _start, endMinutes: _end);

  @override
  Widget build(BuildContext context) {
    final duration = _slot.durationMinutes;
    return TimeEditSheet(
      key: const Key('schedule-slot-dialog'),
      title: widget.title,
      cancelKey: const Key('schedule-slot-cancel'),
      saveKey: const Key('schedule-slot-save'),
      onSave: () => Navigator.of(context).pop(_slot),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TimeRangeWheels(
            startMinutes: _start,
            endMinutes: _end,
            onStartChanged: (value) => setState(() => _start = value),
            onEndChanged: (value) => setState(() => _end = value),
          ),
          const SizedBox(height: 14),
          // 结束早于开始按跨夜算（夜间睡眠 22:00–07:30 就是这样），不当成拨错。
          TimeDurationBar(
            text: '时长 ${duration ~/ 60} 小时 ${duration % 60} 分',
            textKey: const Key('schedule-slot-duration'),
          ),
        ],
      ),
    );
  }
}
