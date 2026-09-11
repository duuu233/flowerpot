#!/usr/bin/env python3
"""查 Dart 源码里**跨行未闭合的字符串字面量**——不依赖 Dart SDK。

为什么要有它：这台开发机没有 Flutter/Dart 工具链，改完只能做静态自检，而此前那套
自检只数括号。2026-09-11 就栽在这上面：用脚本插代码时把 `\\n` 写成了真换行，Dart
源码里的字符串被截断成两行（`'…。` 换行 `'`），**括号完全配平**，自检全绿，直到
Windows 那边打包才报 `String starting with ' must end with '`。

括号数得再准也看不见引号。这个脚本按 Dart 的词法规则真的走一遍：区分 `'`/`"`、
三引号、`r` 前缀原始串、反斜杠转义，以及 `${...}` 插值里可以再嵌套字符串。

只读，不改写。用法：

    python3 tools/dart_string_check.py [路径...]      # 缺省扫 lib 与 test

退出码 1 表示发现问题。
"""

from __future__ import annotations

import os
import sys

_QUOTES = ("'", '"')


def scan(text: str) -> list[tuple[int, str]]:
    """返回 [(行号, 说明)]；空列表表示这个文件没问题。"""
    problems: list[tuple[int, str]] = []
    i = 0
    line = 1
    length = len(text)
    # 插值深度栈：进入 ${ 时压入当前所在字符串的状态，} 时弹回。
    while i < length:
        ch = text[i]
        if ch == '\n':
            line += 1
            i += 1
            continue
        # 注释：行注释到行尾，块注释到 */
        if ch == '/' and i + 1 < length:
            if text[i + 1] == '/':
                while i < length and text[i] != '\n':
                    i += 1
                continue
            if text[i + 1] == '*':
                i += 2
                while i + 1 < length and not (text[i] == '*' and text[i + 1] == '/'):
                    if text[i] == '\n':
                        line += 1
                    i += 1
                i += 2
                continue
        if ch in _QUOTES or (ch == 'r' and i + 1 < length and text[i + 1] in _QUOTES):
            raw = ch == 'r'
            if raw:
                i += 1
                ch = text[i]
            start_line = line
            triple = text[i:i + 3] in ("'''", '"""')
            closer = ch * 3 if triple else ch
            i += len(closer)
            closed = False
            while i < length:
                if not raw and text[i] == '\\':
                    if i + 1 < length and text[i + 1] == '\n':
                        line += 1
                    i += 2
                    continue
                if text[i] == '\n':
                    if not triple:
                        # 单引号串遇到换行 —— 就是那个 bug。
                        problems.append(
                            (
                                start_line,
                                f'{closer} 开头的字符串在本行没有闭合（跨到了下一行）。'
                                f'多半是把 \\n 写成了真换行。',
                            )
                        )
                        break
                    line += 1
                    i += 1
                    continue
                # 插值：`${` 里面可以再写字符串，交给外层循环重新按语法处理。
                if not raw and text[i] == '$' and i + 1 < length and text[i + 1] == '{':
                    depth = 0
                    i += 2
                    depth += 1
                    while i < length and depth:
                        if text[i] == '\n':
                            line += 1
                        elif text[i] == '{':
                            depth += 1
                        elif text[i] == '}':
                            depth -= 1
                        elif text[i] in _QUOTES:
                            # 插值里的嵌套字符串：跳到它的收尾引号
                            quote = text[i]
                            i += 1
                            while i < length and text[i] != quote:
                                if text[i] == '\\':
                                    i += 1
                                elif text[i] == '\n':
                                    line += 1
                                i += 1
                        i += 1
                    continue
                if text.startswith(closer, i):
                    i += len(closer)
                    closed = True
                    break
                i += 1
            if not closed and i >= length:
                problems.append((start_line, f'{closer} 开头的字符串直到文件结束都没有闭合。'))
            continue
        i += 1
    return problems


def main(argv: list[str]) -> int:
    roots = argv[1:] or ['lib', 'test']
    files: list[str] = []
    for root in roots:
        if os.path.isfile(root):
            files.append(root)
            continue
        for base, _, names in os.walk(root):
            files.extend(
                os.path.join(base, name) for name in names if name.endswith('.dart')
            )
    total = 0
    for path in sorted(files):
        with open(path, encoding='utf-8') as handle:
            for line, message in scan(handle.read()):
                print(f'{path}:{line}: {message}')
                total += 1
    if total:
        print(f'-- {total} 处未闭合字符串', file=sys.stderr)
        return 1
    print(f'OK：{len(files)} 个 Dart 文件，未发现跨行未闭合的字符串', file=sys.stderr)
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
