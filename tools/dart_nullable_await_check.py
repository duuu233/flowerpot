#!/usr/bin/env python3
"""检查「可空返回值没判空就用」——只盯**已知会返回 null 的辅助函数**。

为什么要它：本机没有 Dart 工具链，`flutter analyze` 跑不了，这类错误一路带到打包
才炸。2026-09-12 就踩了一次——`withBlockingProgress` 返回 `T?`（null 表示页面已经
不在了），八个调用点里有一个忘了判空，编译期报
`The argument type 'ActionResult?' can't be assigned to the parameter type 'ActionResult'`。

括号配平、字符串闭合、跨类引用那三个脚本都是词法/作用域层面的，看不见类型。这个脚本
不做类型推导，只做一件很窄的事：**这些函数的返回值，赋给变量之后第一次被用到时，
必须是一次判空**。判空的形式认这几种：

    if (x == null) / if (x != null) / x == null / x != null / x?.foo / x ?? y / x!

其余一律报出来。只认名单里的函数，所以不会到处误报；新增了同类辅助函数就往
[NULLABLE_HELPERS] 里加一行。

    python3 tools/dart_nullable_await_check.py            # 扫 lib 和 test
    python3 tools/dart_nullable_await_check.py lib/a.dart
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# 已知返回可空的辅助函数。新增同类的就加在这里。
NULLABLE_HELPERS = (
    "withBlockingProgress",
    # 定制动画页自己的一层包装，透传 withBlockingProgress 的可空返回。
    "_run",
)

ASSIGN = re.compile(
    r"\b(?:final|var)\s+(\w+)\s*=\s*await\s+(" + "|".join(NULLABLE_HELPERS) + r")\s*\(",
)

# 往后最多看这么多行找第一次使用。一个方法体通常远短于这个数。
LOOKAHEAD = 60


def strip_comments(src: str) -> str:
    """去掉注释，保留行数——注释里提到变量名不算使用。"""
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith("//", i):
            while i < n and src[i] != "\n":
                i += 1
            continue
        if src.startswith("/*", i):
            end = src.find("*/", i + 2)
            end = n if end < 0 else end + 2
            out.append("\n" * src.count("\n", i, end))
            i = end
            continue
        out.append(src[i])
        i += 1
    return "".join(out)


def guarded(line: str, name: str) -> bool:
    """这一行里对 name 的使用是不是一次判空。"""
    patterns = (
        rf"\b{name}\s*==\s*null",
        rf"\b{name}\s*!=\s*null",
        rf"\b{name}\s*\?\.",
        rf"\b{name}\s*\?\?",
        rf"\b{name}\s*!",
    )
    return any(re.search(p, line) for p in patterns)


def check(path: Path) -> list[str]:
    text = strip_comments(path.read_text(encoding="utf-8"))
    lines = text.split("\n")
    problems: list[str] = []

    for index, line in enumerate(lines):
        match = ASSIGN.search(line)
        if match is None:
            continue
        name, helper = match.group(1), match.group(2)
        used = re.compile(rf"(?<![\w$]){name}(?![\w$])")
        # 从赋值语句之后找第一次使用。赋值本身可能跨多行（括号还没闭合），
        # 所以先跳过到这条语句结束——以出现 `);` 为界，够用且不会误判。
        cursor = index
        depth = line.count("(") - line.count(")")
        while depth > 0 and cursor + 1 < len(lines):
            cursor += 1
            depth += lines[cursor].count("(") - lines[cursor].count(")")

        for offset in range(cursor + 1, min(cursor + 1 + LOOKAHEAD, len(lines))):
            following = lines[offset]
            if not used.search(following):
                continue
            if guarded(following, name):
                break
            problems.append(
                f"{path}:{offset + 1}: {name} 来自 {helper}（返回可空），"
                f"第一次使用没有判空"
            )
            break
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
        print("发现可空返回值未判空：")
        for line in problems:
            print("  " + line)
        return 1
    print(f"OK：{len(files)} 个 Dart 文件，可空返回值都判过空")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
