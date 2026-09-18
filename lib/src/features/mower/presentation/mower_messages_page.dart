import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../mower_demo.dart';
import 'widgets/mower_bottom_nav.dart';
import 'widgets/mower_card.dart';

/// 消息通知（`割草机-消息通知.png`）。
///
/// 从设置页进来，底部导航照旧画着、停在「设置」那一栏；点「首页 / 割草计划」时
/// 先退回外壳再切到那一栏（[onTabRequested]），而不是在这一页上面再叠一层。
class MowerMessagesPage extends StatefulWidget {
  const MowerMessagesPage({required this.onTabRequested, super.key});

  /// 退回外壳之后要切到哪一栏。
  final ValueChanged<MowerTab> onTabRequested;

  @override
  State<MowerMessagesPage> createState() => _MowerMessagesPageState();
}

class _MowerMessagesPageState extends State<MowerMessagesPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AppPageScaffold(
        appBar: const AppPageHeader(title: '消息通知', leading: AppBackButton()),
        body: SingleChildScrollView(
          key: const Key('mower-messages-scroll-view'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _CategoryTabs(
                current: _tab,
                onChanged: (index) => setState(() => _tab = index),
              ),
              const SizedBox(height: 12),
              const _DateFilterCard(),
              const SizedBox(height: 12),
              for (final message in MowerDemoMessages.items) ...<Widget>[
                _MessageCard(message: message),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: MowerBottomNav(
        current: MowerTab.settings,
        onTap: (tab) {
          Navigator.of(context).pop();
          if (tab != MowerTab.settings) widget.onTabRequested(tab);
        },
      ),
    );
  }
}

/// 日志 / 提醒 / 告警。稿子只画了「日志」那一档的内容，另外两档同版式空着——
/// 这里点得动、但列表不换数据，免得凭空造两批不存在的消息。
class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.current, required this.onChanged});

  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < MowerDemoMessages.tabs.length; i++)
            Expanded(
              child: GestureDetector(
                key: Key('mower-messages-tab-$i'),
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == current
                        ? MowerColors.brand
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    MowerDemoMessages.tabs[i],
                    style: TextStyle(
                      color: i == current ? Colors.white : MowerColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DateFilterCard extends StatelessWidget {
  const _DateFilterCard();

  @override
  Widget build(BuildContext context) {
    return MowerCard(
      color: Colors.white.withValues(alpha: .92),
      radius: 15,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 52,
        child: Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                '日期筛选',
                style: TextStyle(
                  color: MowerColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Text(
              MowerDemoMessages.dateFilter,
              style: TextStyle(color: MowerColors.brand, fontSize: 15),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 22,
              color: MowerColors.brand.withValues(alpha: .9),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final MowerMessage message;

  @override
  Widget build(BuildContext context) {
    return MowerCard(
      color: Colors.white.withValues(alpha: .86),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  message.title,
                  style: const TextStyle(
                    color: MowerColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                message.time,
                style: const TextStyle(
                  color: MowerColors.inkSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message.detail,
            style: const TextStyle(
              color: MowerColors.inkSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
