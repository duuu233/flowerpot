import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_radius.dart';
import 'app_rich_html_parser.dart';

/// 渲染后台富文本编辑器存下来的 HTML。
///
/// 后台（flowerpot-web）的常见问题用的是 wangEditor v5，存进库里的是一段
/// HTML 片段而不是纯文本。App 这边如果直接丢给 [Text]，用户看到的就是
/// `<p>xxx</p>` 这种标签原文，所以这里把它解析成真正的排版。
///
/// 覆盖范围按 wangEditor v5 实际会吐出来的标签来定，不做通用浏览器：
/// 段落与标题、加粗/斜体/下划线/删除线、行内 `style` 里的颜色和字号、有序和
/// 无序列表、引用、分割线、链接、图片、`<pre><code>` 和表格行。命中不了的
/// 标签按「透明容器」处理——丢掉标签本身，内容照常渲染，绝不把标签写到屏幕上。
class AppRichHtml extends StatefulWidget {
  const AppRichHtml({
    required this.html,
    required this.baseStyle,
    super.key,
    this.onLinkTap,
    this.imageMaxHeight = 220,
    this.blockSpacing = 6,
  });

  /// 原始 HTML 片段。纯文本（不含标签）也能传，按换行分段渲染。
  final String html;

  /// 正文基准样式，标签样式都在它之上叠加。
  final TextStyle baseStyle;

  /// 点了 `<a href>` 的回调。不传就只上色不可点——App 里没有引入
  /// url_launcher，不假装能跳外链。
  final ValueChanged<String>? onLinkTap;

  /// 图片的最大高度，避免后台传了一张长图把整页撑开。
  final double imageMaxHeight;

  /// 段落之间的间距。
  final double blockSpacing;

  @override
  State<AppRichHtml> createState() => _AppRichHtmlState();
}

class _AppRichHtmlState extends State<AppRichHtml> {
  /// 链接手势识别器要手动释放，挂在 State 上按帧回收。
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final blocks = buildHtmlBlocks(widget.html, baseStyle: widget.baseStyle);
    if (blocks.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var index = 0; index < blocks.length; index++) {
      if (index > 0) {
        children.add(SizedBox(height: widget.blockSpacing));
      }
      children.add(_buildBlock(blocks[index]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildBlock(HtmlBlock block) {
    if (block.kind == HtmlBlockKind.divider) {
      return const Divider(height: 1, thickness: 1, color: AppColors.divider);
    }
    if (block.kind == HtmlBlockKind.image) {
      return _buildImage(block.imageUrl ?? '');
    }
    if (block.isBlank) {
      return SizedBox(height: (widget.baseStyle.fontSize ?? 12) * .6);
    }

    Widget text = Text.rich(
      TextSpan(style: widget.baseStyle, children: _spansOf(block)),
      textAlign: block.align,
    );

    if (block.kind == HtmlBlockKind.code) {
      text = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: .05),
          borderRadius: AppRadius.small,
        ),
        child: text,
      );
    } else if (block.kind == HtmlBlockKind.quote) {
      text = Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: AppColors.brandSoft, width: 3),
          ),
        ),
        child: text,
      );
    }

    final indent = block.indent * 14.0;
    final marker = block.marker;
    if (marker == null) {
      return indent > 0
          ? Padding(padding: EdgeInsets.only(left: indent), child: text)
          : text;
    }
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 20,
            child: Text(marker, style: widget.baseStyle),
          ),
          Expanded(child: text),
        ],
      ),
    );
  }

  List<InlineSpan> _spansOf(HtmlBlock block) {
    final spans = <InlineSpan>[];
    for (final piece in block.pieces) {
      final href = piece.href;
      if (href == null || href.isEmpty || widget.onLinkTap == null) {
        spans.add(TextSpan(text: piece.text, style: piece.style));
        continue;
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onLinkTap?.call(href);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(text: piece.text, style: piece.style, recognizer: recognizer),
      );
    }
    return spans;
  }

  Widget _buildImage(String url) {
    if (url.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: AppRadius.small,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.imageMaxHeight),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          errorBuilder: (context, error, stackTrace) =>
              const SizedBox.shrink(),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : SizedBox(
                  height: widget.imageMaxHeight / 2,
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
