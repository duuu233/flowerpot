import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

/// [AppRichHtml] 用的极简 HTML 解析：把一段 HTML 片段压平成「块 + 行内片段」。
///
/// 这里刻意不引第三方 HTML 渲染库：后台富文本是 wangEditor v5，它吐出来的标签
/// 集合是固定且很小的一撮，自己解析既能跟着设计系统的字体色走，也不用为了一个
/// 帮助中心把一串传递依赖装进包里。解析器按「宽容优先」写：认不出来的标签当成
/// 透明容器（丢标签、留内容），永远不会把尖括号原样显示给用户。

/// 块的类型。除 [paragraph] 外都要额外的装饰或独立控件。
enum HtmlBlockKind { paragraph, code, quote, divider, image }

/// 一个块里的一段行内文字，样式已经解析完毕。
@immutable
class HtmlPiece {
  const HtmlPiece({required this.text, required this.style, this.href});

  final String text;
  final TextStyle style;

  /// 来自 `<a href>`，没有就是 null。
  final String? href;
}

/// 一个块级元素：段落、列表项、引用、图片或分割线。
@immutable
class HtmlBlock {
  const HtmlBlock({
    this.pieces = const <HtmlPiece>[],
    this.kind = HtmlBlockKind.paragraph,
    this.marker,
    this.indent = 0,
    this.align = TextAlign.start,
    this.imageUrl,
  });

  final List<HtmlPiece> pieces;
  final HtmlBlockKind kind;

  /// 列表项前面的符号，`•` 或 `1.`；非列表项为 null。
  final String? marker;

  /// 列表嵌套层级，用来算左缩进。
  final int indent;
  final TextAlign align;

  /// [HtmlBlockKind.image] 时的图片地址。
  final String? imageUrl;

  /// 整块没有可见文字——空段落，按行距留白处理。
  bool get isBlank => pieces.every((piece) => piece.text.trim().isEmpty);
}

/// 把 [html] 解析成块列表。[baseStyle] 是正文基准样式，所有相对字号基于它算。
///
/// [html] 不含标签时按纯文本处理：保留换行，逐行成段。
List<HtmlBlock> buildHtmlBlocks(String html, {required TextStyle baseStyle}) {
  final source = html.trim();
  if (source.isEmpty) return const <HtmlBlock>[];

  if (!_looksLikeHtml(source)) {
    return <HtmlBlock>[
      for (final line in decodeHtmlEntities(source).split('\n'))
        HtmlBlock(
          pieces: <HtmlPiece>[HtmlPiece(text: line, style: baseStyle)],
        ),
    ];
  }

  final root = _parseFragment(source);
  final builder = _BlockBuilder();
  final context = _Ctx(style: baseStyle, rootFontSize: baseStyle.fontSize ?? 14);
  _walkChildren(root, context, builder);
  builder.endBlock();
  return builder.result();
}

final RegExp _tagPattern = RegExp(r'<\s*/?\s*[a-zA-Z][^>]*>');

bool _looksLikeHtml(String source) => _tagPattern.hasMatch(source);

// ---------------------------------------------------------------------------
// 词法与语法：HTML 片段 -> 元素树
// ---------------------------------------------------------------------------

class _Element {
  _Element(this.tag, this.attributes);

  final String tag;
  final Map<String, String> attributes;

  /// 子节点是 String（文本）或 _Element（子元素）。
  final List<Object> children = <Object>[];
}

/// 没有结束标签的元素。
const Set<String> _voidTags = <String>{
  'br', 'img', 'hr', 'input', 'meta', 'link', 'source', 'col', 'area',
  'base', 'embed', 'param', 'track', 'wbr',
};

/// 内容整个丢掉的元素——它们的正文不属于文章。
const Set<String> _dropTags = <String>{
  'script', 'style', 'head', 'title', 'noscript', 'svg', 'iframe', 'video',
  'audio', 'object', 'canvas',
};

