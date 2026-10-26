import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/flowerpot_app.dart';
import '../../../../core/logging/ota_debug_log.dart';
import '../../../../design_system/design_system.dart';

/// **联调日志框（临时）。**
///
/// 2026-09-12 产品要求：和涂鸦、和设备每次数据交互都打到页面最下面，方便和固件对。
/// 只显示两类——**下发**（App → 设备的 DP 写）与**上报**（设备 → App 的 DP 变化），
/// 数据源是 `FlowerpotState.interactionLog`。
///
/// ⚠️ **这是临时设施，流程验通后连同 [FlowerpotState.interactionLog] 一起去掉。**
/// 放在页面最底部、可折叠，不占正常使用时的视线。
class InteractionLogPanel extends StatefulWidget {
  const InteractionLogPanel({super.key, this.onClose});

  /// 由浮层传进来：有它时「收起」是关掉整个浮层，没有时只折叠日志列表。
  final VoidCallback? onClose;

  @override
  State<InteractionLogPanel> createState() => _InteractionLogPanelState();
}

class _InteractionLogPanelState extends State<InteractionLogPanel> {
  bool _expanded = true;

  /// 「OTA日志」：把保留的 OTA 调试日志合并成一个 `.txt`，调起系统分享当附件发出去
  /// （微信 / QQ / 邮件；手机上可直接打开，也可发到电脑端）。不走剪贴板，没有长度限制。
  Future<void> _shareOtaLog() async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      final file = await OtaDebugLog.exportForShare();
      if (!mounted) return;
      if (file == null) {
        showAppMessage(context, '还没有 OTA 日志，做一次固件升级后再分享');
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'text/plain')],
          subject: 'OTA调试日志',
          // iPad 的分享面板需要锚点；手机上忽略。
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final path = await OtaDebugLog.currentPath();
      if (!mounted) return;
      showAppMessage(
        context,
        '分享失败：$error\n日志文件：${path ?? '目录不可用'}',
        tone: AppMessageTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final lines = state.interactionLog;
    return Container(
      key: const Key('interaction-log-panel'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.textTertiary.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '联调日志（下发 / 上报）',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (OtaDebugLog.enabled)
                TextButton(
                  key: const Key('interaction-log-ota'),
                  onPressed: _shareOtaLog,
                  child: const Text('OTA日志', style: TextStyle(fontSize: 12)),
                ),
              TextButton(
                onPressed: state.clearInteractionLog,
                child: const Text('清空', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed:
                    widget.onClose ??
                    () => setState(() => _expanded = !_expanded),
                child: Text(
                  widget.onClose != null || _expanded ? '收起' : '展开',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (_expanded)
            if (lines.isEmpty)
              const Text(
                '还没有交互。点任意一个下发按钮、或等设备上报一次就会出现。',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
              )
            else
              // 新的在最后，所以从下往上读；高度封顶，免得把页面撑长。
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    lines.join('\n'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
