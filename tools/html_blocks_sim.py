#!/usr/bin/env python3
"""按 app_rich_html_parser.dart 的算法转写一份 HTML -> 块列表，用来在没有 Dart
工具链的机器上验证解析控制流（标签栈、列表符号传递、空块裁剪）。

只转写结构部分，不转写 TextStyle 的解析——样式那半是纯查表，结构这半才是会出
bug 的地方。改了 Dart 那边的 _parseFragment / _walkElement / _BlockBuilder 之后
跑一下这个脚本，确认块划分没跑偏。

    python3 tools/html_blocks_sim.py            # 跑内置样例
    python3 tools/html_blocks_sim.py file.html  # 跑指定文件
"""
from __future__ import annotations

import sys
import re
import html as html_module

VOID_TAGS = {
    "br", "img", "hr", "input", "meta", "link", "source", "col", "area",
    "base", "embed", "param", "track", "wbr",
}
DROP_TAGS = {
    "script", "style", "head", "title", "noscript", "svg", "iframe", "video",
    "audio", "object", "canvas",
}
BLOCK_TAGS = {
    "p", "div", "section", "article", "header", "footer", "main", "aside",
    "figure", "figcaption", "h1", "h2", "h3", "h4", "h5", "h6", "li", "tr",
    "dt", "dd", "address", "caption", "summary",
}
TAG_PATTERN = re.compile(r"<\s*/?\s*[a-zA-Z][^>]*>")
WHITESPACE_RUN = re.compile(r"[ \t\r\n\f]+")


class Element:
    def __init__(self, tag: str, attributes: dict[str, str]) -> None:
        self.tag = tag
        self.attributes = attributes
        self.children: list[object] = []


def read_tag(source: str, start: int):
    length = len(source)
    index = start + 1
    name_start = index
    while index < length and source[index] not in " \t\r\n\f/>":
        index += 1
    if index == name_start:
        return None
    name = source[name_start:index].lower()
    attributes: dict[str, str] = {}
    self_closing = False
    while index < length:
        while index < length and source[index] in " \t\r\n\f":
            index += 1
        if index >= length:
            break
        char = source[index]
        if char == ">":
            index += 1
            break
        if char == "/":
            self_closing = True
            index += 1
            continue
        key_start = index
        while index < length and source[index] not in " \t\r\n\f=/>":
            index += 1
        if index == key_start:
            index += 1
            continue
        key = source[key_start:index].lower()
        while index < length and source[index] in " \t\r\n\f":
            index += 1
        if index >= length or source[index] != "=":
            attributes[key] = ""
            continue
        index += 1
        while index < length and source[index] in " \t\r\n\f":
            index += 1
        if index >= length:
            break
        quote = source[index]
        if quote in ('"', "'"):
            close = source.find(quote, index + 1)
            if close < 0:
                attributes[key] = source[index + 1:]
                index = length
                break
            attributes[key] = html_module.unescape(source[index + 1:close])
            index = close + 1
            continue
        value_start = index
        while index < length and source[index] not in " \t\r\n\f>":
            index += 1
        attributes[key] = html_module.unescape(source[value_start:index])
    return name, attributes, self_closing, index


def skip_element_body(source: str, name: str, start: int) -> int:
    lower = source.lower()
    close = lower.find("</" + name, start)
    if close < 0:
        return len(source)
    end = source.find(">", close)
    return len(source) if end < 0 else end + 1