_Element _parseFragment(String source) {
  final root = _Element('#root', const <String, String>{});
  final stack = <_Element>[root];
  final length = source.length;
  var index = 0;

  while (index < length) {
    final open = source.indexOf('<', index);
    if (open < 0) {
      stack.last.children.add(source.substring(index));
      break;
    }
    if (open > index) {
      stack.last.children.add(source.substring(index, open));
    }

    if (source.startsWith('<!--', open)) {
      final end = source.indexOf('-->', open + 4);
      index = end < 0 ? length : end + 3;
      continue;
    }
    if (source.startsWith('<!', open) || source.startsWith('<?', open)) {
      final end = source.indexOf('>', open);
      index = end < 0 ? length : end + 1;
      continue;
    }
    if (source.startsWith('</', open)) {
      final end = source.indexOf('>', open);
      if (end < 0) break;
      final name = source.substring(open + 2, end).trim().toLowerCase();
      index = end + 1;
      for (var depth = stack.length - 1; depth > 0; depth--) {
        if (stack[depth].tag == name) {
          stack.removeRange(depth, stack.length);
          break;
        }
      }
      continue;
    }

    final token = _readTag(source, open);
    if (token == null) {
      // 单独一个 `<`，当普通文字。
      stack.last.children.add('<');
      index = open + 1;
      continue;
    }
    index = token.end;

    if (_dropTags.contains(token.name)) {
      index = _skipElementBody(source, token.name, index);
      continue;
    }

    // 编辑器或人工内容里常见的漏闭合：新的 <p>/<li> 意味着上一个已经结束。
    if (token.name == 'p' || token.name == 'li') {
      for (var depth = stack.length - 1; depth > 0; depth--) {
        if (stack[depth].tag == token.name) {
          stack.removeRange(depth, stack.length);
          break;
        }
        if (stack[depth].tag == 'ul' || stack[depth].tag == 'ol') break;
      }
    }

    final element = _Element(token.name, token.attributes);
    stack.last.children.add(element);
    if (token.selfClosing || _voidTags.contains(token.name)) continue;
    stack.add(element);
  }

  return root;
}

class _TagToken {
  const _TagToken(this.name, this.attributes, this.selfClosing, this.end);

  final String name;
  final Map<String, String> attributes;
  final bool selfClosing;

  /// `>` 之后的下标。
  final int end;
}

const int _space = 0x20;
const int _tab = 0x09;
const int _lineFeed = 0x0A;
const int _carriageReturn = 0x0D;
const int _formFeed = 0x0C;
const int _slash = 0x2F;
const int _greaterThan = 0x3E;
const int _equals = 0x3D;

bool _isSpaceUnit(int unit) =>
    unit == _space ||
    unit == _tab ||
    unit == _lineFeed ||
    unit == _carriageReturn ||
    unit == _formFeed;

_TagToken? _readTag(String source, int start) {
  final length = source.length;
  var index = start + 1;
  final nameStart = index;
  while (index < length) {
    final unit = source.codeUnitAt(index);
    if (_isSpaceUnit(unit) || unit == _slash || unit == _greaterThan) break;
    index++;
  }
  if (index == nameStart) return null;
  final name = source.substring(nameStart, index).toLowerCase();

  final attributes = <String, String>{};
  var selfClosing = false;

  while (index < length) {
    while (index < length && _isSpaceUnit(source.codeUnitAt(index))) {
      index++;
    }
    if (index >= length) break;
    final unit = source.codeUnitAt(index);
    if (unit == _greaterThan) {
      index++;
      break;
    }
    if (unit == _slash) {
      selfClosing = true;
      index++;
      continue;
    }

    final keyStart = index;
    while (index < length) {
      final current = source.codeUnitAt(index);
      if (_isSpaceUnit(current) ||
          current == _equals ||
          current == _slash ||
          current == _greaterThan) {
        break;
      }
      index++;
    }
    if (index == keyStart) {
      index++;
      continue;
    }
    final key = source.substring(keyStart, index).toLowerCase();

    while (index < length && _isSpaceUnit(source.codeUnitAt(index))) {
      index++;
    }
    if (index >= length || source.codeUnitAt(index) != _equals) {
      attributes[key] = '';
      continue;
    }
    index++;
    while (index < length && _isSpaceUnit(source.codeUnitAt(index))) {
      index++;
    }
    if (index >= length) break;

    final quote = source[index];
    if (quote == _doubleQuote || quote == _singleQuote) {
      final close = source.indexOf(quote, index + 1);
      if (close < 0) {
        attributes[key] = decodeHtmlEntities(source.substring(index + 1));
        index = length;
        break;
      }
      attributes[key] = decodeHtmlEntities(source.substring(index + 1, close));
      index = close + 1;
      continue;
    }

    final valueStart = index;
    while (index < length) {
      final current = source.codeUnitAt(index);
      if (_isSpaceUnit(current) || current == _greaterThan) break;
      index++;
    }
    attributes[key] = decodeHtmlEntities(source.substring(valueStart, index));
  }

  return _TagToken(name, attributes, selfClosing, index);
}

