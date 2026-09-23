import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/blocking_progress.dart';
import '../../devices/presentation/device_info_page.dart';
import '../../devices/presentation/device_online_guard.dart';
import '../mower_ui.dart';
import '../mower_device.dart';
import 'widgets/mower_card.dart';

/// 设备参数（`割草机-设备参数.png`）：设备名称 / 设备型号 / SN 三行，名称后面有支笔。
///
/// ⚠️ **这一页一条 DP 都没有**：名称/型号/SN 在涂鸦侧属于设备档案（DeviceBean / 平台产品信息），
/// 不是功能点。2026-09-23 起**不再画稿子上的假值**：名称取设备在涂鸦里的名字；
/// 型号、SN 没有数据来源（DeviceBean 里没有、功能点表里也没有，产品确认），空着。
///
/// 改名那支笔（2026-09-23 产品：「不用调 DP，跟花盆的名称修改一样，调后端的接口改」）：
/// 走 [FlowerpotState.renameDevice]——涂鸦设备名 + 后端 `editUserProduct` 同步，与花盆设备信息页同一条。
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
      state.logMowerInteraction('未接 ⚠ 割草机「设备参数」型号 / SN 没有数据来源，空着');
    });
  }

  Future<void> _rename(String id, String current) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => RenameDeviceDialog(initialName: current),
    );
    if (name == null || !mounted) return;
    final state = FlowerpotScope.of(context);
    state.logMowerInteraction('改名 → 割草机 $id「$current」→「${name.trim()}」（涂鸦 + 后端 editUserProduct）');
    // 改名走云端，点两次会提交两回。
    final result = await withBlockingProgress(
      context,
      () => state.renameDevice(id, name),
    );
    if (result == null || !mounted) return;
    state.logMowerInteraction(
      result.success ? '改名 ✓ ${result.message}' : '改名 ✗ ${result.message}',
    );
    showDeviceActionResult(context, result, announceSuccess: true);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final id = MowerDevice.instance.deviceId;
    final name = id == null
        ? ''
        : FlowerpotScope.of(context).deviceById(id)?.name ?? '';
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
                value: name,
                // 改名不是 DP：和花盆一样，涂鸦设备名 + 后端 editUserProduct。
                onEdit: id == null ? null : () => unawaited(_rename(id, name)),
              ),
              const MowerRowDivider(),
              // 没有数据来源，空着（不再画稿子上的 YM-1200 / YM202608240018）。
              const _ParameterRow(label: '设备型号', value: ''),
              const MowerRowDivider(),
              const _ParameterRow(label: 'SN', value: ''),
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
