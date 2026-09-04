import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/help_center_model.dart';
import 'widgets/help_center_faq_list.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key, this.pageModel});

  final HelpCenterPageModel? pageModel;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  late Set<String> _expandedIds;
  bool _requested = false;

  /// 后台配的常见问题。null = 还没拉到，页面先用内置的那几条。
  List<HelpCenterFaqItem>? _remoteItems;

  HelpCenterPageModel get _model {
    final pageModel = widget.pageModel;
    if (pageModel != null) return pageModel;
    final remote = _remoteItems;
    if (remote == null || remote.isEmpty) return HelpCenterPageModel.figma;
    return HelpCenterPageModel(
      items: remote,
      initiallyExpandedIds: <String>{remote.first.id},
    );
  }

  @override
  void initState() {
    super.initState();
    _expandedIds = <String>{..._model.initiallyExpandedIds};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested || widget.pageModel != null) return;
    _requested = true;
    _loadFaqs();
  }

  /// 后台配了就用后台那份（`/Client/Product/getProductFaqList`）；返回空或者
  /// 接口不通时保留内置的四条，帮助中心不会变成空页。
  Future<void> _loadFaqs() async {
    final state = FlowerpotScope.maybeOf(context);
    if (state == null) return;
    final faqs = await state.loadFaqs();
    if (!mounted || faqs.isEmpty) return;
    setState(() {
      _remoteItems = faqs
          .map(
            (faq) => HelpCenterFaqItem(
              id: 'faq-${faq.faqId}',
              question: faq.question,
              answer: faq.answer,
            ),
          )
          .toList(growable: false);
      _expandedIds = <String>{..._model.initiallyExpandedIds};
    });
  }

  @override
  void didUpdateWidget(covariant HelpPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageModel != widget.pageModel) {
      _expandedIds = <String>{..._model.initiallyExpandedIds};
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '帮助中心', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: CustomScrollView(
        key: const Key('help-center-scroll-view'),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.lg,
                AppSpacing.pageMargin,
                40,
              ),
              child: HelpCenterFaqList(
                items: _model.items,
                expandedIds: _expandedIds,
                onToggle: _toggleFaq,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleFaq(String id) {
    setState(() {
      if (!_expandedIds.add(id)) {
        _expandedIds.remove(id);
      }
    });
  }
}
