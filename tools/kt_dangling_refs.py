#!/usr/bin/env python3
"""Kotlin 悬空引用检查（按函数作用域）。

## 为什么有这个脚本

本机没有 Kotlin 工具链，`MainActivity.kt` 的改动一律编译不了。2026-09-11 一轮大删除
（配网四条路砍成一条）之后**连续三次打包失败**，三次都是同一类 bug：

| 次 | 报错 | 根因 |
| --- | --- | --- |
| 1 | `34:2 Expecting a top level declaration` ×几十条 | 删除脚本把 `/**` 写成了 `//**` |
| 2 | `Unresolved reference 'currentSsidForLog'` | 该函数夹在被删区间里，一起删了，但仍有 2 处在用 |
| 3 | `Unresolved reference 'requested'` | 局部变量随模式分支一起删了，但同函数后面还有 2 处在用 |

而当时的自检（括号配平、被删符号 grep、枚举引用）**三次全部通过**——括号数量和符号残留
根本覆盖不到这一类。这个脚本补的就是这一项。

## 它做什么

按**函数作用域**找出「用了但在可见范围内没有声明」的小写开头标识符：
文件级成员（fun/val/var）∪ 该函数自己的参数与局部变量。第 3 类 bug 必须按作用域才抓得到
——`requested` 在另一个函数里确实声明过，全文件扁平地查会漏掉。

## 它不做什么

不是类型检查器，也不解析 import。输出是**候选**，需要人工确认哪些是外部 API
（`WifiManager`、`JSONObject` 这类以大写开头的已被排除；小写的外部调用靠白名单）。
目标是「改完之后输出里不该出现你刚删掉的名字」，不是「输出为空」。

## 用法

    python3 tools/kt_dangling_refs.py android/app/src/main/kotlin/com/common/yikaltd/MainActivity.kt
"""
import io, re, sys

KEYWORDS = set('''
if else when for while do try catch finally return break continue throw
val var fun class object interface enum data sealed companion init constructor
private public internal protected override open abstract final suspend inline
is as in out by where typealias package import null true false this super
get set lateinit vararg reified crossinline noinline annotation operator infix
'''.split())

# 小写开头的 Kotlin/Android/Java 外部符号（大写开头的一律不检查）
EXTERNAL = set('''
listOf listOfNotNull mutableListOf setOf mutableSetOf mapOf mutableMapOf arrayOf
emptyList emptyMap emptySet emptyArray arrayOfNulls buildString buildList
runCatching require requireNotNull check checkNotNull error println print
lazy also let apply run with takeIf takeUnless use repeat to synchronized
maxOf minOf abs coerceAtLeast coerceAtMost coerceIn intArrayOf byteArrayOf
sequenceOf generateSequence thread assert
getSystemService startActivity runOnUiThread checkSelfPermission requestPermissions
registerReceiver unregisterReceiver getPackageName getApplicationContext
onCreate onDestroy onResume onPause onNewIntent configureFlutterEngine
java kotlin android javax org
setMethodCallHandler setStreamHandler
mapNotNull compareByDescending sortedWith firstNotNullOfOrNull
isAccessible
'''.split())


def strip_noise(text):
    """去掉注释；字符串只保留 ${...} / $name 插值部分。"""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'(?m)//.*$', '', text)

    def keep_interp(m):
        return ' ' + ' '.join(re.findall(r'\$\{([^}]*)\}|\$(\w+)', m.group(0))[0:0] or []) + ' ' + \
               ' '.join(x for pair in re.findall(r'\$\{([^}]*)\}|\$(\w+)', m.group(0)) for x in pair if x) + ' '

    text = re.sub(r'"""(?:.|\n)*?"""', keep_interp, text)
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', keep_interp, text)
    text = re.sub(r"'(?:[^'\\]|\\.)'", ' ', text)
    return text


