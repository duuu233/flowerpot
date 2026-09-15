#!/usr/bin/env python3
"""查 Dart 源码里**三元表达式分支中的空安全下标 `?[`**——不依赖 Dart SDK。

为什么要有它：2026-09-15 `state.dart` 写了

    final live = range == ReportRange.day
        ? _liveSamples[deviceId]?[metric] ?? const <double>[]
        : const <double>[];

Dart 解析器把分支里的 `?[` 当成了嵌套三元的 `?`，Windows 打包报
`Expected ':' before this`。括号、引号、私有成员几个自检全绿，照样过不了编译。

判定（启发式，按 dart format 的排版）：先去掉字符串和注释，再看
- 以三元分支 `? ` 开头的行里出现 `?[`；
- 或同一行里先出现独立的 ` ? `、后面跟着 `?[`、再后面有 ` : `。

改法：先把 `map[a]` 取到局部变量里判空，分支里不写 `?[`。

只读，不改写。用法：

    python3 tools/dart_ternary_null_index_check.py [路径...]   # 缺省扫 lib 与 test

退出码 1 表示发现问题。
"""

from __future__ import annotations

import os
import re
import sys

_TERNARY_LINE = re.compile(r"^\s*\?\s")
_INLINE = re.compile(r"\s\?\s.*\?\[.*\s:\s")


def strip_code(text: str) -> str:
    """把字符串内容和注释换成空格，保留换行，行号不变。"""
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(c if c == "\n" else " " for c in text[i:j]))
            i = j
            continue
        if ch in ("'", '"'):
            raw = i > 0 and text[i - 1] == "r"
            triple = text.startswith(ch * 3, i)
            quote = ch * 3 if triple else ch
            j = i + len(quote)
            while j < n and not text.startswith(quote, j):
                if text[j] == "\\" and not raw:
                    j += 2
                    continue
                if not triple and text[j] == "\n":
                    break
                j += 1
            j = min(n, j + len(quote))
            out.append(quote + "".join(c if c == "\n" else " " for c in text[i + len(quote):j - len(quote)]) + quote)
            i = j
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def scan(text: str) -> list[int]:
    problems: list[int] = []
    for number, line in enumerate(strip_code(text).split("\n"), start=1):
        if "?[" not in line:
            continue
        if _TERNARY_LINE.match(line) or _INLINE.search(line):
            problems.append(number)
    return problems


def dart_files(paths: list[str]) -> list[str]:
    files: list[str] = []
    for path in paths:
        if os.path.isfile(path):
            files.append(path)
            continue
        for root, _, names in os.walk(path):
            files.extend(os.path.join(root, name) for name in names if name.endswith(".dart"))
    return sorted(files)


def main() -> int:
    paths = sys.argv[1:] or [p for p in ("lib", "test") if os.path.isdir(p)]
    files = dart_files(paths)
    found = 0
    for path in files:
        with open(path, encoding="utf-8") as handle:
            for line in scan(handle.read()):
                print(f"{path}:{line}: 三元分支里用了 `?[`，解析器会当成嵌套三元——先取到局部变量再判空")
                found += 1
    if found:
        print(f"发现 {found} 处")
        return 1
    print(f"OK：{len(files)} 个 Dart 文件，三元分支里没有 `?[`")
    return 0


if __name__ == "__main__":
    sys.exit(main())
