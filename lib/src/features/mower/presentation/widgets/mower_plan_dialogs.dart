import 'package:flutter/material.dart';

import '../../mower_demo.dart';

/// 「时间段重叠」提示（`割草机-割草计划-时间段重复.png`）。
///
/// 只有一颗「返回修改」——这不是一个可以"确认继续"的状态，保存下去设备会拿到两段
/// 打架的计划。返回 true 表示用户要回去改，由调用方把编辑弹窗原样开回来。
Future<bool?> showMowerOverlapDialog(
  BuildContext context, {
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0x471A1F1F),
    builder: (context) => _MowerCenterDialog(
      dialogKey: const Key('mower-plan-overlap-dialog'),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: MowerColors.chipFill,
        ),
        child: const Text(
          '!',
          style: TextStyle(
            color: MowerColors.brand,
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: '时间段重叠',
      message: '$message\n请调整后再保存',
      actions: <Widget>[
        Expanded(
          child: _DialogButton(
            label: '返回修改',
            buttonKey: const Key('mower-plan-overlap-back'),
            background: MowerColors.brand,
            foreground: Colors.white,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    ),
  );
}

/// 「恢复默认计划？」（`割草机-割草计划-时间段重复-1.png`）。返回 true 表示恢复。
Future<bool?> showMowerRestoreDefaultDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0x471A1F1F),
    builder: (context) => _MowerCenterDialog(
      dialogKey: const Key('mower-plan-restore-dialog'),
      icon: const Icon(
        Icons.history_rounded,
        size: 46,
        color: MowerColors.brand,
      ),
      title: '恢复默认计划？',
      message: '当前自定义时段将被清除，\n并恢复为系统推荐计划。',
      actions: <Widget>[
        Expanded(
          child: _DialogButton(
            label: '取消',
            buttonKey: const Key('mower-plan-restore-cancel'),
            background: MowerColors.softFill,
            foreground: MowerColors.brand,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _DialogButton(
            label: '恢复计划',
            buttonKey: const Key('mower-plan-restore-confirm'),
            background: MowerColors.brand,
            foreground: Colors.white,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    ),
  );
}

/// 两张弹窗的公共外壳：圆角 24 的白卡，图标、标题、说明、按钮一列排下来。
class _MowerCenterDialog extends StatelessWidget {
  const _MowerCenterDialog({
    required this.dialogKey,
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
  });

  final Key dialogKey;
  final Widget icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: dialogKey,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            icon,
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MowerColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MowerColors.inkSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 20),
            Row(children: actions),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    required this.buttonKey,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  final Key buttonKey;

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
