import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

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

/// 时段编辑弹窗（`docs/UI/v2/智能花盆ysplanter/编辑周四时段2.png`）。
///
/// 两根滑条一次改完开始和结束，中间实时显示时长——之前是两个各自独立的系统
/// 时间选择器，改完才知道自己排了个 20 分钟或者跨了午夜的时段。
///
/// [onDelete] 有值时右上角出现删除按钮，[conflictHint] 有值时在按钮上方显示一行
/// 提示（frame 里的「时段 1: 09:00–11:30」）。花盆的中午小憩和夜间睡眠都删不掉，
/// 也没有第二个时段，所以两个都不传。
Future<ScheduleSlot?> showScheduleSlotDialog(
  BuildContext context, {
  required String title,
  required ScheduleSlot initial,
  String subtitle = '修改时间，或调整时段长度',
  String? conflictHint,
  VoidCallback? onDelete,
}) {
  return showDialog<ScheduleSlot>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .4),
    builder: (_) => ScheduleSlotDialog(
      title: title,
      subtitle: subtitle,
      initial: initial,
      conflictHint: conflictHint,
      onDelete: onDelete,
    ),
  );
}

class ScheduleSlotDialog extends StatefulWidget {
  const ScheduleSlotDialog({
    required this.title,
    required this.initial,
    super.key,
    this.subtitle = '修改时间，或调整时段长度',
    this.conflictHint,
    this.onDelete,
  });

  static const int minutesInDay = 24 * 60;

  /// 滑条的步长。设备侧的功能点是按分钟的，但 1440 个刻度在手机上根本拖不准，
  /// 5 分钟一档既够用又拖得住。
  static const int stepMinutes = 5;

  final String title;
  final String subtitle;
  final ScheduleSlot initial;
  final String? conflictHint;
  final VoidCallback? onDelete;

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
  late int _start = _snap(widget.initial.startMinutes);
  late int _end = _snap(widget.initial.endMinutes);

  static int _snap(int minutes) {
    final step = ScheduleSlotDialog.stepMinutes;
    final snapped = (minutes / step).round() * step;
    return snapped.clamp(0, ScheduleSlotDialog.minutesInDay - step);
  }

  ScheduleSlot get _slot => ScheduleSlot(startMinutes: _start, endMinutes: _end);

  @override
  Widget build(BuildContext context) {
    final duration = _slot.durationMinutes;
    final delete = widget.onDelete;
    return Dialog(
      key: const Key('schedule-slot-dialog'),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (delete != null)
                  Material(
                    color: AppColors.dangerSurface,
                    borderRadius: AppRadius.card,
                    child: InkWell(
                      key: const Key('schedule-slot-delete'),
                      borderRadius: AppRadius.card,
                      onTap: () {
                        Navigator.of(context).pop();
                        delete();
                      },
                      child: const SizedBox.square(
                        dimension: 44,
                        child: Icon(
                          Icons.delete_outline,
                          color: AppColors.danger,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _TimeSlider(
              sliderKey: const Key('schedule-slot-start'),
              label: '开始时间',
              minutes: _start,
              onChanged: (value) => setState(() => _start = value),
            ),
            const SizedBox(height: 12),
            _TimeSlider(
              sliderKey: const Key('schedule-slot-end'),
              label: '结束时间',
              minutes: _end,
              onChanged: (value) => setState(() => _end = value),
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.brandSurface,
                borderRadius: AppRadius.card,
              ),
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(
                    '时长 ${duration ~/ 60} 小时 ${duration % 60} 分',
                    key: const Key('schedule-slot-duration'),
                    style: const TextStyle(
                      color: AppColors.brandDark,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.conflictHint case final String hint) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppDialogButton(
                    key: const Key('schedule-slot-cancel'),
                    label: '取消',
                    textColor: AppColors.brandDark,
                    background: AppColors.brandSurface,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDialogButton(
                    key: const Key('schedule-slot-save'),
                    label: '保存',
                    textColor: AppColors.surface,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        AppColors.brandPrimary,
                        AppColors.brandDark,
                      ],
                    ),
                    onTap: () => Navigator.of(context).pop(_slot),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeSlider extends StatelessWidget {
  const _TimeSlider({
    required this.sliderKey,
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final Key sliderKey;
  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const max = ScheduleSlotDialog.minutesInDay - ScheduleSlotDialog.stepMinutes;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  ScheduleSlotDialog.clockLabel(minutes),
                  style: const TextStyle(
                    color: AppColors.brandDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Slider(
              key: sliderKey,
              value: minutes.toDouble(),
              max: max.toDouble(),
              divisions: max ~/ ScheduleSlotDialog.stepMinutes,
              label: ScheduleSlotDialog.clockLabel(minutes),
              onChanged: (value) => onChanged(value.round()),
            ),
          ],
        ),
      ),
    );
  }
}