def declarations(text):
    names = set()
    names |= set(re.findall(r'\bfun\s+(?:<[^>]*>\s*)?(\w+)\s*\(', text))
    names |= set(re.findall(r'\b(?:val|var)\s+(\w+)', text))
    names |= set(re.findall(r'\b(?:class|object|interface)\s+(\w+)', text))
    # 形参 `name: Type` / lambda 形参 `(a, b) ->` / for / catch / 解构
    names |= set(re.findall(r'(\w+)\s*:\s*[A-Za-z_(]', text))
    for m in re.finditer(r'\(([^()]*)\)\s*->', text):
        names |= set(re.findall(r'\b([a-z]\w*)\b', m.group(1)))
    # Kotlin lambda 形参写在花括号里：`{ a, b -> … }`、`{ (k, v) -> … }`
    for m in re.finditer(r'\{\s*\(?([\w,\s]+?)\)?\s*->', text):
        names |= set(re.findall(r'\b([a-z]\w*)\b', m.group(1)))
    names |= set(re.findall(r'\bfor\s*\(\s*(?:\(([^)]*)\)|(\w+))', text))and names
    for m in re.finditer(r'\bfor\s*\(\s*(?:\(([^)]*)\)|(\w+))', text):
        names |= set(re.findall(r'\w+', (m.group(1) or m.group(2) or '')))
    names |= set(re.findall(r'\bcatch\s*\(\s*(\w+)', text))
    names |= {'it', 'field'}
    return names


def used_names(text):
    """无接收者的函数调用 foo(...)，以及 $foo 插值。带 `.` 前缀的是成员访问，跳过。"""
    found = {}
    # 接收者可能在**上一行**（`.apply {` / 换行后的 `.mapNotNull {`），所以 `.` 与名字之间
    # 允许有空白；只用 `(?<![\w.])` 这种单字符回顾会把链式调用全部误报成无接收者调用。
    chained = re.compile(r'[.?]\s*$')
    for pattern in (r'([a-z]\w*)\s*\(', r'([a-z]\w*)(?![\w(])'):
        for m in re.finditer(pattern, text):
            before = text[:m.start()]
            if before[-1:].isalnum() or before[-1:] in '_$':
                continue
            if chained.search(before):
                continue
            found.setdefault(m.group(1), m.start())
    return found


def member_bodies(text):
    """按缩进 4 的 `fun` 切出每个成员函数体，返回 (名字, 起始offset, 函数体文本)。"""
    out = []
    for m in re.finditer(r'(?m)^    (?:(?:private|internal|public|protected|override|open|abstract|inline|suspend)\s+)*fun\s+(?:<[^>]*>\s*)?(\w+)', text):
        start = m.start()
        # 从函数签名后的第一个 { 起配平到对应的 }
        brace = text.find('{', m.end())
        if brace == -1:
            continue
        depth, i = 0, brace
        while i < len(text):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        out.append((m.group(1), start, text[brace:i + 1]))
    return out


def main():
    path = sys.argv[1]
    raw = io.open(path, encoding='utf-8').read()
    code = strip_noise(raw)

    # 块注释配平（第 1 类 bug）
    problems = []
    opens, closes = len(re.findall(r'/\*', raw)), len(re.findall(r'\*/', raw))
    if opens != closes:
        problems.append(f'块注释不配平：/* = {opens}，*/ = {closes}')
    if '//**' in raw:
        problems.append('出现 `//**` —— KDoc 开头被写成了行注释，整块会降级成顶层裸文本')

    members = member_bodies(code)
    # ⚠️ 文件级声明必须**挖掉所有成员函数体**再统计。否则 A 函数里的局部变量会被当成
    # 文件级可见，B 函数里误用同名变量就查不出来——2026-09-11 第 3 次打包失败
    # （`requested` 只在 requestPairingPermissions 里声明，却在 startActivator 里被用）
    # 就是这样从第一版检查器手里漏掉的。
    outer = code
    for _, _, body in members:
        outer = outer.replace(body, ' ')
    file_level = declarations(outer)
    dangling = []
    for name, start, body in members:
        visible = file_level | declarations(body)
        for used, off in used_names(body).items():
            if used in visible or used in KEYWORDS or used in EXTERNAL:
                continue
            line = raw[:start].count('\n') + 1
            dangling.append((used, name, line))

    if problems:
        print('结构问题：')
        for p in problems:
            print('  ✗', p)
    if dangling:
        print('可疑悬空引用（用了但在该函数可见范围内没声明）：')
        seen = set()
        for used, fn, line in dangling:
            if (used, fn) in seen:
                continue
            seen.add((used, fn))
            print(f'  {used:28} 在 {fn}() 内（约第 {line} 行起）')
    if not problems and not dangling:
        print('OK：块注释配平，未发现悬空引用')
    return 1 if (problems or dangling) else 0


if __name__ == '__main__':
    sys.exit(main())
