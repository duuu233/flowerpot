import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/backend/backend.dart';
import '../../../../design_system/design_system.dart';

/// App 升级弹窗。
///
/// 两种形态共用这一个弹窗，差别只在能不能关：
/// - **强制升级**（`/Client/Basic/getLastVersion` 的 `compulsory == 1`）：App 打开
///   后检测到就弹，没有取消、返回键也关不掉，升级完是新装的包，重进自然不再命中；
/// - **提示升级**：用户在「关于东方金穗 → 检查更新」里点出来的，可以「稍后再说」。
///
/// 「立即更新」目前把下载地址复制到剪贴板——项目还没有 `url_launcher` 依赖，加它
/// 需要跑一次 `flutter pub get`；接上之后把 [_copyDownloadUrl] 换成打开链接即可。
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required BackendAppVersion version,
  required bool force,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !force,
    builder: (dialogContext) => PopScope(
      canPop: !force,
      child: AlertDialog(
        key: const Key('app-update-dialog'),
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        title: Text(
          '发现新版本 V${version.versionNo}',
          style: AppTypography.sectionTitle.copyWith(fontSize: 17),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: AppDialogScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (version.releaseNotes.isEmpty)
                  Text('建议更新到最新版本以获得更稳定的体验。', style: AppTypography.body)
                else
                  for (final note in version.releaseNotes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text('• $note', style: AppTypography.body),
                    ),
                if (force) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '这是一次必须完成的更新，升级后才能继续使用。',
                    style: AppTypography.smallBody.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          if (!force)
            TextButton(
              key: const Key('app-update-later'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('稍后再说'),
            ),
          FilledButton(
            key: const Key('app-update-now'),
            onPressed: () => _copyDownloadUrl(dialogContext, version, force),
            child: const Text('立即更新'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _copyDownloadUrl(
  BuildContext context,
  BackendAppVersion version,
  bool force,
) async {
  final url = version.downloadUrl.trim();
  if (url.isEmpty) {
    showAppMessage(context, '后台还没有配置下载地址', tone: AppMessageTone.error);
    return;
  }
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  showAppMessage(context, '下载地址已复制，请在浏览器中打开');
  // 强制升级不关弹窗：用户拿到地址去更新，回来仍然被挡着。
  if (!force) Navigator.of(context).pop();
}
