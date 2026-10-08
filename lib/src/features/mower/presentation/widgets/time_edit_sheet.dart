import 'package:flutter/material.dart';

import '../../mower_ui.dart';
import 'mower_form.dart';

/// 「编辑时段」底部弹层，割草计划的「编辑周X」和花盆行为页的「编辑中午小憩 / 夜间睡眠」共用
/// （2026-10-08 用户：小憩弹框「改成割草计划页面的编辑时间段的那种交互和效果」）。
///
/// 外壳 [TimeEditSheet]、开始 / 结束滚轮 [TimeRangeWheels]、时长条 [TimeDurationBar] 都只有这一份，
/// 两处的样子和手感改这里一起变；各自只往 [TimeEditSheet.child] 里放自己的东西。
Future<T?> showTimeEditSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x471A1F1F),
    builder: builder,
  );
}

/// 弹层外壳：标题 + 副标题、一条分隔线、中间可滚动的内容、底部「取消 / 保存」。
///
/// 「取消」直接关；「保存」调 [onSave]，关不关、带什么回去由调用方决定。
class TimeEditSheet extends StatelessWidget {
  const TimeEditSheet({
    required this.title,
    required this.onSave,
    required this.child,
    super.key,
    this.subtitle = '上下滑动选择小时与分钟',
    this.titleKey,
    this.cancelKey,
    this.saveKey,
  });

  final String title;
  final String subtitle;
  final VoidCallback onSave;
  final Widget child;
  final Key? titleKey;
  final Key? cancelKey;
  final Key? saveKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    key: titleKey,
                    style: const TextStyle(
                      color: MowerColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: MowerColors.inkSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const ColoredBox(
              color: MowerColors.divider,
              child: SizedBox(height: 1, width: double.infinity),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: child,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _SheetButton(
                      label: '取消',
                      buttonKey: cancelKey,
                      background: MowerColors.softFill,
                      foreground: MowerColors.brand,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _SheetButton(
                      label: '保存',
                      buttonKey: saveKey,
                      background: MowerColors.brand,
                      foreground: Colors.white,
                      onTap: onSave,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 开始 / 结束两组「小时 : 分钟」滚轮。
///
/// ⚠️ **分钟是 1 分一格，稿子上画的是 10 分一格**——稿子自己的图表里有 16:23 这种时间，
/// 10 分一格根本选不出来。版式一样，只是相邻两行的数字不同。
///
/// 滚轮只在第一次建的时候按 [startMinutes] / [endMinutes] 定位；要换一组数据
/// （割草计划切时段 1 / 2）就换 key 重建。
class TimeRangeWheels extends StatefulWidget {
  const TimeRangeWheels({
    required this.startMinutes,
    required this.endMinutes,
    required this.onStartChanged,
    required this.onEndChanged,
    super.key,
  });

  final int startMinutes;
  final int endMinutes;
  final ValueChanged<int> onStartChanged;
  final ValueChanged<int> onEndChanged;

  @override
  State<TimeRangeWheels> createState() => _TimeRangeWheelsState();
}

class _TimeRangeWheelsState extends State<TimeRangeWheels> {
  static const int _minuteStep = 1;
  static const double _itemExtent = 40;

  late final FixedExtentScrollController _startHour;
  late final FixedExtentScrollController _startMinute;
  late final FixedExtentScrollController _endHour;
  late final FixedExtentScrollController _endMinute;

  @override
  void initState() {
    super.initState();
    _startHour = FixedExtentScrollController(
      initialItem: widget.startMinutes ~/ 60,
    );
    _startMinute = FixedExtentScrollController(
      initialItem: widget.startMinutes % 60 ~/ _minuteStep,
    );
    _endHour = FixedExtentScrollController(
      initialItem: widget.endMinutes ~/ 60,
    );
    _endMinute = FixedExtentScrollController(
      initialItem: widget.endMinutes % 60 ~/ _minuteStep,
    );
  }

  @override
  void dispose() {
    _startHour.dispose();
    _startMinute.dispose();
    _endHour.dispose();
    _endMinute.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            Expanded(
              child: _PickerSide(
                label: '开始时间',
                hourController: _startHour,
                minuteController: _startMinute,
                minutes: widget.startMinutes,
                itemExtent: _itemExtent,
                minuteStep: _minuteStep,
                onChanged: widget.onStartChanged,
              ),
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: MowerColors.divider,
              indent: 8,
              endIndent: 8,
            ),
            Expanded(
              child: _PickerSide(
                label: '结束时间',
                hourController: _endHour,
                minuteController: _endMinute,
                minutes: widget.endMinutes,
                itemExtent: _itemExtent,
                minuteStep: _minuteStep,
                onChanged: widget.onEndChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 滚轮下面那条时长（稿子 673:7897：36 高）。文案和颜色由调用方给——
/// 割草计划要提示「不足 10 分设备会丢弃」，花盆的夜间睡眠是跨夜的，两边算法不一样。
class TimeDurationBar extends StatelessWidget {
  const TimeDurationBar({
    required this.text,
    super.key,
    this.textKey,
    this.color = MowerColors.brand,
  });

  final String text;
  final Key? textKey;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MowerColors.brand.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        key: textKey,
        style: TextStyle(color: color, fontSize: 15),
      ),
    );
  }
}

class _PickerSide extends StatelessWidget {
  const _PickerSide({
    required this.label,
    required this.hourController,
    required this.minuteController,
    required this.minutes,
    required this.itemExtent,
    required this.minuteStep,
    required this.onChanged,
  });

  final String label;
  final FixedExtentScrollController hourController;
  final FixedExtentScrollController minuteController;
  final int minutes;
  final double itemExtent;
  final int minuteStep;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: MowerColors.inkSecondary,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: <Widget>[
            Expanded(child: _PickerHeader(text: '小时')),
            Expanded(child: _PickerHeader(text: '分钟')),
          ],
        ),
        SizedBox(
          height: itemExtent * 3,
          child: Stack(
            children: <Widget>[
              Center(
                child: Container(
                  height: itemExtent + 6,
                  decoration: BoxDecoration(
                    color: MowerColors.brand.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: MowerWheel(
                      controller: hourController,
                      count: 24,
                      selected: hour,
                      itemExtent: itemExtent,
                      activeFontSize: 24,
                      onSelected: (value) => onChanged(value * 60 + minute),
                    ),
                  ),
                  Expanded(
                    child: MowerWheel(
                      controller: minuteController,
                      count: 60 ~/ minuteStep,
                      selected: minute ~/ minuteStep,
                      itemExtent: itemExtent,
                      activeFontSize: 24,
                      onSelected: (value) =>
                          onChanged(hour * 60 + value * minuteStep),
                    ),
                  ),
                ],
              ),
              const Center(
                child: Text(
                  ':',
                  style: TextStyle(
                    color: MowerColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: MowerColors.inkTertiary, fontSize: 13),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.buttonKey,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        key: buttonKey,
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }
}
