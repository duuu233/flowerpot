import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/backend/backend.dart';
import '../../../../design_system/design_system.dart';

/// App 升级弹窗。
///
/// 两种形态共用这一个弹窗，差别只在能不能关：
/// - **强制升级**（`/Client/Basic/getLastVersion` 的 `compulsory == 1`）：App 打开
///   后检测到就弹，没有取消、返回键也关不掉，升级完是新装的包，重进自然不再命中；
/// - **提示升级**：用户在「关于东方金穗 → 检查更新」里点出来的，可以「稍后再说」。
///
/// 「立即更新」用外部浏览器 / 应用商店打开后台配置的下载地址（`downloadPath`）。
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
            onPressed: () => _openDownloadUrl(dialogContext, version, force),
            child: const Text('立即更新'),
          ),
        ],
      ),
    ),
  );
}

/// 下载地址来自后台，只放行 https 与两家应用商店的 scheme：被配成 intent://、tel://
/// 之类时，外部打开会直接拉起任意应用。
const Set<String> _allowedDownloadSchemes = <String>{'https', 'market', 'itms-apps'};

Future<void> _openDownloadUrl(
  BuildContext context,
  BackendAppVersion version,
  bool force,
) async {
  final url = version.downloadUrl.trim();
  if (url.isEmpty) {
    showAppMessage(context, '后台还没有配置下载地址', tone: AppMessageTone.error);
    return;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !_allowedDownloadSchemes.contains(uri.scheme)) {
    showAppMessage(context, '下载地址无效，请稍后再试', tone: AppMessageTone.error);
    return;
  }
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // 没有应用商店的 ROM 上 market:// 会抛 PlatformException，不能冒泡崩掉 App。
  }
  if (!context.mounted) return;
  if (!opened) {
    showAppMessage(context, '无法打开下载地址，请稍后再试', tone: AppMessageTone.error);
    return;
  }
  // 强制升级不关弹窗：用户从下载页回来若没真的升级，仍然被挡着。
  if (!force) Navigator.of(context).pop();
}
