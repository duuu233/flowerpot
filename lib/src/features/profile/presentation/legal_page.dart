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
          padding: const EdgeInsets.fromLTRB(23, 28, 23, 30),
          child: LegalDocumentCard(model: model),
        ),
      ),
    );
  }
}
