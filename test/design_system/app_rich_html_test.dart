import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const TextStyle _base = TextStyle(fontSize: 12);

List<HtmlBlock> _blocks(String html) =>
    buildHtmlBlocks(html, baseStyle: _base);

String _textOf(HtmlBlock block) =>
    block.pieces.map((piece) => piece.text).join();

void main() {
  group('buildHtmlBlocks', () {
    test('后台富文本按标签分段，不会把标签当文字', () {
      final blocks = _blocks(
        '<p>请确认<strong>智能花盆</strong>已开机。</p><p>再点添加设备。</p>',
      );

      expect(blocks, hasLength(2));
      expect(_textOf(blocks.first), '请确认智能花盆已开机。');
      expect(_textOf(blocks.last), '再点添加设备。');
      expect(
        blocks.first.pieces.any(
          (piece) =>
              piece.text == '智能花盆' && piece.style.fontWeight == FontWeight.w600,
        ),
        isTrue,
      );
      for (final block in blocks) {
        expect(_textOf(block), isNot(contains('<')));
      }
    });

    test('有序和无序列表各自带上符号与缩进', () {
      final blocks = _blocks(
        '<ol><li>打开 App</li><li>点击添加</li></ol><ul><li>2.4GHz</li></ul>',
      );

      expect(blocks.map((block) => block.marker).toList(), <String>[
        '1.',
        '2.',
        '•',
      ]);
      expect(blocks.every((block) => block.indent == 1), isTrue);
    });

    test('列表项里嵌段落时符号仍然落在有文字的那个块上', () {
      final blocks = _blocks('<ul><li><p>第一条</p></li><li><p>第二条</p></li></ul>');

      expect(blocks, hasLength(2));
      expect(blocks.first.marker, '•');
      expect(_textOf(blocks.first), '第一条');
      expect(blocks.last.marker, '•');
    });

    test('图片、分割线和引用各自成块', () {
      final blocks = _blocks(
        '<p><img src="https://cdn.example.com/a.png"/></p>'
        '<hr/><blockquote>联系客服</blockquote>',
      );

      expect(blocks[0].kind, HtmlBlockKind.image);
      expect(blocks[0].imageUrl, 'https://cdn.example.com/a.png');
      expect(blocks[1].kind, HtmlBlockKind.divider);
      expect(blocks[2].kind, HtmlBlockKind.quote);
    });

    test('行内 style 的颜色、字号和居中都解析出来', () {
      final blocks = _blocks(
        '<p style="text-align: center;">'
        '<span style="color: rgb(225, 60, 57); font-size: 18px;">注意</span></p>',
      );

      expect(blocks.single.align, TextAlign.center);
      final piece = blocks.single.pieces.single;
      expect(piece.style.color, const Color(0xFFE13C39));
      expect(piece.style.fontSize, 18);
    });

    test('链接带上 href 并且换了颜色', () {
      final blocks = _blocks('<p>见 <a href="https://example.com">文档</a></p>');
      final link = blocks.single.pieces.firstWhere(
        (piece) => piece.text == '文档',
      );

      expect(link.href, 'https://example.com');
      expect(link.style.decoration, TextDecoration.underline);
    });

    test('实体还原，script 内容整段丢掉', () {
      final blocks = _blocks(
        '<p>A&nbsp;&amp;&nbsp;B</p><script>var a = 1;</script><p>尾</p>',
      );

      expect(blocks, hasLength(2));
      expect(_textOf(blocks.first), 'A\u00A0&\u00A0B');
      expect(_textOf(blocks.last), '尾');
    });

    test('漏闭合的 li 不会把后面的项吞进去', () {
      final blocks = _blocks('<ul><li>甲<li>乙<li>丙</ul>');

      expect(blocks.map(_textOf).toList(), <String>['甲', '乙', '丙']);
    });

    test('纯文本按换行分段，首尾空段被裁掉', () {
      expect(_blocks('第一行\n第二行').map(_textOf).toList(), <String>[
        '第一行',
        '第二行',
      ]);
      expect(_blocks('<p><br></p><p>  </p>'), isEmpty);
      expect(_blocks(''), isEmpty);
    });
  });

  testWidgets('AppRichHtml 渲染出的是排版后的文字，不是标签原文', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppRichHtml(
            html: '<p>请确认<strong>已开机</strong></p><ul><li>靠近花盆</li></ul>',
            baseStyle: _base,
          ),
        ),
      ),
    );

    expect(find.textContaining('<p>'), findsNothing);
    expect(find.textContaining('请确认已开机'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
  });
}