const String _doubleQuote = '"';
const String _singleQuote = "'";

/// 跳过 [name] 元素的全部正文，返回它结束标签之后的下标。
int _skipElementBody(String source, String name, int from) {
  final lower = source.toLowerCase();
  final close = lower.indexOf('</$name', from);
  if (close < 0) return source.length;
  final end = source.indexOf('>', close);
  return end < 0 ? source.length : end + 1;
}

// ---------------------------------------------------------------------------
// 语义：元素树 -> 块列表
// ---------------------------------------------------------------------------

/// 列表符号的持有者。`<li><p>正文</p></li>` 这种写法里，符号该记在真正产出文字
/// 的那个块上，所以用一次性取走的方式传下去。
class _Marker {
  _Marker(this.value);

  String? value;

  String? take() {
    final current = value;
    value = null;
    return current;
  }
}

@immutable
class _Ctx {
  const _Ctx({
    required this.style,
    required this.rootFontSize,
    this.align = TextAlign.start,
    this.indent = 0,
    this.marker,
    this.href,
    this.pre = false,
    this.kind = HtmlBlockKind.paragraph,
  });

  final TextStyle style;

  /// 正文基准字号，`em` / 标题倍数都以它为准。
  final double rootFontSize;
  final TextAlign align;
  final int indent;
  final _Marker? marker;
  final String? href;
  final bool pre;
  final HtmlBlockKind kind;

  _Ctx copyWith({
    TextStyle? style,
    TextAlign? align,
    int? indent,
    _Marker? marker,
    bool dropMarker = false,
    String? href,
    bool? pre,
    HtmlBlockKind? kind,
  }) {
    return _Ctx(
      style: style ?? this.style,
      rootFontSize: rootFontSize,
      align: align ?? this.align,
      indent: indent ?? this.indent,
      marker: dropMarker ? null : (marker ?? this.marker),
      href: href ?? this.href,
      pre: pre ?? this.pre,
      kind: kind ?? this.kind,
    );
  }
}

class _BlockBuilder {
  final List<HtmlBlock> _blocks = <HtmlBlock>[];
  List<HtmlPiece> _pieces = <HtmlPiece>[];
  HtmlBlockKind _kind = HtmlBlockKind.paragraph;
  TextAlign _align = TextAlign.start;
  int _indent = 0;
  String? _marker;

  bool get isCurrentEmpty => _pieces.isEmpty;

  void startBlock(_Ctx ctx) {
    endBlock();
    _kind = ctx.kind;
    _align = ctx.align;
    _indent = ctx.indent;
    _marker ??= ctx.marker?.take();
  }

  void add(HtmlPiece piece) {
    if (piece.text.isEmpty) return;
    _pieces.add(piece);
  }

