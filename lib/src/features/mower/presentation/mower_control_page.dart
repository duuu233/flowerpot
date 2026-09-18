import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../mower_demo.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_status_card.dart';

/// 割草机首页（`docs/UI/v2/割草机/割草机-控制.png` 及其三张状态图）。
///
/// 静态页：电量、今日计划、状态都来自 [MowerDemoDevice]，四颗操作按钮只换选中态，
/// 不下发任何 DP。
///
/// **四种电量态怎么看**：稿子给了默认 / 充电中 / 电量告警 / 低电量四张图，它们的差别
/// 全在环和环下面那行字上。这里**点一下电量环就切到下一态**——否则那三张图在 App 里
/// 永远看不到，产品只能对着 PNG 看。真设备接进来之后把 [_state] 换成设备上报即可。
class MowerControlPage extends StatefulWidget {
  const MowerControlPage({super.key});

  @override
  State<MowerControlPage> createState() => _MowerControlPageState();
}

class _MowerControlPageState extends State<MowerControlPage> {
  MowerPowerState _state = MowerPowerState.idle;
  MowerAction _action = MowerAction.returnHome;

  /// 「停止」按下去之后换成「继续」（稿子里的 `操作 / 继续`）。
  bool _paused = false;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(
        title: MowerDemoDevice.name,
        leading: AppBackButton(),
      ),
      body: SingleChildScrollView(
        key: const Key('mower-control-scroll-view'),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MowerStatusCard(
              state: _state,
              onTapRing: () => setState(() => _state = _state.next),
            ),
            const SizedBox(height: 24),
            const _SafetyNotice(),
            const SizedBox(height: 8),
            const _TodayPlanCard(),
            const SizedBox(height: 8),
            _ActionPanel(
              selected: _action,
              paused: _paused,
              onSelected: (action) => setState(() {
                _action = action;
                if (action == MowerAction.stop) _paused = !_paused;
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// 安全提醒条。
class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('mower-safety-notice'),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: BoxDecoration(
        color: MowerColors.noticeFill,
        border: Border.all(color: MowerColors.noticeBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Image.asset(
            MowerAssets.safetyTipIcon,
            width: 17,
            height: 16,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              MowerDemoDevice.safetyTip,
              style: TextStyle(color: MowerColors.noticeText, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// 今日计划卡。
class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard();

  @override
  Widget build(BuildContext context) {
    return MowerCard(
      key: const Key('mower-today-plan'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                '今日计划',
                style: TextStyle(
                  color: MowerColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.54,
                ),
              ),
              Text(
                MowerDemoDevice.todayDate,
                style: const TextStyle(
                  color: MowerColors.inkSecondary,
                  fontSize: 12,
                  height: 1.33,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                MowerDemoDevice.todayRange,
                style: const TextStyle(
                  color: MowerColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  height: 1.56,
                ),
              ),
              Container(
                width: 54,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MowerColors.softFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  MowerDemoDevice.todayTaskLabel,
                  style: TextStyle(color: MowerColors.brand, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            MowerDemoDevice.todayNext,
            style: TextStyle(
              color: MowerColors.brand,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 四颗操作按钮。选中的那一颗底下垫一块 `#EEF6F7`。
class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.selected,
    required this.paused,
    required this.onSelected,
  });

  final MowerAction selected;
  final bool paused;
  final ValueChanged<MowerAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return MowerCard(
      key: const Key('mower-action-panel'),
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (final action in MowerAction.values)
            _ActionButton(
              action: action,
              active: action == selected,
              // 「停止」按下之后同位换成「继续」：稿子里它们是同一颗按钮的两个态。
              paused: paused && action == MowerAction.stop,
              onTap: () => onSelected(action),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.active,
    required this.paused,
    required this.onTap,
  });

  final MowerAction action;
  final bool active;
  final bool paused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('mower-action-${action.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 70,
        height: 86,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? MowerColors.softFill : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset(
              paused ? MowerAssets.actionResumeIcon : action.icon,
              width: 40,
              height: 40,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 7),
            Text(
              paused ? '继续' : action.label,
              style: const TextStyle(
                color: MowerColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
