import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// 日志区滚动条要常显（2026-11-02 产品：拉高一点并显示滚动条，方便翻看），
  /// [Scrollbar] 与列表必须共用同一个控制器。
  final ScrollController _logScroll = ScrollController();

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

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

  /// 刚复制完时标题右边那句「已复制…」；2 秒后消失。
  ///
  /// 不用 `showAppMessage`：日志框挂在 Navigator 外面，往上找不到 Overlay，提示条
  /// 会静默不出。
  String? _copiedNotice;
  Timer? _copiedTimer;

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _copiedNotice = '已复制$what');
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedNotice = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final entries = state.interactionLog
        .map(InteractionLogEntry.parse)
        .toList(growable: false);
    final buttonStyle = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12),
    );
    return Container(
      key: const Key('interaction-log-panel'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.textTertiary.withValues(alpha: .3)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: .08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '联调日志 · ${entries.length} 条（新的在最下面）',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_copiedNotice != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    _copiedNotice!,
                    key: const Key('interaction-log-copied'),
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          // 按钮单独一排、可换行：窄屏上和标题挤一行会把标题压成两三行。
          Wrap(
            spacing: 2,
            children: <Widget>[
              TextButton(
                key: const Key('interaction-log-copy-all'),
                style: buttonStyle,
                onPressed: entries.isEmpty
                    ? null
                    : () => _copy(
                        entries.map((entry) => entry.copyText).join('\n\n'),
                        '全部日志',
                      ),
                child: const Text('复制全部'),
              ),
              TextButton(
                key: const Key('interaction-log-device-snapshot'),
                style: buttonStyle,
                onPressed: state.logDeviceListSnapshot,
                child: const Text('设备快照'),
              ),
              if (OtaDebugLog.enabled)
                TextButton(
                  key: const Key('interaction-log-ota'),
                  style: buttonStyle,
                  onPressed: _shareOtaLog,
                  child: const Text('OTA日志'),
                ),
              TextButton(
                style: buttonStyle,
                onPressed: state.clearInteractionLog,
                child: const Text('清空'),
              ),
              TextButton(
                style: buttonStyle,
                onPressed:
                    widget.onClose ??
                    () => setState(() => _expanded = !_expanded),
                child: Text(
                  widget.onClose != null || _expanded ? '收起' : '展开',
                ),
              ),
            ],
          ),
          if (_expanded)
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4, right: 4),
                child: Text(
                  '还没有日志。点任意一个下发按钮、等设备上报一次，或点「设备快照」。',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              )
            else
              // 新的在最后，所以从下往上读；高度封顶，免得把页面撑长。
              // 2026-11-02 起封顶由 180 拉到屏高的 45%（不低于 180），滚动条常显；
              // 2026-11-19 改成一条一块（时间 + 标题 + 缩进明细，条间分隔线），拉到 55%。
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * .55)
                      .clamp(220.0, double.infinity)
                      .toDouble(),
                ),
                child: Scrollbar(
                  controller: _logScroll,
                  thumbVisibility: true,
                  child: ListView.separated(
                    key: const Key('interaction-log-list'),
                    controller: _logScroll,
                    reverse: true,
                    shrinkWrap: true,
                    // 右侧让出滚动条的位置，长行不压在滑块下面
                    padding: const EdgeInsets.only(right: 10),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 17,
                      thickness: .5,
                      color: AppColors.divider,
                    ),
                    itemBuilder: (context, index) {
                      final entry = entries[entries.length - 1 - index];
                      return _LogEntryTile(
                        entry: entry,
                        onCopy: () => _copy(entry.copyText, '这条日志'),
                      );
                    },
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// 一条联调日志拆成「时间 / 标题 / 明细」用于排版（2026-11-19 用户：排版一下，
/// 便于查看复制，不要密密麻麻挤在一起）。
///
/// 日志原文是 `HH:MM:SS 内容`，内容可以是多行（第一行当标题，其余原样当明细，保留
/// 缩进）。只有一行、又用「；」或「 · 」串了好几段的，拆成一段一行。只改显示，不改
/// 状态层里记的原文；复制的是排好版的文字，和屏幕上看到的一致。
@immutable
class InteractionLogEntry {
  const InteractionLogEntry({
    required this.time,
    required this.title,
    this.details = const <String>[],
  });

  factory InteractionLogEntry.parse(String raw) {
    final match = _timePrefix.firstMatch(raw);
    final time = match?.group(1) ?? '';
    final body = match == null ? raw : raw.substring(match.end);
    final lines = body.split('\n');
    var title = lines.first.trim();
    var details = lines.skip(1).toList();
    while (details.isNotEmpty && details.last.trim().isEmpty) {
      details.removeLast();
    }
    if (details.isEmpty) {
      final parts = title
          .split(_segmentSeparator)
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.length > 1) {
        title = parts.first;
        details = <String>[for (final part in parts.skip(1)) '  $part'];
      }
    }
    return InteractionLogEntry(time: time, title: title, details: details);
  }

  static final RegExp _timePrefix = RegExp(r'^(\d{2}:\d{2}:\d{2}) ');
  static final RegExp _segmentSeparator = RegExp(r'；| · ');

  final String time;
  final String title;
  final List<String> details;

  /// 复制出去的文字：首行「时间 标题」，明细一行一条。
  String get copyText => <String>[
    time.isEmpty ? title : '$time $title',
    ...details,
  ].join('\n');
}

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({required this.entry, required this.onCopy});

  final InteractionLogEntry entry;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (entry.time.isNotEmpty) ...<Widget>[
              Container(
                margin: const EdgeInsets.only(top: 1),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.brandSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.time,
                  style: const TextStyle(
                    color: AppColors.brandDark,
                    fontSize: 11,
                    height: 1.4,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: SelectableText(
                entry.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onCopy,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(6, 2, 2, 2),
                child: Text(
                  '复制',
                  style: TextStyle(color: AppColors.brandDark, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        if (entry.details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText(
              entry.details.join('\n'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.55,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }
}
