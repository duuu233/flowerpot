import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../core/backend/backend.dart';
import '../../../design_system/design_system.dart';
import '../models/about_page_model.dart';
import 'widgets/about_brand_lockup.dart';
import 'widgets/about_version_card.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.pageModel});

  final AboutPageModel? pageModel;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _requested = false;

  AboutPageModel get _baseModel =>
      widget.pageModel ?? AboutPageModel.current();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    // 更新状态和版本说明来自 `/Client/Basic/getLastVersion`，要把本机版本号发
    // 过去做比对。后端没开或查不到就用页面自带的「已是最新版本」。
    FlowerpotScope.maybeOf(context)?.checkAppVersion(_baseModel.version);
  }

  /// 后端的判定覆盖到页面模型上。当前版本号仍然显示本机的那个——`version`
  /// 是「我装的是哪一版」，不是「线上最新是哪一版」。
  static AboutPageModel _merge(AboutPageModel model, BackendAppVersion? latest) {
    if (latest == null) return model;
    return model.copyWith(
      updateStatus: latest.hasUpdate ? '发现新版本 V${latest.versionNo}' : '已是最新版本',
      releaseNotes: latest.releaseNotes.isEmpty ? null : latest.releaseNotes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = _merge(
      _baseModel,
      FlowerpotScope.maybeOf(context)?.appVersion,
    );
    final compact = MediaQuery.sizeOf(context).height < 700;

    return AppPageScaffold(
      appBar: const AppPageHeader(
        title: '关于YSplanter',
        leading: AppBackButton(),
      ),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('about-scroll-view'),
        child: ResponsiveContent(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            compact ? 78 : 110,
            AppSpacing.pageMargin,
            48,
          ),
          child: Column(
            children: <Widget>[
              AboutBrandLockup(model: model),
              const SizedBox(height: 32),
              AboutVersionCard(
                model: model,
                onCheckUpdate: () => showAppMessage(
                  context,
                  model.updateStatus,
                  tone: AppMessageTone.info,
                ),
                onReleaseNotes: () => _showReleaseNotes(context, model),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReleaseNotes(BuildContext context, AboutPageModel model) {
    return showAppBottomSheet<void>(
      context,
      title: '版本说明',
      builder: (sheetContext) => Column(
        key: const Key('about-release-notes-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            model.displayVersion,
            style: AppTypography.sectionTitle.copyWith(
              color: AppColors.brandDark,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final note in model.releaseNotes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text('• $note', style: AppTypography.body),
            ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
