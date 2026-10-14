import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../../shared/l10n/app_l10n.dart';
import '../../../../tuya/tuya_config.dart';
import 'behavior_schedule_card.dart';

/// 「行为」页上的休眠模式：开关（DP 151 `standby_switch`）+ 延迟时间
/// （DP 152 `standby_delay`，1–180 分钟）。
///
/// 版式和交互跟着同一页的午休 / 夜间卡片走：上半是标题、状态和开关，下半是一行
/// 说明加一行可点的取值——点开弹窗改，改完写回。休眠原来是一个二级页面，用户要
/// 多跳一层才能看到「多久没人理就睡」这件事本身，现在直接摊在这一页上。
class StandbySettingsCard extends StatelessWidget {
  const StandbySettingsCard({
    required this.enabled,
    required this.delayMinutes,
    required this.onEnabledChanged,
    required this.onDelayTap,
    super.key,
    this.updating = false,
  });

  final bool enabled;
  final int delayMinutes;
  final ValueChanged<bool>? onEnabledChanged;
  final VoidCallback? onDelayTap;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return AppSurfaceCard(
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      padding: EdgeInsets.zero,
      showShadow: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 76,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.standby,
                          style: AppTypography.sectionTitle.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          enabled ? l10n.on : l10n.off,
                          style: AppTypography.sectionTitle.copyWith(
                            color: AppColors.brandPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: .86,
                    alignment: Alignment.centerRight,
                    child: Switch(
                      key: const Key('standby-switch'),
                      value: enabled,
                      onChanged: updating ? null : onEnabledChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(indent: 22, endIndent: 22),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 19, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.standbyDescription,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                BehaviorTimeRow(
                  key: const Key('standby-delay-row'),
                  label: l10n.standbyDelay,
                  value: standbyDelayLabel(l10n, delayMinutes),
                  onTap: updating ? null : onDelayTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 延迟时间的行内取值：不足一小时就只写分钟，免得「0时30分」这种读着别扭。
String standbyDelayLabel(AppL10n l10n, int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest${l10n.minuteUnit}';
  if (rest == 0) return '$hours${l10n.hourUnit}';
  return '$hours${l10n.hourUnit}$rest${l10n.minuteUnit}';
}

/// 改延迟时间的弹窗，返回分钟数；取消返回 null。
///
/// 和时段编辑（`showScheduleSlotDialog`）同一套操作：点行→弹出→保存，用户
/// 在这一页学到的操作在休眠上照样成立。滚轮沿用原休眠页的两根（时 / 分），滚动
/// 过程中不发 DP，按「保存」才写一次。
Future<int?> showStandbyDelayDialog(
  BuildContext context, {
  required int initialMinutes,
}) {
  return showDialog<int>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .4),
    builder: (_) => _StandbyDelayDialog(initialMinutes: initialMinutes),
  );
}

class _StandbyDelayDialog extends StatefulWidget {
  const _StandbyDelayDialog({required this.initialMinutes});

  final int initialMinutes;

  @override
  State<_StandbyDelayDialog> createState() => _StandbyDelayDialogState();
}

class _StandbyDelayDialogState extends State<_StandbyDelayDialog> {
  /// 滚轮一格的高度，和选中态那条高亮带同高。
  static const double _itemExtent = 44;

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  late int _hours = widget.initialMinutes ~/ 60;
  late int _minutes = widget.initialMinutes % 60;

  int get _totalMinutes => _hours * 60 + _minutes;

  @override
  void initState() {
    super.initState();
    _hourController = FixedExtentScrollController(initialItem: _hours);
    _minuteController = FixedExtentScrollController(initialItem: _minutes);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  /// 把两根滚轮的取值收进 [TuyaConfig.standbyDelayMin]–[TuyaConfig.standbyDelayMax]。
  ///
  /// 3 时 30 分是 210 分钟，设备只认到 180；0 时 0 分是 0，也不合法。越界时把越界
  /// 的那一根滚轮拨回去，用户看到的就是「拨不过去」，而不是保存时才被告知。
  void _clampToRange() {
    final total = _totalMinutes;
    if (total > TuyaConfig.standbyDelayMax) {
      _hours = TuyaConfig.standbyDelayMax ~/ 60;
      _minutes = TuyaConfig.standbyDelayMax % 60;
    } else if (total < TuyaConfig.standbyDelayMin) {
      _hours = TuyaConfig.standbyDelayMin ~/ 60;
      _minutes = TuyaConfig.standbyDelayMin % 60;
    } else {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hourController.hasClients &&
          _hourController.selectedItem != _hours) {
        _hourController.animateToItem(
          _hours,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      if (_minuteController.hasClients &&
          _minuteController.selectedItem != _minutes) {
        _minuteController.animateToItem(
          _minutes,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Dialog(
      key: const Key('standby-delay-dialog'),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Flexible(
              child: AppDialogScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      l10n.standbyDelay,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.standbyDescription,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: _itemExtent * 3,
                      child: Stack(
                        children: <Widget>[
                          // 选中态的高亮带：滚轮本身只负责数字，居中那一格由它衬底。
                          Center(
                            child: Container(
                              height: _itemExtent,
                              decoration: BoxDecoration(
                                color: AppColors.canvas,
                                borderRadius: AppRadius.small,
                              ),
                            ),
                          ),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: _DelayWheel(
                                  wheelKey: const Key('standby-hour-wheel'),
                                  controller: _hourController,
                                  itemExtent: _itemExtent,
                                  count: TuyaConfig.standbyDelayMax ~/ 60 + 1,
                                  selected: _hours,
                                  unit: l10n.hourUnit,
                                  onSelected: (value) {
                                    setState(() {
                                      _hours = value;
                                      _clampToRange();
                                    });
                                  },
                                ),
                              ),
                              Expanded(
                                child: _DelayWheel(
                                  wheelKey: const Key('standby-minute-wheel'),
                                  controller: _minuteController,
                                  itemExtent: _itemExtent,
                                  count: 60,
                                  selected: _minutes,
                                  unit: l10n.minuteUnit,
                                  onSelected: (value) {
                                    setState(() {
                                      _minutes = value;
                                      _clampToRange();
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppDialogButton(
                    key: const Key('standby-delay-cancel'),
                    label: '取消',
                    textColor: AppColors.brandDark,
                    background: AppColors.brandSurface,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDialogButton(
                    key: const Key('standby-delay-save'),
                    label: l10n.save,
                    textColor: AppColors.surface,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        AppColors.brandPrimary,
                        AppColors.brandDark,
                      ],
                    ),
                    onTap: () => Navigator.of(context).pop(_totalMinutes),
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

/// 一根滚轮：数字居中，单位跟在选中那一格右边。
class _DelayWheel extends StatelessWidget {
  const _DelayWheel({
    required this.wheelKey,
    required this.controller,
    required this.itemExtent,
    required this.count,
    required this.selected,
    required this.unit,
    required this.onSelected,
  });

  final Key wheelKey;
  final FixedExtentScrollController controller;
  final double itemExtent;
  final int count;
  final int selected;
  final String unit;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      key: wheelKey,
      controller: controller,
      itemExtent: itemExtent,
      physics: const FixedExtentScrollPhysics(),
      // 透视压到最小：这一版设计里滚轮是平的，不要 iOS 那种圆筒感。
      perspective: 0.001,
      diameterRatio: 20,
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) {
          final active = index == selected;
          return Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  index.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: active
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                    fontSize: active ? 26 : 22,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (active) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    unit,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
