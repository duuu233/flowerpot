import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../models/about_page_model.dart';
import 'widgets/about_brand_lockup.dart';
import 'widgets/about_version_card.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.pageModel});

  final AboutPageModel? pageModel;

  @override
  Widget build(BuildContext context) {
    final model = pageModel ?? AboutPageModel.current();
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
          maxWidth: 375,
          padding: EdgeInsets.fromLTRB(20, compact ? 78 : 110, 20, 48),
          child: Column(
            children: <Widget>[
              const MockDataBanner(
                title: '占位内容',
                message: '版本号、更新状态与版本说明都是写死的，未接入版本服务。',
              ),
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