def parse_fragment(source: str) -> Element:
    root = Element("#root", {})
    stack = [root]
    length = len(source)
    index = 0
    while index < length:
        open_at = source.find("<", index)
        if open_at < 0:
            stack[-1].children.append(source[index:])
            break
        if open_at > index:
            stack[-1].children.append(source[index:open_at])
        if source.startswith("<!--", open_at):
            end = source.find("-->", open_at + 4)
            index = length if end < 0 else end + 3
            continue
        if source.startswith("<!", open_at) or source.startswith("<?", open_at):
            end = source.find(">", open_at)
            index = length if end < 0 else end + 1
            continue
        if source.startswith("</", open_at):
            end = source.find(">", open_at)
            if end < 0:
                break
            name = source[open_at + 2:end].strip().lower()
            index = end + 1
            for depth in range(len(stack) - 1, 0, -1):
                if stack[depth].tag == name:
                    del stack[depth:]
                    break
            continue
        token = read_tag(source, open_at)
        if token is None:
            stack[-1].children.append("<")
            index = open_at + 1
            continue
        name, attributes, self_closing, index = token
        if name in DROP_TAGS:
            index = skip_element_body(source, name, index)
            continue
        if name in ("p", "li"):
            for depth in range(len(stack) - 1, 0, -1):
                if stack[depth].tag == name:
                    del stack[depth:]
                    break
                if stack[depth].tag in ("ul", "ol"):
                    break
        element = Element(name, attributes)
        stack[-1].children.append(element)
        if self_closing or name in VOID_TAGS:
            continue
        stack.append(element)
    return root


class Marker:
    def __init__(self, value):
        self.value = value

    def take(self):
        current = self.value
        self.value = None
        return current


class BlockBuilder:
    def __init__(self) -> None:
        self.blocks: list[dict] = []
        self._pieces: list[str] = []
        self._kind = "paragraph"
        self._align = "start"
        self._indent = 0
        self._marker = None

    @property
    def is_current_empty(self) -> bool:
        return not self._pieces

    def start_block(self, ctx) -> None:
        self.end_block()
        self._kind = ctx["kind"]
        self._align = ctx["align"]
        self._indent = ctx["indent"]
        if self._marker is None and ctx["marker"] is not None:
            self._marker = ctx["marker"].take()

    def add(self, text: str) -> None:
        if text:
            self._pieces.append(text)

    def end_block(self) -> None:
        if self._pieces:
            self.blocks.append({
                "text": "".join(self._pieces),
                "kind": self._kind,
                "marker": self._marker,
                "indent": self._indent,
                "align": self._align,
            })
            self._marker = None
        self._pieces = []
        self._kind = "paragraph"
        self._align = "start"
        self._indent = 0

    def drop_pending_marker(self) -> None:
        self._marker = None

    def emit_divider(self) -> None:
        self.end_block()
        self.blocks.append({"kind": "divider", "text": "", "marker": None,
                            "indent": 0, "align": "start"})

    def emit_image(self, url: str, indent: int) -> None:
        if not url:
            return
        self.end_block()
        self.blocks.append({"kind": "image", "text": url, "marker": None,
                            "indent": indent, "align": "start"})

    def result(self) -> list[dict]:
        start, end = 0, len(self.blocks)

        def blank_at(i: int) -> bool:
            block = self.blocks[i]
            return block["kind"] == "paragraph" and not block["text"].strip()

        while start < end and blank_at(start):
            start += 1
        while end > start and blank_at(end - 1):
            end -= 1
        return self.blocks[start:end]


def ctx_of(align="start", indent=0, marker=None, href=None, pre=False,
           kind="paragraph"):
    return {"align": align, "indent": indent, "marker": marker, "href": href,
            "pre": pre, "kind": kind}


def walk_children(element: Element, ctx, out: BlockBuilder) -> None:
    ordered = element.tag == "ol"
    unordered = element.tag == "ul"
    ordinal = int(element.attributes.get("start", "1") or 1) if ordered else 1
    for child in element.children:
        if isinstance(child, str):
            walk_text(child, ctx, out)
            continue
        if child.tag == "li" and (ordered or unordered):
            marker = f"{ordinal}." if ordered else "•"
            ordinal += 1
            walk_element(child, {**ctx, "marker": Marker(marker)}, out)
            continue
        walk_element(child, ctx, out)


def walk_text(raw: str, ctx, out: BlockBuilder) -> None:
    text = html_module.unescape(raw if ctx["pre"] else WHITESPACE_RUN.sub(" ", raw))
    if not text:
        return
    if not ctx["pre"] and not text.strip() and out.is_current_empty:
        return
    out.add(text)


