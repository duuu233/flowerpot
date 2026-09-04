import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/legal_document_page_model.dart';

class LegalDocumentCard extends StatelessWidget {
  const LegalDocumentCard({required this.model, super.key});

  final LegalDocumentPageModel model;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('legal-document-card'),
      padding: const EdgeInsets.fromLTRB(17, 20, 17, 28),
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      showShadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Text(
              model.documentTitle,
              textAlign: TextAlign.center,
              style: AppTypography.deviceTitle.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text('更新日期：${model.updatedAt}', style: _metaStyle),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerRight,
                  fit: BoxFit.scaleDown,
                  child: Text('生效日期：${model.effectiveAt}', style: _metaStyle),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (
            var index = 0;
            index < model.sections.length;
            index++
          ) ...<Widget>[
            if (model.sections[index].heading.isNotEmpty) ...<Widget>[
              Text(
                model.sections[index].heading,
                key: Key('legal-section-$index'),
                style: AppTypography.sectionTitle.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              model.sections[index].body,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
            if (index < model.sections.length - 1)
              const SizedBox(height: AppSpacing.xl),
          ],
        ],
      ),
    );
  }

  static final TextStyle _metaStyle = AppTypography.smallBody.copyWith(
    color: AppColors.textSecondary,
    fontSize: 12,
    height: 1.2,
  );
}
