import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
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
  const HelpPage({super.key, this.pageModel});

  /// 测试和预览用。传了就不请求后台。
  final HelpCenterPageModel? pageModel;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  /// 列表下方打印接口调试信息（2026-09-14 产品：「直接在下方打印调了哪个接口、请求参数是什么、
  /// 接口返回什么，我需要看下打印的日志」）。**联调期开着，数据问题查清后改成 false。**
  static const bool _showApiTrace = true;

  Set<String> _expandedIds = <String>{};
  bool _requested = false;

  /// 最近一次拉常见问题的记录，见 `FlowerpotState.faqTrace`。
  String _trace = '';

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

  Future<void> _loadFaqs() async {
    final state = FlowerpotScope.maybeOf(context);
    if (state == null) {
      setState(() => _remoteItems = const <HelpCenterFaqItem>[]);
      return;
    }
    final faqs = await state.loadFaqs();
    if (!mounted) return;
    setState(() {
      _trace = state.faqTrace;
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
    final trace = _showApiTrace && _trace.isNotEmpty
        ? _ApiTraceBox(text: _trace)
        : null;
    if (model.items.isEmpty) {
      const empty = AppEmptyState(
        key: Key('help-center-empty'),
        title: '暂无常见问题',
        message: '后台还没有配置常见问题，配置后这里会自动显示。',
      );
      if (trace == null) return empty;
      // 空态也要把调试信息画出来——没数据的时候恰恰最需要看接口到底回了什么。
      return ListView(
        key: const Key('help-center-scroll-view'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageMargin,
          AppSpacing.lg,
          AppSpacing.pageMargin,
          40,
        ),
        children: <Widget>[empty, trace],
      );
    }
    return CustomScrollView(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                HelpCenterFaqList(
                  items: model.items,
                  expandedIds: _expandedIds,
                  onToggle: _toggleFaq,
                ),
                if (trace != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  trace,
                ],
              ],
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

/// 帮助中心列表下方的接口调试信息：调了哪个接口、请求参数、请求头、返回体、App 解析结果。
///
/// 等宽字体、可选中；右上角「复制」把整段放进剪贴板，方便直接发给后端对照。
class _ApiTraceBox extends StatelessWidget {
  const _ApiTraceBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('help-center-api-trace'),
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.textTertiary.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '接口调试信息（联调期显示）',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                key: const Key('help-center-api-trace-copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    showAppMessage(context, '已复制', tone: AppMessageTone.success);
                  }
                },
                child: const Text('复制'),
              ),
            ],
          ),
          SelectableText(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.45,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
