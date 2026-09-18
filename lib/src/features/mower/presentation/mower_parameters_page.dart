import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../mower_demo.dart';
import '../mower_device.dart';
import 'widgets/mower_card.dart';

/// 设备参数（`割草机-设备参数.png`）：设备名称 / 设备型号 / SN 三行，名称后面有支笔。
///
/// ⚠️ **这一页一条 DP 都没有**：名称/型号/SN 在涂鸦侧属于设备档案（DeviceBean / 平台产品信息），
/// 不是功能点。按 2026-09-18 用户口径，进页面提示一句「当前还没有支持的 DPID」，
/// 页面照常画（版式先定下来），改名那支笔同样只提示。
class MowerParametersPage extends StatefulWidget {
  const MowerParametersPage({super.key});

  @override
  State<MowerParametersPage> createState() => _MowerParametersPageState();
}

class _MowerParametersPageState extends State<MowerParametersPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = FlowerpotScope.of(context);
      state.logPageEntry('割草机-设备参数');
      MowerDevice.instance.logUnsupported(state, '设备参数');
      showAppMessage(context, '当前还没有支持的 DPID', tone: AppMessageTone.info);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '设备参数', leading: AppBackButton()),
      body: SingleChildScrollView(
        key: const Key('mower-parameters-scroll-view'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: MowerCard(
          child: Column(
            children: <Widget>[
              _ParameterRow(
                label: '设备名称',
                value: MowerDemoDevice.name,
                // 稿子上只有一支笔，没给编辑页；改名走的也不是 DP，这一轮只提示。
                onEdit: () {
                  MowerDevice.instance.logUnsupported(
                    FlowerpotScope.of(context),
                    '设备改名',
                  );
                  showAppMessage(
                    context,
                    '当前还没有支持的 DPID',
                    tone: AppMessageTone.info,
                  );
                },
              ),
              const MowerRowDivider(),
              const _ParameterRow(
                label: '设备型号',
                value: MowerDemoDevice.model,
              ),
              const MowerRowDivider(),
              const _ParameterRow(
                label: 'SN',
                value: MowerDemoDevice.serialNumber,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParameterRow extends StatelessWidget {
  const _ParameterRow({required this.label, required this.value, this.onEdit});

  final String label;
  final String value;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                color: MowerColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              value,
              key: Key('mower-parameter-$label'),
              style: const TextStyle(
                color: MowerColors.inkSecondary,
                fontSize: 13,
              ),
            ),
            if (onEdit != null) ...<Widget>[
              const SizedBox(width: 8),
              GestureDetector(
                key: const Key('mower-parameter-rename'),
                onTap: onEdit,
                child: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: MowerColors.inkSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
