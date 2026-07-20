import 'package:flutter/material.dart';

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

  HelpCenterPageModel get _model =>
      widget.pageModel ?? HelpCenterPageModel.figma;

  @override
  void initState() {
    super.initState();
    _expandedIds = <String>{..._model.initiallyExpandedIds};
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
              maxWidth: 375,
              padding: const EdgeInsets.fromLTRB(20, 72, 20, 40),
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
