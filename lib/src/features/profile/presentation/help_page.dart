import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
import '../../../design_system/design_system.dart';
import '../models/help_center_model.dart';
import 'widgets/help_center_faq_list.dart';

/// 帮助中心：常见问题全部来自后台 `/Client/Product/getProductFaqList`。
///
/// **没有内置兜底数据**——产品口径是「全部动态读取，没有就为空，不要用静态数据
/// 兜底」。后台没配或接口不通时这里就是一个空态，而不是几条对不上版本的假问答。
///
/// 答案是后台富文本编辑器（wangEditor）存的 HTML，交给 [HelpCenterFaqList] 里的
/// [AppRichHtml] 渲染，不能当纯文本显示。
class HelpPage extends StatefulWidget {
  const HelpPage({super.key, this.pageModel, this.productId});

  /// 测试和预览用。传了就不请求后台。
  final HelpCenterPageModel? pageModel;

  /// 按哪个产品筛常见问题（`getProductFaqList` 的 `broadcastId`）。
  ///
  /// 割草机的设置页带 [MowerDp.productId] 进来；花盆那条路不传，走
  /// [FlowerpotState.loadFaqs] 的默认口径（优先匹配花盆产品 ID，匹配不到取第一个）。
  final String? productId;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> with NetworkRetryAware<HelpPage> {
  Set<String> _expandedIds = <String>{};
  bool _requested = false;

  /// null = 还没拉到，空列表 = 后台确实没有。
  List<HelpCenterFaqItem>? _remoteItems;

  HelpCenterPageModel? get _model {
    final pageModel = widget.pageModel;
    if (pageModel != null) return pageModel;
    final remote = _remoteItems;
    if (remote == null) return null;
    return HelpCenterPageModel(
      items: remote,
      initiallyExpandedIds: remote.isEmpty
          ? const <String>{}
          : <String>{remote.first.id},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested || widget.pageModel != null) return;
    _requested = true;
    _loadFaqs();
  }

  /// 「网络异常」弹窗点「重试」：回到加载态，重新拉一次常见问题。
  @override
  Future<void> reloadForNetworkRetry() async {
    if (widget.pageModel != null) return;
    setState(() => _remoteItems = null);
    await _loadFaqs();
  }

  Future<void> _loadFaqs() async {
    final state = FlowerpotScope.maybeOf(context);
    if (state == null) {
      setState(() => _remoteItems = const <HelpCenterFaqItem>[]);
      return;
    }
    final faqs = await state.loadFaqs(productId: widget.productId);
    if (!mounted) return;
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
      _expandedIds = <String>{...?_model?.initiallyExpandedIds};
    });
  }

  @override
  void didUpdateWidget(covariant HelpPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageModel != widget.pageModel) {
      _expandedIds = <String>{...?_model?.initiallyExpandedIds};
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '帮助中心', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final model = _model;
    if (model == null) {
      return const AppLoading(key: Key('help-center-loading'));
    }
    if (model.items.isEmpty) {
      return const AppEmptyState(
        key: Key('help-center-empty'),
        title: '暂无常见问题',
        message: '后台还没有配置常见问题，配置后这里会自动显示。',
      );
    }
    return CustomScrollView(
      key: const Key('help-center-scroll-view'),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: ResponsiveContent(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              6,
              AppSpacing.pageMargin,
              40,
            ),
            child: HelpCenterFaqList(
              items: model.items,
              expandedIds: _expandedIds,
              onToggle: _toggleFaq,
            ),
          ),
        ),
      ],
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
