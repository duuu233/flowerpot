import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
import '../../../design_system/design_system.dart';
import '../models/legal_document_page_model.dart';
import 'widgets/legal_document_card.dart';

class LegalPage extends StatefulWidget {
  const LegalPage({required this.privacy, super.key, this.pageModel});

  final bool privacy;
  final LegalDocumentPageModel? pageModel;

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage>
    with NetworkRetryAware<LegalPage> {
  bool _requested = false;

  LegalDocumentPageModel get _baseModel =>
      widget.pageModel ??
      (widget.privacy
          ? LegalDocumentPageModel.privacy()
          : LegalDocumentPageModel.agreement());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    // 协议正文后台可以改（`/Client/Basic/getBasicData`）。App 里那份是兜底：
    // 后台没配、或者接口不通时页面照常有内容，不会变成空白页。
    FlowerpotScope.maybeOf(context)?.loadBasicData();
  }

  @override
  Future<void> reloadForNetworkRetry() async {
    final state = FlowerpotScope.maybeOf(context);
    if (state == null) return;
    await state.loadBasicData();
  }

  @override
  Widget build(BuildContext context) {
    final base = _baseModel;
    final basic = FlowerpotScope.maybeOf(context)?.basicData;
    final remote = basic == null
        ? null
        : (widget.privacy ? basic.privacyPolicy : basic.userAgreement);
    final model = widget.pageModel != null || remote == null
        ? base
        : base.copyWith(
            sections: <LegalDocumentSection>[
              LegalDocumentSection(heading: '', body: remote),
            ],
          );

    return AppPageScaffold(
      appBar: AppPageHeader(
        title: model.pageTitle,
        leading: const AppBackButton(),
      ),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('legal-document-scroll-view'),
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(23, 14, 23, 30),
          child: LegalDocumentCard(model: model),
        ),
      ),
    );
  }
}