  /// 收掉当前块。空块不落盘，但待用的列表符号会留给下一个块。
  void endBlock() {
    if (_pieces.isNotEmpty) {
      _blocks.add(
        HtmlBlock(
          pieces: List<HtmlPiece>.unmodifiable(_pieces),
          kind: _kind,
          marker: _marker,
          indent: _indent,
          align: _align,
        ),
      );
      _marker = null;
    }
    _pieces = <HtmlPiece>[];
    _kind = HtmlBlockKind.paragraph;
    _align = TextAlign.start;
    _indent = 0;
  }

  void dropPendingMarker() => _marker = null;

  void emitDivider() {
    endBlock();
    _blocks.add(const HtmlBlock(kind: HtmlBlockKind.divider));
  }

  void emitImage(String url, int indent) {
    if (url.isEmpty) return;
    endBlock();
    _blocks.add(
      HtmlBlock(kind: HtmlBlockKind.image, imageUrl: url, indent: indent),
    );
  }

  /// 去掉首尾的空段落，中间的留着——那是作者排的空行。
  List<HtmlBlock> result() {
    var start = 0;
    var end = _blocks.length;
    bool blankAt(int index) =>
        _blocks[index].kind == HtmlBlockKind.paragraph &&
        _blocks[index].isBlank;
    while (start < end && blankAt(start)) {
      start++;
    }
    while (end > start && blankAt(end - 1)) {
      end--;
    }
    return _blocks.sublist(start, end);
  }
}

/// 走成块的标签。ul/ol/pre/blockquote 另有处理，不在这里。
const Set<String> _blockTags = <String>{
  'p', 'div', 'section', 'article', 'header', 'footer', 'main', 'aside',
  'figure', 'figcaption', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'tr',
  'dt', 'dd', 'address', 'caption', 'summary',
};

const Map<String, double> _headingScale = <String, double>{
  'h1': 1.55,
  'h2': 1.38,
  'h3': 1.24,
  'h4': 1.12,
  'h5': 1.04,
  'h6': 1,
};

void _walkChildren(_Element element, _Ctx ctx, _BlockBuilder out) {
  final ordered = element.tag == 'ol';
  final unordered = element.tag == 'ul';
  var ordinal = ordered ? _startOrdinal(element) : 1;

  for (final child in element.children) {
    if (child is String) {
      _walkText(child, ctx, out);
      continue;
    }
    final node = child as _Element;
    if (node.tag == 'li' && (ordered || unordered)) {
      final marker = ordered ? '$ordinal.' : _bullet;
      ordinal++;
      _walkElement(node, ctx.copyWith(marker: _Marker(marker)), out);
      continue;
    }
    _walkElement(node, ctx, out);
  }
}

const String _bullet = '•';

int _startOrdinal(_Element element) {
  final raw = element.attributes['start'];
  if (raw == null) return 1;
  return int.tryParse(raw.trim()) ?? 1;
}

void _walkText(String raw, _Ctx ctx, _BlockBuilder out) {
  final text = ctx.pre
      ? decodeHtmlEntities(raw)
      : decodeHtmlEntities(_collapseWhitespace(raw));
  if (text.isEmpty) return;
  // 标签之间用来排版的空白不该变成行首空格。
  if (!ctx.pre && text.trim().isEmpty && out.isCurrentEmpty) return;
  out.add(HtmlPiece(text: text, style: ctx.style, href: ctx.href));
}

