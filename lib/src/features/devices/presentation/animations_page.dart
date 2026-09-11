import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/flowerpot_app.dart';
import '../../../core/network/api_exception.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import 'device_online_guard.dart';

class AnimationsPage extends StatefulWidget {
  const AnimationsPage({required this.deviceId, super.key});

  static const uploadZoneKey = Key('animation-upload-zone');

  final String deviceId;

  @override
  State<AnimationsPage> createState() => _AnimationsPageState();
}

class _AnimationsPageState extends State<AnimationsPage> {
  bool loadingStarted = false;

  /// Files ticked in the gallery. 图库管理（v2）是多选删除，所以选中态属于页面
  /// 而不是每个格子。
  final Set<String> _selected = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loadingStarted) return;
    loadingStarted = true;
    unawaited(_refreshFiles());
  }

  Future<void> _refreshFiles() async {
    try {
      await FlowerpotScope.of(context).refreshAnimations(widget.deviceId);
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        '图片列表加载失败：${error.message}',
        tone: AppMessageTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final files = state
        .animationsFor(widget.deviceId)
        .where((item) => !item.path.startsWith('builtin://'))
        .toList(growable: false);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '定制动画', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: Stack(
        children: <Widget>[
          CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: ResponsiveContent(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageMargin,
                    AppSpacing.xxxl,
                    AppSpacing.pageMargin,
                    // 给底部那条悬浮按钮留位置，否则最后一行缩略图会被压在下面。
                    _GalleryActionBar.height + AppSpacing.xxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _AnimationTipsCard(),
                      const SizedBox(height: AppSpacing.md),
                      // 有图就只画图库卡：v2 设计稿
                      // `docs/UI/v2/智能花盆ysplanter/定制动画-已上传图片（图库管理）.png`
                      // 里没有虚线上传位。虚线位是空态的样子（`docs/UI/定制动画.png`），
                      // 上传入口本身已经常驻在底部悬浮条上。
                      if (files.isEmpty)
                        _UploadCard(
                          fileCount: files.length,
                          enabled: !state.busy,
                          onTap: () => _pickFile(context),
                        )
                      else
                        _UploadedFilesCard(
                          files: files,
                          selected: _selected,
                          onToggle: _toggleSelection,
                          onPin: (file) => _pinFile(context, file),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _GalleryActionBar(
              hasFiles: files.isNotEmpty,
              onUpload: state.busy || files.length >= 10
                  ? null
                  : () => _pickFile(context),
              onDeleteSelected: state.busy || _selected.isEmpty
                  ? null
                  : () => _deleteSelected(context, files),
              onClearSelection: _selected.isEmpty
                  ? null
                  : () => setState(_selected.clear),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    final state = FlowerpotScope.of(context);
    final fileCount = state
        .animationsFor(widget.deviceId)
        .where((item) => !item.path.startsWith('builtin://'))
        .length;
    if (fileCount >= 10) {
      showAppMessage(context, '最多只能上传 10 个文件', tone: AppMessageTone.info);
      return;
    }
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (file == null || !context.mounted) return;
    final result = await state.addAnimation(
      widget.deviceId,
      name: file.name,
      path: file.path,
    );
    if (!context.mounted) return;
    showDeviceActionResult(context, result, announceSuccess: true);
  }

  void _toggleSelection(AnimationAsset file) {
    setState(() {
      if (!_selected.remove(file.id)) _selected.add(file.id);
    });
  }

  /// 删除选中的文件。
  ///
  /// 云端那份由 [FlowerpotState.deleteAnimation] 删；设备本地那份要另外下发
  /// DP 155（按文件名删一张）或 156（全清），否则花盆屏幕上还会继续放这些图。
  /// 全选时用 156：一次下发比逐张删可靠，也少几十条 DP。
  Future<void> _deleteSelected(
    BuildContext context,
    List<AnimationAsset> files,
  ) async {
    final targets = files
        .where((item) => _selected.contains(item.id))
        .toList(growable: false);
    if (targets.isEmpty) {
      showAppMessage(context, '请先选择要删除的文件', tone: AppMessageTone.info);
      return;
    }
    final all = targets.length == files.length;
    final confirmed = await showAppConfirmDialog(
      context,
      title: all ? '清空全部文件' : '删除选中文件',
      message: all
          ? '设备上的 ${files.length} 个文件都会被清空，确定继续吗？'
          : '选中的 ${targets.length} 个文件会从云端和设备上移除，确定继续吗？',
      confirmLabel: '删除',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!confirmed || !context.mounted) return;
    final state = FlowerpotScope.of(context);
    if (all) {
      final cleared = await state.deleteAllDevicePhotos(widget.deviceId);
      if (!context.mounted) return;
      if (!cleared.success) {
        showAppMessage(context, cleared.message, tone: AppMessageTone.error);
        return;
      }
    }
    var failed = 0;
    for (final file in targets) {
      if (!all) {
        final removed = await state.deleteDevicePhoto(
          widget.deviceId,
          file.name,
        );
        if (!removed.success) failed++;
      }
      final result = await state.deleteAnimation(widget.deviceId, file.id);
      if (!result.success) failed++;
    }
    if (!context.mounted) return;
    setState(_selected.clear);
    showAppMessage(
      context,
      failed == 0 ? '已删除 ${targets.length} 个文件' : '有 $failed 个文件删除失败，请重试',
      tone: failed == 0 ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  /// DP 157：让设备优先显示这张图。云端列表的顺序也跟着挪，两边看到的第一张
  /// 才是同一张。
  Future<void> _pinFile(BuildContext context, AnimationAsset file) async {
    final state = FlowerpotScope.of(context);
    final result = await state.pinDevicePhoto(widget.deviceId, file.name);
    if (!context.mounted) return;
    if (result.success) state.pinAnimation(file.id);
    showDeviceActionResult(context, result, announceSuccess: true);
  }
}

class _AnimationTipsCard extends StatelessWidget {
  const _AnimationTipsCard();

  /// 文案区的高度，不含卡片内边距。
  static const double _contentHeight = 126;
  static const EdgeInsets _contentPadding = EdgeInsets.fromLTRB(16, 14, 14, 14);

  @override
  Widget build(BuildContext context) {
    // 右下角那张背景图要贴着卡片右边缘，所以内边距交给文案自己加、卡片本身不留
    // padding。原来的写法反过来：卡片留 padding，图片靠负偏移往外顶，而 Stack 的
    // `clipBehavior` 默认是 `Clip.hardEdge`——顶出去的 18px / 14px 根本不画。盒子
    // 高度改短之后被切掉的正好是文件夹的下沿和右边的叶子，看着就是图缺了一块。
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: _contentHeight + _contentPadding.vertical,
        child: Stack(
          children: <Widget>[
            // 右边贴着卡片边缘出血，底部留出和文案一样的 14px——设计稿里图就是这么
            // 摆的，这样整张图既完整、也不会被卡片 16px 的圆角削掉叶子尖。
            const Positioned(
              right: 0,
              bottom: 14,
              child: Opacity(
                opacity: .42,
                child: _FilePreviewIllustration(
                  key: Key('animation-tips-illustration'),
                  size: 118,
                ),
              ),
            ),
            Padding(
              padding: _contentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const AppIconBadge(
                        assetPath: AppAssets.notificationIcon,
                        semanticLabel: '提示',
                        backgroundColor: Colors.transparent,
                        size: 34,
                        iconSize: 34,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        '提示',
                        style: AppTypography.pageTitle.copyWith(fontSize: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '请上传符合要求的文件以确保动画可以正常播放。',
                      maxLines: 1,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _TipLine(text: '支持本地图片文件上传'),
                  const SizedBox(height: AppSpacing.xs),
                  const _TipLine(text: '长按文件可删除已选文件'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipLine extends StatelessWidget {
  const _TipLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.brandPrimary,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(dimension: 7),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTypography.compactBody.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.fileCount,
    required this.enabled,
    required this.onTap,
  });

  final int fileCount;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: AppDashedBorder(
        child: Material(
          key: AnimationsPage.uploadZoneKey,
          color: AppColors.brandSurface.withValues(alpha: .34),
          borderRadius: AppRadius.card,
          child: InkWell(
            borderRadius: AppRadius.card,
            onTap: enabled ? onTap : null,
            child: SizedBox(
              height: 252,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Image.asset(
                      AppAssets.cloudUploadIcon,
                      width: 70,
                      height: 70,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      semanticLabel: '上传文件',
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      '上传文件',
                      style: AppTypography.deviceTitle.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '点击或拖拽文件到这里上传',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          const TextSpan(text: 'Files  '),
                          TextSpan(
                            text: '$fileCount/10',
                            style: const TextStyle(
                              color: AppColors.brandPrimary,
                            ),
                          ),
                        ],
                      ),
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '仅支持JPG/GIF等格式',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 已上传文件（`docs/UI/v2/智能花盆ysplanter/定制动画-已上传图片（图库管理）.png`）。
///
/// 三列缩略图 + 右上角勾选圈。设计稿里那排圆按钮搬到了页面底部的
/// [_GalleryActionBar]，卡片本身只管网格。长按一张是「置顶」（DP 157），
/// frame 里没有按钮位置，放在长按上。
class _UploadedFilesCard extends StatelessWidget {
  const _UploadedFilesCard({
    required this.files,
    required this.selected,
    required this.onToggle,
    required this.onPin,
  });

  final List<AnimationAsset> files;
  final Set<String> selected;
  final ValueChanged<AnimationAsset> onToggle;
  final ValueChanged<AnimationAsset> onPin;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '已上传文件',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${files.length}/10',
                key: const Key('animation-file-count'),
                style: const TextStyle(
                  color: AppColors.brandPrimary,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '支持多选，选中后可删除；长按可置顶',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.lg),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: files.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemBuilder: (context, index) => _GalleryTile(
              file: files[index],
              index: index,
              selected: selected.contains(files[index].id),
              onTap: () => onToggle(files[index]),
              onLongPress: () => onPin(files[index]),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部悬浮操作条。
///
/// 上传按钮常驻，不跟着网格一起消失：图库空着的时候页面上只剩虚线上传位，这颗
/// 按钮是随手就能点到的那个入口。「删除选中」「取消选择」只在已经有上传的图片时
/// 才画——没有图的时候这两个按钮永远点不动，画出来只是两个灰圈。
class _GalleryActionBar extends StatelessWidget {
  const _GalleryActionBar({
    required this.hasFiles,
    required this.onUpload,
    required this.onDeleteSelected,
    required this.onClearSelection,
  });

  /// 条子的高度，滚动内容按它留底部内边距。
  static const double height = _GalleryAction.diameter + AppSpacing.md * 2;

  final bool hasFiles;
  final VoidCallback? onUpload;
  final VoidCallback? onDeleteSelected;
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    // 缩略图会从按钮下面滚过去，底部渐变把它压淡，圆按钮才始终看得清。空白处不
    // 吃点击（DecoratedBox 自己不参与命中测试），贴边滚动仍然滚得动。
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x00FAFAFA), AppColors.canvas],
          stops: <double>[0, .55],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageMargin,
          vertical: AppSpacing.md,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _GalleryAction(
              actionKey: const Key('animation-upload-action'),
              icon: Icons.file_upload_outlined,
              color: AppColors.brandPrimary,
              tooltip: '上传文件',
              onTap: onUpload,
            ),
            if (hasFiles) ...<Widget>[
              const SizedBox(width: AppSpacing.xl),
              _GalleryAction(
                actionKey: const Key('animation-delete-action'),
                icon: Icons.delete_outline,
                color: AppColors.danger,
                tooltip: '删除选中',
                onTap: onDeleteSelected,
              ),
              const SizedBox(width: AppSpacing.xl),
              _GalleryAction(
                actionKey: const Key('animation-clear-selection-action'),
                icon: Icons.close,
                color: AppColors.textSecondary,
                tooltip: '取消选择',
                onTap: onClearSelection,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.file,
    required this.index,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final AnimationAsset file;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandSurface,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('animation-tile-$index'),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _Thumbnail(path: file.path),
            Positioned(
              top: 6,
              right: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.brandPrimary
                      : AppColors.surface.withValues(alpha: .72),
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 26,
                  child: selected
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: AppColors.surface,
                        )
                      : null,
                ),
              ),
            ),
            if (!file.synced)
              const Positioned(
                left: 6,
                bottom: 6,
                child: Icon(
                  Icons.cloud_upload_outlined,
                  size: 18,
                  color: AppColors.warningSoft,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 缩略图。后端返回的是 URL，本地刚选的是文件路径，读不出来就退回一个图标——
/// 网格里留个空白格子会让人以为文件坏了。
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    const fallback = Center(
      child: Icon(
        Icons.image_outlined,
        color: AppColors.brandDark,
        size: 26,
      ),
    );
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    if (path.startsWith('builtin://')) return fallback;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _GalleryAction extends StatelessWidget {
  const _GalleryAction({
    required this.actionKey,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  static const double diameter = 56;

  final Key actionKey;
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled ? color : AppColors.disabled,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        // 按钮悬浮在页面内容之上，给一点投影把它和底下的缩略图分开。
        elevation: enabled ? 4 : 0,
        shadowColor: AppColors.textPrimary,
        child: InkWell(
          key: actionKey,
          onTap: onTap,
          child: SizedBox.square(
            dimension: diameter,
            child: Icon(icon, color: AppColors.surface, size: 24),
          ),
        ),
      ),
    );
  }
}

class _FilePreviewIllustration extends StatelessWidget {
  const _FilePreviewIllustration({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        AppAssets.animationUploadIllustration,
        fit: BoxFit.cover,
        alignment: Alignment.centerRight,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}
