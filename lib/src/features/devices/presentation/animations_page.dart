import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
import '../../../core/network/api_exception.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/media/upload_image.dart';
import '../../../shared/widgets/blocking_progress.dart';
import '../../../tuya/tuya_models.dart';
import 'device_online_guard.dart';

class AnimationsPage extends StatefulWidget {
  const AnimationsPage({required this.deviceId, super.key});

  static const uploadZoneKey = Key('animation-upload-zone');

  final String deviceId;

  @override
  State<AnimationsPage> createState() => _AnimationsPageState();
}

class _AnimationsPageState extends State<AnimationsPage>
    with NetworkRetryAware<AnimationsPage> {
  bool loadingStarted = false;

  /// 图库里当前选中的那一张（[AnimationAsset.id]），没选中是 null。选中态属于
  /// 页面而不是每个格子——底部那条操作栏要按「有没有选中」换面孔。
  ///
  /// ⚠️ **只能单选**（2026-09-17 产品）：这里从 `Set<String>` 改成一个可空 id，
  /// 「同时选中两张」在类型上就不成立了，不是靠「点的时候记得把别的清掉」这种
  /// 约定维持的。DP 157（置顶）本来也只认一个文件名。
  String? _selectedId;

  /// 本页正在跑一件要等的事。
  ///
  /// ⚠️ **不能只看 `FlowerpotState.busy`**：删除是**一串**请求（逐张删云端 + 逐张
  /// 下发 DP155），两次请求之间 `busy` 会掉回 false，按钮闪回可点；上传前面还夹着
  /// 系统选图器，那一段也不在 `busy` 里。所以本页自己再记一道
  /// （2026-09-12 产品：所有可能重复点击的地方都要有 loading）。
  bool _busy = false;

  /// 跑一件要等的事：本页置忙 + 盖一层不可点穿的进度圈。
  Future<T?> _run<T>(Future<T> Function() action) async {
    if (_busy || !mounted) return null;
    setState(() => _busy = true);
    try {
      return await withBlockingProgress(context, action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loadingStarted) return;
    loadingStarted = true;
    unawaited(_refreshFiles());
  }

  @override
  Future<void> reloadForNetworkRetry() => _refreshFiles();

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
                    23,
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
                          selectedId: _selectedId,
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
              hasSelection: _selectedId != null,
              onUpload: state.busy || _busy || files.length >= 10
                  ? null
                  : () => _pickFile(context),
              // DP 157 一次只认一个文件名；单选之后「选中的」本来就只有一张。
              onPinSelected: state.busy || _busy || _selectedId == null
                  ? null
                  : () => _pinSelected(context, files),
              onDeleteSelected: state.busy || _busy || _selectedId == null
                  ? null
                  : () => _deleteSelected(context, files),
              onClearSelection: _busy || _selectedId == null
                  ? null
                  : () => setState(() => _selectedId = null),
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
    // 上传要走一次文件上传 + 一次下发，最慢的一步，必须挡住重复点击。压缩也罩在
    // 同一个进度圈里：解码 + 编码有几百毫秒，露在外面用户会以为没点上。
    final result = await _run(() async {
      // 花盆那块屏幕只有 320 × 240：压到框以内、Baseline 4:2:0、500 KB 以内再传，
      // 见 [UploadImage]。压不出合格的图就不传——设备下载完也显示不了（固件 1.0.12）。
      final path = await UploadImage.prepare(file.path);
      if (path == null) {
        return const ActionResult(false, '图片处理失败，换一张图片再试');
      }
      return state.addAnimation(
        widget.deviceId,
        name: path.split(RegExp(r'[/\\]')).last,
        path: path,
      );
    });
    if (result == null || !context.mounted) return;
    showDeviceActionResult(context, result, announceSuccess: true);
  }

  /// 点一下切换选中。**单选**：点另一张就是把选中换过去，攒不出第二张；再点一次
  /// 当前这张是取消选中（等价于底部的「取消选择」）。
  void _toggleSelection(AnimationAsset file) {
    setState(() => _selectedId = _selectedId == file.id ? null : file.id);
  }

  /// 当前选中的那张文件，没选中或者列表里已经没有它了都返回 null。
  ///
  /// 不直接用 `_selectedId` 取对象：删除或刷新之后列表会换，选中的 id 可能已经
  /// 不在列表里，这时候按钮该点不动，而不是拿着一个失效 id 去发 DP。
  AnimationAsset? _selectedFile(List<AnimationAsset> files) {
    for (final file in files) {
      if (file.id == _selectedId) return file;
    }
    return null;
  }

  /// 删除选中的那一张。
  ///
  /// 云端那份由 [FlowerpotState.deleteAnimation] 删；设备本地那份要另外下发
  /// DP 155（按文件名删一张）或 156（全清），否则花盆屏幕上还会继续放这张图。
  ///
  /// 单选之后「删的正好是全部」只剩一种情况：图库里就这一张。这时候仍然走 156
  /// （全清）——一次下发比 155 可靠，设备侧也不用按文件名去匹配。
  Future<void> _deleteSelected(
    BuildContext context,
    List<AnimationAsset> files,
  ) async {
    final target = _selectedFile(files);
    if (target == null) {
      showAppMessage(context, '请先选择要删除的文件', tone: AppMessageTone.info);
      return;
    }
    final all = files.length == 1;
    final confirmed = await showAppConfirmDialog(
      context,
      title: all ? '清空全部文件' : '删除选中文件',
      message: all
          ? '设备上这 1 个文件会被清空，确定继续吗？'
          : '选中的文件会从云端和设备上移除，确定继续吗？',
      confirmLabel: '删除',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!confirmed || !context.mounted) return;
    final state = FlowerpotScope.of(context);
    // ⚠️ **两条请求一起罩住**：删云端 + 下发 DP 之间 `FlowerpotState.busy` 会掉回
    // false，按钮闪回可点，用户再点一次就会删两遍。
    final failed = await _run(() async {
      var count = 0;
      if (all) {
        final cleared = await state.deleteAllDevicePhotos(widget.deviceId);
        if (!cleared.success) return -1;
      } else {
        final removed = await state.deleteDevicePhoto(
          widget.deviceId,
          target.name,
        );
        if (!removed.success) count++;
      }
      final result = await state.deleteAnimation(widget.deviceId, target.id);
      if (!result.success) count++;
      return count;
    });
    if (failed == null || !context.mounted) return;
    if (failed < 0) {
      showAppMessage(context, '清空设备图片失败，请重试', tone: AppMessageTone.error);
      return;
    }
    setState(() => _selectedId = null);
    showAppMessage(
      context,
      failed == 0 ? '已删除 1 个文件' : '文件删除失败，请重试',
      tone: failed == 0 ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  /// 底部第一颗钮：把**当前选中的那一张**置顶。
  ///
  /// DP 157 `pin_photo` 一次只带一个文件名。单选之后这里只兜一次「选中的还在不在
  /// 列表里」，防止列表刚换过、按钮状态还没跟上时拿失效 id 去发 DP。
  Future<void> _pinSelected(
    BuildContext context,
    List<AnimationAsset> files,
  ) async {
    final target = _selectedFile(files);
    if (target == null) {
      showAppMessage(context, '请先选择要置顶的图片', tone: AppMessageTone.info);
      return;
    }
    await _pinFile(context, target);
  }

  /// DP 157：让设备优先显示这张图。云端列表的顺序也跟着挪，两边看到的第一张
  /// 才是同一张。
  Future<void> _pinFile(BuildContext context, AnimationAsset file) async {
    final state = FlowerpotScope.of(context);
    final result = await _run(
      () => state.pinDevicePhoto(widget.deviceId, file.name),
    );
    if (result == null || !context.mounted) return;
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
            // 稿子 156:5548 虚线区 267 高。
            child: SizedBox(
              height: 267,
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
                    // 2026-09-14 产品定稿：手机端没有拖拽上传，不要出现「拖拽」。
                    Text(
                      '点击此处上传文件',
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
/// 三列缩略图，**选中的那一张**右上角画一个勾选圈（没选中的格子不画空圈，
/// 2026-09-17 产品）。设计稿里那排圆按钮搬到了页面底部的 [_GalleryActionBar]，
/// 卡片本身只管网格。长按一张是「置顶」（DP 157），frame 里没有按钮位置，放在
/// 长按上。
class _UploadedFilesCard extends StatelessWidget {
  const _UploadedFilesCard({
    required this.files,
    required this.selectedId,
    required this.onToggle,
    required this.onPin,
  });

  final List<AnimationAsset> files;

  /// 当前选中的文件 id，没选中是 null。**单选**，见 `_AnimationsPageState`。
  final String? selectedId;
  final ValueChanged<AnimationAsset> onToggle;
  final ValueChanged<AnimationAsset> onPin;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      // 稿子 692:2612：卡片内边距 12，网格横 12 / 纵 8，格子 96×100。
      padding: const EdgeInsets.all(12),
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
          // 「支持多选」2026-09-17 去掉了：现在只能单选，写着支持多选是错的。
          const Text(
            '选中后可删除；长按可置顶',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.lg),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: files.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 12,
              childAspectRatio: 96 / 100,
            ),
            itemBuilder: (context, index) => _GalleryTile(
              file: files[index],
              index: index,
              selected: files[index].id == selectedId,
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
/// 底部悬浮操作区。**按有没有选中图片切两副面孔**（2026-09-12 产品要求）：
///
/// - **没选中**：一条长按钮「上传图片」，宽度约 80%，圆角胶囊——和全站其它页面
///   底部那颗主按钮（选择植物页的「确认选择」）同一个样式。原来这里是一颗 56 的
///   小圆钮，产品反馈「太小了」。
/// - **选中了**：换成一排圆形功能钮——**置顶**、删除、取消选择。
///   ⚠️ 选中态**不画上传**（2026-09-12 产品二次明确：「选中图片的时候，下面的上传
///   图片小图标就不需要了」）。要传新图先点「取消选择」。
///
/// ⚠️ **最左边那颗是「置顶」（DP 157 `pin_photo`）**，不是上传。产品 2026-09-12
/// 指出原来这一颗挂的是上传，DPID 对不上；上传现在是没选中时那条长按钮。
class _GalleryActionBar extends StatelessWidget {
  const _GalleryActionBar({
    required this.hasSelection,
    required this.onUpload,
    required this.onPinSelected,
    required this.onDeleteSelected,
    required this.onClearSelection,
  });

  /// 条子的高度，滚动内容按它留底部内边距。两副面孔里高的那个说了算。
  static const double height = _GalleryAction.diameter + AppSpacing.md * 2;

  /// 长按钮占屏宽的比例。产品说「大概 80vw」。
  static const double _uploadWidthFactor = .8;

  final bool hasSelection;
  final VoidCallback? onUpload;
  final VoidCallback? onPinSelected;
  final VoidCallback? onDeleteSelected;
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    // 缩略图会从按钮下面滚过去，底部渐变把它压淡，按钮才始终看得清。空白处不
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
        child: SizedBox(
          height: _GalleryAction.diameter,
          child: Center(
            child: hasSelection ? _selectionActions() : _uploadButton(context),
          ),
        ),
      ),
    );
  }

  /// 没选中图片时的那条长按钮。样式照搬选择植物页底部那一颗。
  Widget _uploadButton(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: _uploadWidthFactor,
      child: FilledButton(
        key: const Key('animation-upload-action'),
        onPressed: onUpload,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          backgroundColor: AppColors.brandPrimary,
          foregroundColor: AppColors.surface,
          disabledBackgroundColor: AppColors.disabled,
          disabledForegroundColor: AppColors.surface,
          elevation: 2,
          shadowColor: AppColors.brandPrimary.withValues(alpha: .35),
          shape: const StadiumBorder(),
          textStyle: AppTypography.pageTitle.copyWith(color: AppColors.surface),
        ),
        child: const Text('上传图片'),
      ),
    );
  }

  /// 选中图片之后的几颗功能钮。**第一颗是置顶（DP 157）**，上传照旧保留。
  Widget _selectionActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _GalleryAction(
          actionKey: const Key('animation-pin-action'),
          icon: Icons.vertical_align_top,
          color: AppColors.brandPrimary,
          tooltip: '置顶显示',
          onTap: onPinSelected,
        ),
        const SizedBox(width: AppSpacing.lg),
        _GalleryAction(
          actionKey: const Key('animation-delete-action'),
          icon: Icons.delete_outline,
          color: AppColors.danger,
          tooltip: '删除选中',
          onTap: onDeleteSelected,
        ),
        const SizedBox(width: AppSpacing.lg),
        _GalleryAction(
          actionKey: const Key('animation-clear-selection-action'),
          icon: Icons.close,
          color: AppColors.textSecondary,
          tooltip: '取消选择',
          onTap: onClearSelection,
        ),
      ],
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
            // 选中才画勾选圈。**没选中的格子什么都不画**（2026-09-17 产品：去掉
            // 未选中时的多选框，只保留选中后的样式）——原来每张图右上角都顶着一个
            // 半透明空圈，九宫格看着像一排待勾的复选框。
            if (selected)
              Positioned(
                key: Key('animation-tile-selected-$index'),
                top: 6,
                right: 6,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 26,
                    child: Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.surface,
                    ),
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