void _walkElement(_Element element, _Ctx parent, _BlockBuilder out) {
  final tag = element.tag;

  if (_dropTags.contains(tag)) return;
  if (tag == 'br') {
    out.add(HtmlPiece(text: '\n', style: parent.style));
    return;
  }
  if (tag == 'hr') {
    out.emitDivider();
    return;
  }
  if (tag == 'img') {
    final source =
        element.attributes['src'] ?? element.attributes['data-src'] ?? '';
    out.emitImage(source.trim(), parent.indent);
    return;
  }

  var ctx = parent.copyWith(style: _inlineStyleFor(element, parent));

  if (tag == 'a') {
    final href = element.attributes['href']?.trim();
    if (href != null && href.isNotEmpty) {
      ctx = ctx.copyWith(href: href);
    }
  }

  final align = _alignOf(element);
  if (align != null) {
    ctx = ctx.copyWith(align: align);
  }

  if (tag == 'ul' || tag == 'ol') {
    out.endBlock();
    _walkChildren(
      element,
      ctx.copyWith(indent: parent.indent + 1, dropMarker: true),
      out,
    );
    out.endBlock();
    return;
  }

  if (tag == 'pre' || tag == 'blockquote') {
    final kind = tag == 'pre' ? HtmlBlockKind.code : HtmlBlockKind.quote;
    final inner = ctx.copyWith(kind: kind, pre: tag == 'pre');
    out.startBlock(inner);
    _walkChildren(element, inner, out);
    out.endBlock();
    return;
  }

  if (_blockTags.contains(tag)) {
    out.startBlock(ctx);
    _walkChildren(element, ctx, out);
    out.endBlock();
    if (tag == 'li') {
      out.dropPendingMarker();
    }
    return;
  }

  _walkChildren(element, ctx, out);
  if (tag == 'td' || tag == 'th') {
    out.add(HtmlPiece(text: '  ', style: ctx.style));
  }
}

// ---------------------------------------------------------------------------
// 样式：标签语义 + 行内 style 声明
// ---------------------------------------------------------------------------

TextStyle _inlineStyleFor(_Element element, _Ctx ctx) {
  final tag = element.tag;
  final rootSize = ctx.rootFontSize;
  var style = ctx.style;
  final currentSize = style.fontSize ?? rootSize;

  if (tag == 'b' || tag == 'strong') {
    style = style.copyWith(fontWeight: FontWeight.w600);
  } else if (tag == 'i' || tag == 'em' || tag == 'cite' || tag == 'var') {
    style = style.copyWith(fontStyle: FontStyle.italic);
  } else if (tag == 'u' || tag == 'ins') {
    style = style.copyWith(decoration: TextDecoration.underline);
  } else if (tag == 's' || tag == 'del' || tag == 'strike') {
    style = style.copyWith(decoration: TextDecoration.lineThrough);
  } else if (tag == 'code' || tag == 'kbd' || tag == 'samp' || tag == 'pre') {
    style = style.copyWith(
      fontFamily: 'monospace',
      fontSize: currentSize * .94,
    );
  } else if (tag == 'sub' || tag == 'sup' || tag == 'small') {
    style = style.copyWith(fontSize: currentSize * .78);
  } else if (tag == 'mark') {
    style = style.copyWith(backgroundColor: const Color(0x33FFC107));
  } else if (tag == 'a') {
    style = style.copyWith(
      color: AppColors.brandDark,
      decoration: TextDecoration.underline,
    );
  } else if (tag == 'th') {
    style = style.copyWith(fontWeight: FontWeight.w600);
  } else {
    final scale = _headingScale[tag];
    if (scale != null) {
      style = style.copyWith(
        fontSize: rootSize * scale,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.35,
      );
    }
  }

  return _applyStyleAttribute(element, style, rootSize);
}

