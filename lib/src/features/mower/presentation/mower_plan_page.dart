import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../mower_demo.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_plan_chart.dart';
import 'widgets/mower_plan_dialogs.dart';
import 'widgets/mower_plan_edit_sheet.dart';

/// 割草计划页（`割草机-割草计划.png` 及编辑弹窗、两张提示弹窗）。
///
/// 静态页，但**图上的编辑是真的会变的**：勾选、编辑、长按删除、恢复默认都只改这一页
/// 自己的 [_slots] / [_enabledDays]，退出去就没了。这样产品点进来能把四张图（图表、
/// 编辑弹窗、重叠提示、恢复默认确认）逐个走一遍，而不是对着四张静态图想象。
class MowerPlanPage extends StatefulWidget {
  const MowerPlanPage({super.key});

  @override
  State<MowerPlanPage> createState() => _MowerPlanPageState();
}

class _MowerPlanPageState extends State<MowerPlanPage> {
  late List<MowerPlanSlot> _slots = List<MowerPlanSlot>.of(
    MowerDemoPlan.slots,
  );
  late List<bool> _enabledDays = List<bool>.of(MowerDemoPlan.enabledDays);

  /// 合计只算勾上的那几天——没勾的那天设备根本不出门。
  String get _totalLabel {
    var minutes = 0;
    for (final slot in _slots) {
      if (_enabledDays[slot.day]) {
        minutes += slot.endMinutes - slot.startMinutes;
      }
    }
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '总工作时间：$rest分钟';
    if (rest == 0) return '总工作时间：$hours小时';
    return '总工作时间：$hours小时$rest分钟';
  }

  Future<void> _edit(int day, int? slot) async {
    var draft = MowerPlanDraft.forDay(day, _slots, activeSlot: slot ?? 1);
    // 重叠时弹窗先关、提示弹出来，点「返回修改」再把同一份草稿开回去——
    // 稿子上那张提示图的背景就是计划页本身，不是压在编辑弹窗上面。
    while (true) {
      if (!mounted) return;
      final result = await showMowerPlanEditSheet(context, draft: draft);
      if (result is MowerPlanEditSaved) {
        setState(() => _applyDraft(result.draft));
        return;
      }
      if (result is! MowerPlanEditOverlap) return;
      if (!mounted) return;
      final retry = await showMowerOverlapDialog(
        context,
        message: result.message,
      );
      if (retry != true) return;
      draft = result.draft;
    }
  }

  void _applyDraft(MowerPlanDraft draft) {
    final days = draft.copyWeek
        ? List<int>.generate(MowerDemoPlan.dayLabels.length, (index) => index)
        : <int>[draft.day];
    _slots = _slots
        .where((slot) => !days.contains(slot.day))
        .toList(growable: true);
    for (final day in days) {
      _slots
        ..add(
          MowerPlanSlot(
            day: day,
            startMinutes: draft.one.startMinutes,
            endMinutes: draft.one.endMinutes,
            slot: 1,
            trim: draft.one.trim,
          ),
        )
        ..add(
          MowerPlanSlot(
            day: day,
            startMinutes: draft.two.startMinutes,
            endMinutes: draft.two.endMinutes,
            slot: 2,
            trim: draft.two.trim,
          ),
        );
    }
  }

  Future<void> _restoreDefault() async {
    final confirmed = await showMowerRestoreDefaultDialog(context);
    if (confirmed != true || !mounted) return;
    setState(() {
      _slots = List<MowerPlanSlot>.of(MowerDemoPlan.slots);
      _enabledDays = List<bool>.of(MowerDemoPlan.enabledDays);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: '割草计划',
        leading: const AppBackButton(),
        actions: <Widget>[_RestoreDefaultButton(onTap: _restoreDefault)],
      ),
      body: SingleChildScrollView(
        key: const Key('mower-plan-scroll-view'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text(
                  '本周计划',
                  style: TextStyle(
                    color: MowerColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _totalLabel,
                  key: const Key('mower-plan-total'),
                  style: const TextStyle(
                    color: MowerColors.brand,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            MowerCard(
              padding: const EdgeInsets.only(bottom: 18),
              child: MowerPlanChart(
                enabledDays: _enabledDays,
                slots: _slots,
                onToggleDay: (day) => setState(
                  () => _enabledDays[day] = !_enabledDays[day],
                ),
                onEditDay: (day, slot) => unawaited(_edit(day, slot)),
                onDeleteSlot: (slot) => setState(() => _slots.remove(slot)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标题栏右边那颗「恢复默认」。
class _RestoreDefaultButton extends StatelessWidget {
  const _RestoreDefaultButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        key: const Key('mower-plan-restore'),
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: MowerColors.softFill,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.history_rounded, size: 16, color: MowerColors.brand),
              SizedBox(width: 5),
              Text(
                '恢复默认',
                style: TextStyle(color: MowerColors.brand, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
