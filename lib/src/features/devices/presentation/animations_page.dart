import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';

class AnimationsPage extends StatelessWidget {
  const AnimationsPage({required this.deviceId, super.key});

  static const uploadZoneKey = Key('animation-upload-zone');

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final files = state.animations
        .where((item) => !item.path.startsWith('builtin://'))
        .toList(growable: false);
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: '定制动画',
        leading: const AppBackButton(),
        actions: <Widget>[
          TextButton.icon(
            onPressed: state.busy ? null : () => _syncFiles(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              backgroundColor: AppColors.surface.withValues(alpha: .72),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: const StadiumBorder(),
            ),
            icon: Image.asset(
              AppAssets.refreshIcon,
              width: 20,
              height: 20,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
            label: const Text('文件同步'),
          ),
        ],
      ),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
              maxWidth: 375,
              padding: const EdgeInsets.fromLTRB(20, 72, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _PermissionBanner(
                    onAuthorize: state.busy ? null : () => _pickFile(context),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _AnimationTipsCard(),
                  const SizedBox(height: AppSpacing.md),
                  _UploadCard(
                    fileCount: files.length,
                    enabled: !state.busy && files.length < 10,
                    onTap: () => _pickFile(context),
                  ),
                  if (files.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    for (final file in files) ...<Widget>[
                      _AnimationFileTile(
                        file: file,
                        onDelete: () {
                          state.deleteAnimation(file.id);
                          showAppMessage(context, '已删除 ${file.name}');
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    final state = FlowerpotScope.of(context);
    final fileCount = state.animations
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
      deviceId,
      name: file.name,
      path: file.path,
    );
    if (!context.mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  Future<void> _syncFiles(BuildContext context) async {
    final state = FlowerpotScope.of(context);
    final result = await state.syncAnimations(deviceId);
    if (!context.mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.onAuthorize});

  final VoidCallback? onAuthorize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.dangerSurface,
      borderRadius: AppRadius.card,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: <Widget>[
            Image.asset(
              AppAssets.warningIcon,
              width: 40,
              height: 40,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: '权限提示',
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '仅支持屏幕录制或本地文件。',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  InkWell(
                    onTap: onAuthorize,
                    child: Text(
                      '点击这里重新授权',
                      style: AppTypography.body.copyWith(
                        color: AppColors.brandPrimary,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.brandPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimationTipsCard extends StatelessWidget {
  const _AnimationTipsCard();

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: SizedBox(
        height: 126,
        child: Stack(
          children: <Widget>[
            const Positioned(
              right: -14,
              bottom: -18,
              child: Opacity(
                opacity: .42,
                child: _FilePreviewIllustration(size: 118),
              ),
            ),
            Column(
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
                const _TipLine(text: '支持屏幕录制文件或本地文件上传'),
                const SizedBox(height: AppSpacing.xs),
                const _TipLine(text: '长按文件可删除已选文件'),
              ],
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
      child: CustomPaint(
        painter: const _DashedRoundedRectPainter(),
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
                      enabled ? '点击或拖拽文件到这里上传' : '文件数量已达到上限',
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

class _AnimationFileTile extends StatelessWidget {
  const _AnimationFileTile({required this.file, required this.onDelete});

  final AnimationAsset file;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              const AppIconBadge(
                icon: Icons.image_outlined,
                color: AppColors.brandDark,
                backgroundColor: AppColors.brandSurface,
                size: 44,
                iconSize: 24,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyEmphasis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      file.synced ? '已同步 · 长按删除' : '待同步 · 长按删除',
                      style: AppTypography.smallBody,
                    ),
                  ],
                ),
              ),
              Icon(
                file.synced
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined,
                color: file.synced ? AppColors.success : AppColors.warningSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRoundedRectPainter extends CustomPainter {
  const _DashedRoundedRectPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(AppRadius.md),
        ),
      );
    final metrics = path.computeMetrics();
    final paint = Paint()
      ..color = AppColors.brandPrimary.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 5.0;
    const gap = 5.0;
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            math.min(distance + dash, metric.length),
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedRectPainter oldDelegate) => false;
}

class _FilePreviewIllustration extends StatelessWidget {
  const _FilePreviewIllustration({required this.size});

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
