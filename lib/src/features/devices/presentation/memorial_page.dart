import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/widgets/blocking_progress.dart';
import '../../../tuya/tuya_memorial_codec.dart';
import 'device_online_guard.dart';
import 'memorial_edit_page.dart';

/// 纪念日列表（`docs/UI/v2/智能花盆ysplanter/纪念日.png`）。
///
/// 两条固定纪念日（生日 / 结婚纪念日）走 DP 158 / 159，自定义条目走 DP 154 的
/// upsert 帧。固定的两条只能停用或改日期，删不掉——设备上那两个功能点一直在，
/// 「删除」只会把它们清成停用态，和列表里少一行不是一回事。
class MemorialPage extends StatefulWidget {
  const MemorialPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<MemorialPage> createState() => _MemorialPageState();
}

class _MemorialPageState extends State<MemorialPage>
    with NetworkRetryAware<MemorialPage> {
  bool _requested = false;

  /// 接了后端时本次进页面的拉取状态：还没拉到显示加载中，失败显示重试，不拿本机存的
  /// 旧列表顶替（2026-10-21 用户「读取到的数据不做任何缓存」）。
  bool _loading = false;
  bool _loadFailed = false;

  String get deviceId => widget.deviceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    // 自定义条目以后端为准（`/Client/UserProduct/getProductAnniversaryList`），
    // 进页面拉一次。没接后端时不拉，页面继续显示本地那份清单。
    _loading = FlowerpotScope.of(context).memorialsFromBackend;
    unawaited(_load());
  }

  @override
  Future<void> reloadForNetworkRetry() => _load();

  Future<void> _load() async {
    final state = FlowerpotScope.of(context);
    if (!state.memorialsFromBackend) return;
    if (!_loading || _loadFailed) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    var failed = false;
    try {
      await state.refreshMemorials(deviceId);
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadFailed = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final device = state.deviceById(deviceId);
    if (device == null) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '纪念日', leading: AppBackButton()),
        body: const AppErrorView(title: '未找到设备', message: '设备不存在或已经解绑。'),
      );
    }
    if (_loading || _loadFailed) {
      return AppPageScaffold(
        appBar: const AppPageHeader(title: '纪念日', leading: AppBackButton()),
        background: AppPageBackground.standard,
        body: AppLoadStateView(
          key: const Key('memorial-load-state'),
          state: _loading ? AppLoadState.loading : AppLoadState.error,
          content: const SizedBox.shrink(),
          errorMessage: '纪念日加载失败，请检查网络后重试',
          onRetry: () => unawaited(_load()),
        ),
      );
    }
    final entries = state.memorialsFor(deviceId);
    final customCount = state.customMemorialsFor(deviceId).length;
    // 计数按整份列表算：两条固定纪念日也占位，满的时候是 12 条，不是 10 条。
    // 「新增」的可用性仍然只看自定义那 10 条，固定的两条删不掉也加不了。
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '纪念日', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('memorial-scroll-view'),
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            22,
            AppSpacing.pageMargin,
            40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SectionHeader(
                title: '自定义纪念日',
                trailing: '${entries.length}/${TuyaMemorialCodec.maxEntries}条',
              ),
              const SizedBox(height: AppSpacing.md),
              for (final entry in entries) ...<Widget>[
                _MemorialRow(
                  entry: entry,
                  onTap: () => _edit(context, entry),
                  onDelete: entry.isFixed
                      ? null
                      : () => _delete(context, entry),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              // 稿子 513:1880：最后一张卡到「新增纪念日」20（卡间距 12 之外再补 8）。
              const SizedBox(height: 8),
              _AddMemorialButton(
                enabled: customCount < TuyaMemorialCodec.maxCustomEntries,
                onTap: () => _add(context, state.nextMemorialId(deviceId)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _edit(BuildContext context, MemorialEntry entry) {
    Navigator.pushNamed(
      context,
      AppRoutes.memorialEdit,
      arguments: MemorialEditArguments(deviceId: deviceId, entry: entry),
    );
  }

  void _add(BuildContext context, int id) {
    Navigator.pushNamed(
      context,
      AppRoutes.memorialEdit,
      arguments: MemorialEditArguments(
        deviceId: deviceId,
        entry: MemorialEntry(
          id: id,
          date: DateTime.now(),
          type: MemorialContentType.text,
          content: '',
        ),
        creating: true,
      ),
    );
  }

  Future<void> _delete(BuildContext context, MemorialEntry entry) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除纪念日',
      message: '「${entry.title.isEmpty ? entry.dateLabel : entry.title}」'
          '将从设备上移除，确定继续吗？',
      confirmLabel: '删除',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!confirmed || !context.mounted) return;
    final state = FlowerpotScope.of(context);
    // 删除要下发 DP154，点两次会发两帧。
    final result = await withBlockingProgress(
      context,
      () => state.deleteMemorial(deviceId, entry.id),
    );
    if (result == null || !context.mounted) return;
    showDeviceActionResult(context, result, announceSuccess: true);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 4,
          height: 18,
          decoration: const BoxDecoration(
            color: AppColors.brandPrimary,
            borderRadius: AppRadius.small,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          trailing,
          key: const Key('memorial-count'),
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

/// One row. Custom entries swipe left to reveal 删除, matching the Figma frame;
/// the two fixed rows have nothing to reveal and are plain cards.
class _MemorialRow extends StatelessWidget {
  const _MemorialRow({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  final MemorialEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final card = _MemorialCard(entry: entry, onTap: onTap);
    final delete = onDelete;
    if (delete == null) return card;
    return Dismissible(
      key: ValueKey<int>(entry.id),
      direction: DismissDirection.endToStart,
      background: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.danger,
          borderRadius: AppRadius.card,
        ),
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 32),
            child: Text(
              '删除',
              style: TextStyle(
                color: AppColors.surface,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
      // 删除要先弹确认，确认完由页面自己刷新列表，所以这里永远不让 Dismissible
      // 把行移除——否则确认框还没关，行已经从树上消失了。
      confirmDismiss: (_) async {
        delete();
        return false;
      },
      child: card,
    );
  }
}

class _MemorialCard extends StatelessWidget {
  const _MemorialCard({required this.entry, required this.onTap});

  final MemorialEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.card,
      child: InkWell(
        key: Key('memorial-row-${entry.kind.name}-${entry.id}'),
        borderRadius: AppRadius.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: <Widget>[
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.brandSurface,
                  shape: BoxShape.circle,
                ),
                // 稿子图标 36、到文字 12（原 46 / 16）。
                child: SizedBox.square(
                  dimension: 36,
                  child: Icon(_icon, color: AppColors.brandPrimary, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.title.isEmpty ? '未命名纪念日' : entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.enabled ? entry.dateLabel : '已停用',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const AppTrailingChevron(),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (entry.kind) {
    MemorialKind.birthday => Icons.cake_outlined,
    MemorialKind.wedding => Icons.favorite_border,
    MemorialKind.custom => Icons.event_note_outlined,
  };
}

class _AddMemorialButton extends StatelessWidget {
  const _AddMemorialButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.brandPrimary : AppColors.disabled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('memorial-add'),
        borderRadius: AppRadius.card,
        onTap: enabled ? onTap : null,
        child: AppDashedBorder(
          color: color,
          // 稿子按钮 52 高、加号 24、间距 8（原 64 / 30 / 12）。
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: const SizedBox.square(
                    dimension: 24,
                    child: Icon(Icons.add, color: AppColors.surface, size: 16),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '新增纪念日',
                  style: TextStyle(color: color, fontSize: 17),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
