import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 启动类动作每次确认，不持久化或缓存用户的确认结果。
Future<bool> showMowerSafetyDialog(BuildContext context) async {
  final confirmed = await showAppDialog(
    context,
    title: '启动安全提醒',
    message:
        '请确保您已站在割草机旁边，且设备周围 10 米内没有儿童、宠物或障碍物。\n'
        '启动后刀盘将高速旋转，请勿靠近。',
    icon: Icons.warning_amber_rounded,
    confirmLabel: '我已确认，周围安全',
    stackActions: true,
  );
  return confirmed == true;
}

/// DP119 只接受整小时；向下取整保证作业不超过当天 18:00。
int mowerStartMaxHours(DateTime now) {
  final deadline = DateTime(now.year, now.month, now.day, 18);
  return deadline.difference(now).inHours.clamp(0, 24);
}

bool mowerStartHoursValid(DateTime now, int hours) =>
    hours >= 1 && hours <= mowerStartMaxHours(now);

String mowerStartUnavailableMessage(DateTime now) => now.hour >= 18
    ? '今天的割草时间已结束（18:00），请明天再启动割草机。'
    : '距离今天18:00已不足1小时，无法设置完整的割草时长，请明天再启动。';

Future<int?> showMowerDurationDialog(BuildContext context, int maxHours) async {
  if (maxHours <= 0) {
    await showAppNoticeDialog(
      context,
      title: '暂时无法启动',
      message: '可设置的割草时长必须大于0小时，请明天再启动。',
      icon: Icons.schedule_rounded,
    );
    return null;
  }
  if (maxHours > 24) throw RangeError.range(maxHours, 1, 24, 'maxHours');
  var hours = maxHours;
  final confirmed = await showAppDialog(
    context,
    title: '割草时间设置',
    message: '距离今天18:00最多可割草 $maxHours 小时，仅可缩短时长。',
    icon: Icons.schedule_rounded,
    confirmLabel: '确认启动',
    stackActions: true,
    content: StatefulBuilder(
      builder: (context, setState) => DropdownButtonFormField<int>(
        key: const Key('mower-start-hours'),
        initialValue: maxHours,
        decoration: const InputDecoration(labelText: '割草时长（小时）'),
        items: <DropdownMenuItem<int>>[
          for (var value = 1; value <= maxHours; value++)
            DropdownMenuItem(value: value, child: Text('$value 小时')),
        ],
        onChanged: (value) {
          if (value != null) setState(() => hours = value);
        },
      ),
    ),
  );
  return confirmed == true ? hours : null;
}
