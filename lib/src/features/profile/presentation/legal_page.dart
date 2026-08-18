import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../models/legal_document_page_model.dart';
import 'widgets/legal_document_card.dart';

class LegalPage extends StatelessWidget {
  const LegalPage({required this.privacy, super.key, this.pageModel});

  final bool privacy;
  final LegalDocumentPageModel? pageModel;

  @override
  Widget build(BuildContext context) {
    final model =
        pageModel ??
        (privacy
            ? LegalDocumentPageModel.privacy()
            : LegalDocumentPageModel.agreement());

    return AppPageScaffold(
      appBar: AppPageHeader(
        title: model.pageTitle,
        leading: const AppBackButton(),
      ),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('legal-document-scroll-view'),
        child: ResponsiveContent(
          maxWidth: 375,
          padding: const EdgeInsets.fromLTRB(23, 79, 23, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const MockDataBanner(
                title: '占位文案',
                message: '正文与生效日期是示例内容，上线前需替换为正式版本。',
              ),
              LegalDocumentCard(model: model),
            ],
          ),
        ),
      ),
    );
  }
}