TextStyle _applyStyleAttribute(
  _Element element,
  TextStyle style,
  double rootSize,
) {
  var result = style;

  // 老式 <font color size>，后台历史内容里还会出现。
  if (element.tag == 'font') {
    final legacy = _parseCssColor(element.attributes['color'] ?? '');
    if (legacy != null) {
      result = result.copyWith(color: legacy);
    }
  }

  final raw = element.attributes['style'];
  if (raw == null || raw.trim().isEmpty) return result;
  final declarations = _parseStyleDeclarations(raw);

  final color = _parseCssColor(declarations['color'] ?? '');
  if (color != null) {
    result = result.copyWith(color: color);
  }

  final background = _parseCssColor(
    declarations['background-color'] ?? declarations['background'] ?? '',
  );
  if (background != null) {
    result = result.copyWith(backgroundColor: background);
  }

  final size = _parseCssFontSize(
    declarations['font-size'] ?? '',
    result.fontSize ?? rootSize,
  );
  if (size != null) {
    result = result.copyWith(fontSize: size);
  }

  final weight = _parseCssFontWeight(declarations['font-weight'] ?? '');
  if (weight != null) {
    result = result.copyWith(fontWeight: weight);
  }

  final fontStyle = declarations['font-style'];
  if (fontStyle == 'italic' || fontStyle == 'oblique') {
    result = result.copyWith(fontStyle: FontStyle.italic);
  } else if (fontStyle == 'normal') {
    result = result.copyWith(fontStyle: FontStyle.normal);
  }

  final decoration =
      declarations['text-decoration-line'] ??
      declarations['text-decoration'] ??
      '';
  if (decoration.contains('line-through')) {
    result = result.copyWith(decoration: TextDecoration.lineThrough);
  } else if (decoration.contains('underline')) {
    result = result.copyWith(decoration: TextDecoration.underline);
  } else if (decoration.contains('none')) {
    result = result.copyWith(decoration: TextDecoration.none);
  }

  return result;
}

TextAlign? _alignOf(_Element element) {
  String? value;
  final raw = element.attributes['style'];
  if (raw != null && raw.trim().isNotEmpty) {
    value = _parseStyleDeclarations(raw)['text-align'];
  }
  value ??= element.attributes['align']?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  if (value == 'center') return TextAlign.center;
  if (value == 'right' || value == 'end') return TextAlign.end;
  if (value == 'justify') return TextAlign.justify;
  if (value == 'left' || value == 'start') return TextAlign.start;
  return null;
}

Map<String, String> _parseStyleDeclarations(String raw) {
  final result = <String, String>{};
  for (final part in raw.split(';')) {
    final colon = part.indexOf(':');
    if (colon <= 0) continue;
    final key = part.substring(0, colon).trim().toLowerCase();
    final value = part.substring(colon + 1).trim().toLowerCase();
    if (key.isEmpty || value.isEmpty) continue;
    result[key] = value;
  }
  return result;
}

FontWeight? _parseCssFontWeight(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return null;
  if (value == 'bold' || value == 'bolder') return FontWeight.w600;
  if (value == 'normal' || value == 'lighter') return FontWeight.w400;
  final numeric = int.tryParse(value);
  if (numeric == null) return null;
  if (numeric >= 600) return FontWeight.w600;
  if (numeric >= 500) return FontWeight.w500;
  return FontWeight.w400;
}

final RegExp _lengthPattern = RegExp(r'^(-?[0-9]*\.?[0-9]+)(px|pt|em|rem|%)?$');

double? _parseCssFontSize(String raw, double current) {
  final match = _lengthPattern.firstMatch(raw.trim().toLowerCase());
  if (match == null) return null;
  final number = double.tryParse(match.group(1) ?? '');
  if (number == null || number <= 0) return null;
  final unit = match.group(2);
  double size;
  if (unit == 'pt') {
    size = number * 4 / 3;
  } else if (unit == 'em' || unit == 'rem') {
    size = current * number;
  } else if (unit == '%') {
    size = current * number / 100;
  } else {
    size = number;
  }
  return size.clamp(8, 40).toDouble();
}

const Map<String, int> _namedColors = <String, int>{
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
  'red': 0xFFFF0000,
  'green': 0xFF008000,
  'blue': 0xFF0000FF,
  'gray': 0xFF808080,
  'grey': 0xFF808080,
  'silver': 0xFFC0C0C0,
  'orange': 0xFFFFA500,
  'yellow': 0xFFFFFF00,
  'purple': 0xFF800080,
  'pink': 0xFFFFC0CB,
  'brown': 0xFFA52A2A,
  'cyan': 0xFF00FFFF,
  'magenta': 0xFFFF00FF,
  'gold': 0xFFFFD700,
  'navy': 0xFF000080,
  'teal': 0xFF008080,
  'lime': 0xFF00FF00,
  'maroon': 0xFF800000,
  'olive': 0xFF808000,
};

