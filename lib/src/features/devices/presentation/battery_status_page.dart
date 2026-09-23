import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/battery_status_page_model.dart';
import 'widgets/battery_status_summary_card.dart';

/// 电池状态。入口在设备设置页（2026-09-15 从首页快捷列表挪过去）。
///
/// 只有顶部这张摘要卡：功能点表里没有电池的历史 DP（只有 103 电量、104 状态、
/// 145 充电中三个实时值），电量历史报表 2026-09-15 按产品要求删掉，日期切换一并去掉。
class BatteryStatusPage extends StatelessWidget {
  const BatteryStatusPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final device = FlowerpotScope.of(context).deviceById(deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '电池状态', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    final summaryModel = BatteryStatusPageModel.fromDevice(device);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '电池状态', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                23,
                AppSpacing.pageMargin,
                32,
              ),
              child: BatteryStatusSummaryCard(model: summaryModel),
            ),
          ),
        ],
      ),
    );
  }
}