def walk_element(element: Element, parent, out: BlockBuilder) -> None:
    tag = element.tag
    if tag in DROP_TAGS:
        return
    if tag == "br":
        out.add("\n")
        return
    if tag == "hr":
        out.emit_divider()
        return
    if tag == "img":
        source = element.attributes.get("src") or element.attributes.get("data-src") or ""
        out.emit_image(source.strip(), parent["indent"])
        return

    ctx = dict(parent)
    if tag == "a":
        href = (element.attributes.get("href") or "").strip()
        if href:
            ctx["href"] = href

    if tag in ("ul", "ol"):
        out.end_block()
        walk_children(element, {**ctx, "indent": parent["indent"] + 1,
                               "marker": None}, out)
        out.end_block()
        return

    if tag in ("pre", "blockquote"):
        kind = "code" if tag == "pre" else "quote"
        inner = {**ctx, "kind": kind, "pre": tag == "pre"}
        out.start_block(inner)
        walk_children(element, inner, out)
        out.end_block()
        return

    if tag in BLOCK_TAGS:
        out.start_block(ctx)
        walk_children(element, ctx, out)
        out.end_block()
        if tag == "li":
            out.drop_pending_marker()
        return

    walk_children(element, ctx, out)
    if tag in ("td", "th"):
        out.add("  ")


def build_html_blocks(source: str) -> list[dict]:
    source = source.strip()
    if not source:
        return []
    if not TAG_PATTERN.search(source):
        return [{"text": line, "kind": "paragraph", "marker": None,
                 "indent": 0, "align": "start"}
                for line in html_module.unescape(source).split("\n")]
    root = parse_fragment(source)
    out = BlockBuilder()
    walk_children(root, ctx_of(), out)
    out.end_block()
    return out.result()


SAMPLES = {
    "wangEditor 典型输出": (
        '<p>请确认<strong>智能花盆</strong>已开机。</p><p><br></p>'
        '<p style="text-align: center;">'
        '<span style="color: rgb(225, 60, 57); font-size: 18px;">注意事项</span></p>'
        '<ol><li>打开 App</li><li>点击<em>添加设备</em></li></ol>'
        '<ul><li>2.4GHz Wi-Fi</li><li>定位权限</li></ul>'
        '<p><img src="https://cdn.example.com/a.png" alt="示意图" style="width: 100%;"/></p>'
        '<blockquote>若仍搜索不到，请联系客服。</blockquote>'
        '<p>更多见 <a href="https://example.com/faq">帮助文档</a>&nbsp;。</p>'
    ),
    "列表项里套段落": '<ul><li><p>第一条</p></li><li><p>第二条</p></li></ul>',
    "漏闭合的 li": '<ul><li>甲<li>乙<li>丙</ul>',
    "脚本与注释": '<p>正文</p><script>var a = "<p>假的</p>";</script><!-- 注释 --><p>结尾</p>',
    "嵌套列表": '<ul><li>外层<ul><li>内层</li></ul></li></ul>',
    "纯文本兜底": '第一行\n第二行\n第三行',
    "表格行": '<table><tbody><tr><td>湿度</td><td>45%</td></tr></tbody></table>',
    "分割线与标题": '<h2>标题</h2><hr/><p>正文</p>',
    "空内容": '<p><br></p><p>  </p>',
}


def render(blocks: list[dict]) -> None:
    if not blocks:
        print("    (空)")
        return
    for block in blocks:
        marker = block["marker"] or ""
        prefix = "  " * block["indent"]
        label = block["kind"]
        text = block["text"].replace("\n", "\\n")
        print(f"    [{label:9}] {prefix}{marker}{text}")


def main() -> int:
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8") as handle:
            render(build_html_blocks(handle.read()))
        return 0
    for name, sample in SAMPLES.items():
        print(f"== {name}")
        render(build_html_blocks(sample))
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