final RegExp _rgbPattern = RegExp(
  r'^rgba?\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*(?:,\s*([0-9.]+)\s*)?\)$',
);

Color? _parseCssColor(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty || value == 'transparent' || value == 'inherit') {
    return null;
  }

  final named = _namedColors[value];
  if (named != null) return Color(named);

  if (value.startsWith('#')) {
    final hex = value.substring(1);
    if (hex.length == 3) {
      final expanded = hex.split('').map((char) => '$char$char').join();
      final parsed = int.tryParse(expanded, radix: 16);
      return parsed == null ? null : Color(0xFF000000 | parsed);
    }
    if (hex.length == 6) {
      final parsed = int.tryParse(hex, radix: 16);
      return parsed == null ? null : Color(0xFF000000 | parsed);
    }
    if (hex.length == 8) {
      // CSS 是 RRGGBBAA，Flutter 要 AARRGGBB。
      final rgb = int.tryParse(hex.substring(0, 6), radix: 16);
      final alpha = int.tryParse(hex.substring(6), radix: 16);
      if (rgb == null || alpha == null) return null;
      return Color((alpha << 24) | rgb);
    }
    return null;
  }

  final match = _rgbPattern.firstMatch(value);
  if (match == null) return null;
  final red = double.tryParse(match.group(1) ?? '')?.round();
  final green = double.tryParse(match.group(2) ?? '')?.round();
  final blue = double.tryParse(match.group(3) ?? '')?.round();
  if (red == null || green == null || blue == null) return null;
  final opacity = double.tryParse(match.group(4) ?? '1') ?? 1;
  final alpha = (opacity.clamp(0, 1) * 255).round();
  return Color.fromARGB(
    alpha,
    red.clamp(0, 255).toInt(),
    green.clamp(0, 255).toInt(),
    blue.clamp(0, 255).toInt(),
  );
}

// ---------------------------------------------------------------------------
// 文本清洗
// ---------------------------------------------------------------------------

final RegExp _whitespaceRun = RegExp(r'[ \t\r\n\f]+');

/// HTML 里连续空白等价于一个空格。注意这里只收敛 ASCII 空白，`&nbsp;` 此刻还是
/// 实体原文，解码之后的不换行空格会被原样保留。
String _collapseWhitespace(String value) =>
    value.replaceAll(_whitespaceRun, ' ');

const Map<String, String> _namedEntities = <String, String>{
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'middot': '·',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'laquo': '«',
  'raquo': '»',
  'bull': '•',
  'times': '×',
  'divide': '÷',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'deg': '°',
  'plusmn': '±',
  'sect': '§',
  'para': '¶',
  'euro': '€',
  'pound': '£',
  'yen': '¥',
  'cent': '¢',
  'larr': '←',
  'rarr': '→',
  'uarr': '↑',
  'darr': '↓',
  'ensp': ' ',
  'emsp': ' ',
  'thinsp': ' ',
  'zwnj': '‌',
  'zwj': '‍',
  'shy': '',
};

final RegExp _entityPattern = RegExp(
  r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]{1,31});',
);

/// 把 HTML 实体还原成字符。认不出的实体原样留着，不会吞掉内容。
String decodeHtmlEntities(String value) {
  if (!value.contains('&')) return value;
  return value.replaceAllMapped(_entityPattern, (match) {
    final body = match.group(1) ?? '';
    if (body.startsWith('#')) {
      final isHex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final digits = isHex ? body.substring(2) : body.substring(1);
      final code = int.tryParse(digits, radix: isHex ? 16 : 10);
      if (code == null || code <= 0 || code > 0x10FFFF) return match[0] ?? '';
      return String.fromCharCode(code);
    }
    return _namedEntities[body.toLowerCase()] ?? match[0] ?? '';
  });
}
