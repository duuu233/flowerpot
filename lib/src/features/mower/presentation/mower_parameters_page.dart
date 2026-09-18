import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../mower_demo.dart';
import 'widgets/mower_card.dart';

/// 设备参数（`割草机-设备参数.png`）：设备名称 / 设备型号 / SN 三行，名称后面有支笔。
class MowerParametersPage extends StatelessWidget {
  const MowerParametersPage({super.key});

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
                // 稿子上只有一支笔，没给编辑页；点了先说明这是静态页。
                onEdit: () => showAppMessage(
                  context,
                  '静态页面：改名入口本轮没有出图',
                  tone: AppMessageTone.info,
                ),
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
