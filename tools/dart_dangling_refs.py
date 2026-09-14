#!/usr/bin/env python3
"""找 Dart 里「用了某个私有成员，但它不属于当前类」的引用。

为什么要它：本机没有 Flutter / Dart 工具链，`flutter analyze` 跑不了，这类错误会
一路带到打包才炸。2026-09-12 就踩了一次——把植物详情页拆成 StatefulWidget 之后，
调试行留在了 `_PlantBasicInfoCard` 里，但它读的 `_loading` / `_detail` 是
`_PlantDetailPageState` 的字段，编译期才报 "The getter '_loading' isn't defined"。

Dart 里 `_foo` 是**库私有**：类体里一个光秃秃的 `_foo`，只能解析到本类（或同文件里
的父类 / mixin）的成员、局部变量，或者库级声明。所以「它是**别的类**的成员，而本类
和库级都没有」就一定是错的——这正是这个脚本报的唯一一种情况，不猜别的，力求零误报。

    python3 tools/dart_dangling_refs.py            # 扫 lib 和 test
    python3 tools/dart_dangling_refs.py lib/src/x.dart
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# 去掉注释和字符串，避免把注释里的 `[_loading]` 当成引用。
def strip_comments_and_strings(src: str) -> str:
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            end = n if j < 0 else j + 2
            out.append("\n" * src.count("\n", i, end))
            i = end
            continue
        if c in ('"', "'"):
            raw = i > 0 and src[i - 1] == "r"
            triple = src[i:i + 3] == c * 3
            quote = c * 3 if triple else c
            i += len(quote)
            while i < n:
                if not raw and src[i] == "\\":
                    i += 2
                    continue
                if src.startswith(quote, i):
                    i += len(quote)
                    break
                # 插值里的表达式要留着，它是真代码。
                if src[i] == "$" and i + 1 < n and src[i + 1] == "{":
                    depth, j = 0, i + 1
                    while j < n:
                        if src[j] == "{":
                            depth += 1
                        elif src[j] == "}":
                            depth -= 1
                            if depth == 0:
                                break
                        j += 1
                    out.append(src[i + 2:j])
                    i = j + 1
                    continue
                if src[i] == "\n":
                    out.append("\n")
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


CLASS_HEAD = re.compile(
    r"\b(?:abstract\s+|base\s+|final\s+|interface\s+|sealed\s+|mixin\s+)*"
    r"(?:class|mixin|extension|enum)\s+(\w+)([^{;]*)\{"
)
PRIVATE = re.compile(r"(?<![\w.$])(_\w+)")


class ClassBlock:
    def __init__(self, name: str, header: str, body: str, offset: int) -> None:
        self.name = name
        self.header = header
        self.body = body
        self.offset = offset
        self.parents = set(re.findall(r"\b(\w+)", header))


def find_classes(text: str) -> list[ClassBlock]:
    blocks: list[ClassBlock] = []
    for match in CLASS_HEAD.finditer(text):
        start = match.end()          # `{` 之后
        depth = 1
        i = start
        while i < len(text) and depth:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
            i += 1
        blocks.append(ClassBlock(match.group(1), match.group(2), text[start:i - 1], start))
    return blocks


def member_declarations(body: str) -> set[str]:
    """类体里声明出来的私有名字：字段、方法、getter/setter、this._x 构造参数。"""
    names: set[str] = set()
    # 字段：`final bool _loading = false;` / `int? _n;` / `static const _k = 1;`
    for m in re.finditer(r"(?:^|[;{}])\s*(?:@\w+\s*)*[\w<>,\s\?\[\]]*?(_\w+)\s*(?:=[^=]|;)", body):
        names.add(m.group(1))
    # 方法 / 构造：`void _open(` `Future<void> _load(` `_Foo._(`
    for m in re.finditer(r"(?:^|[;{}\)])\s*(?:@\w+\s*)*[\w<>,\s\?\[\]]*?(_\w+)\s*\(", body):
        names.add(m.group(1))
    # getter / setter
    names.update(re.findall(r"\b(?:get|set)\s+(_\w+)", body))
    # 构造函数里的 `this._x`
    names.update(re.findall(r"this\.(_\w+)", body))
    # 局部变量、形参、catch 变量等，凡是在本类体里声明过的都算——宁可漏报不误报。
    names.update(re.findall(r"\b(?:final|const|var|late)\s+[\w<>,\s\?\[\]]*?(_\w+)\b", body))
    return names


def library_level_names(text: str, classes: list[ClassBlock]) -> set[str]:
    """库级私有名字：顶层类型、顶层函数和顶层变量。"""
    masked = list(text)
    for block in classes:
        for i in range(block.offset, block.offset + len(block.body)):
            masked[i] = " "
    top = "".join(masked)
    names: set[str] = set()
    names.update(re.findall(r"\b(?:class|mixin|extension|enum|typedef)\s+(_\w+)", text))
    names.update(re.findall(r"(?:^|[;}])\s*(?:@\w+\s*)*[\w<>,\s\?\[\]]*?(_\w+)\s*[=;(]", top))
    return names


def check(path: Path) -> list[str]:
    raw = path.read_text(encoding="utf-8")
    if re.search(r"^\s*part\s+of\b", raw, re.M):
        return []          # part 文件跨文件共享作用域，单文件判不了
    text = strip_comments_and_strings(raw)
    classes = find_classes(text)
    if not classes:
        return []
    by_name = {block.name: block for block in classes}
    declared = {block.name: member_declarations(block.body) for block in classes}
    library = library_level_names(text, classes)

    def visible(block: ClassBlock, seen: set[str]) -> set[str]:
        """本类 + 同文件里的父类 / mixin 的成员。"""
        if block.name in seen:
            return set()
        seen.add(block.name)
        names = set(declared[block.name])
        for parent in block.parents:
            if parent in by_name:
                names |= visible(by_name[parent], seen)
        return names

    # 哪些名字是「某个类的成员」——只有这种才可能是跨类误用。
    owned: dict[str, set[str]] = {}
    for block in classes:
        for name in declared[block.name]:
            owned.setdefault(name, set()).add(block.name)

    problems: list[str] = []
    for block in classes:
        mine = visible(block, set())
        for match in PRIVATE.finditer(block.body):
            name = match.group(1)
            if name in mine or name in library or name in by_name:
                continue
            holders = owned.get(name)
            if not holders or block.name in holders:
                continue
            line = text.count("\n", 0, block.offset + match.start()) + 1
            problems.append(
                f"{path}:{line}: 类 {block.name} 用了 {name}，"
                f"但它是 {'/'.join(sorted(holders))} 的成员"
            )
    return problems


def main(argv: list[str]) -> int:
    targets = [Path(a) for a in argv[1:]] or [Path("lib"), Path("test")]
    files: list[Path] = []
    for target in targets:
        if target.is_dir():
            files.extend(sorted(target.rglob("*.dart")))
        elif target.suffix == ".dart":
            files.append(target)
    problems: list[str] = []
    for path in files:
        problems.extend(check(path))
    if problems:
        print("发现跨类引用私有成员：")
        for line in problems:
            print("  " + line)
        return 1
    print(f"OK：{len(files)} 个 Dart 文件，未发现跨类引用私有成员")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
