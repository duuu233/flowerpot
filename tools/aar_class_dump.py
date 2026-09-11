#!/usr/bin/env python3
"""把 `.class` / `.jar` / `.aar` 里的类签名打出来——**不依赖 JDK**。

为什么要有它：桥接层整套是反射调 SDK（`invoke(target, "setSsid", ...)`），
方法名和参数类型**没有编译期保护**，写错只会在真机上炸 `NoSuchMethodException`。
这台开发机没有 `javap`（连 JRE 都没装），此前只能靠翻文档和猜——涂鸦官方 AI 编造
过好几个不存在的类，就是这么被拆穿的（见 `docs/history/2026-09/`）。

只读，不改写任何东西。用法：

    python3 tools/aar_class_dump.py <aar|jar|class> [类名子串过滤...]

输出每个类的父类、接口、字段与方法（含 JVM 描述符转成的人话签名）。
"""

from __future__ import annotations

import io
import re
import struct
import sys
import zipfile

# 常量池里我们要用的两种：Utf8 和 Class（Class 指向一个 Utf8）。其余按长度跳过。
_CONST_SIZES = {
    3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4, 11: 4,
    12: 4, 15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2,
}

_PRIMITIVES = {
    'B': 'byte', 'C': 'char', 'D': 'double', 'F': 'float', 'I': 'int',
    'J': 'long', 'S': 'short', 'Z': 'boolean', 'V': 'void',
}

ACC_PUBLIC, ACC_STATIC, ACC_ABSTRACT, ACC_INTERFACE = 0x0001, 0x0008, 0x0400, 0x0200


def _read_pool(data: bytes, offset: int) -> tuple[dict[int, object], int]:
    count = struct.unpack_from('>H', data, offset)[0]
    offset += 2
    pool: dict[int, object] = {}
    index = 1
    while index < count:
        tag = data[offset]
        offset += 1
        if tag == 1:
            length = struct.unpack_from('>H', data, offset)[0]
            pool[index] = data[offset + 2:offset + 2 + length].decode('utf-8', 'replace')
            offset += 2 + length
        elif tag == 7:
            pool[index] = ('class', struct.unpack_from('>H', data, offset)[0])
            offset += 2
        else:
            offset += _CONST_SIZES.get(tag, 0)
        # long 与 double 占两个槽位。
        index += 2 if tag in (5, 6) else 1
    return pool, offset


def _name(pool: dict[int, object], index: int) -> str:
    entry = pool.get(index)
    if isinstance(entry, tuple) and entry[0] == 'class':
        entry = pool.get(entry[1])
    return str(entry).replace('/', '.') if entry else '?'


def _types(descriptor: str) -> tuple[list[str], str]:
    """把 `(Ljava/lang/String;I)V` 拆成 (['String', 'int'], 'void')。"""
    out: list[str] = []
    i = 0
    args_end = descriptor.index(')') if ')' in descriptor else len(descriptor)
    body = descriptor[1:args_end] if descriptor.startswith('(') else descriptor
    while i < len(body):
        arrays = 0
        while i < len(body) and body[i] == '[':
            arrays += 1
            i += 1
        if i >= len(body):
            break
        if body[i] == 'L':
            end = body.index(';', i)
            name = body[i + 1:end].replace('/', '.').split('.')[-1]
            i = end + 1
        else:
            name = _PRIMITIVES.get(body[i], body[i])
            i += 1
        out.append(name + '[]' * arrays)
    ret = ''
    if ')' in descriptor:
        ret = _types(descriptor[args_end + 1:] + '@')[0]
        ret = ret[0] if ret else 'void'
    return out, ret


def dump(data: bytes) -> str:
    if data[:4] != b'\xca\xfe\xba\xbe':
        return ''
    pool, offset = _read_pool(data, 8)
    flags, this_index, super_index = struct.unpack_from('>HHH', data, offset)
    offset += 6
    interface_count = struct.unpack_from('>H', data, offset)[0]
    offset += 2
    interfaces = [
        _name(pool, struct.unpack_from('>H', data, offset + 2 * i)[0])
        for i in range(interface_count)
    ]
    offset += 2 * interface_count

    lines = [
        f"{'interface' if flags & ACC_INTERFACE else 'class'} {_name(pool, this_index)}"
        f"{'' if super_index == 0 else ' extends ' + _name(pool, super_index)}"
        f"{'' if not interfaces else ' implements ' + ', '.join(interfaces)}"
    ]

    for section in ('field', 'method'):
        count = struct.unpack_from('>H', data, offset)[0]
        offset += 2
        for _ in range(count):
            acc, name_index, desc_index, attr_count = struct.unpack_from('>HHHH', data, offset)
            offset += 8
            for _ in range(attr_count):
                length = struct.unpack_from('>I', data, offset + 2)[0]
                offset += 6 + length
            name = str(pool.get(name_index, '?'))
            desc = str(pool.get(desc_index, '?'))
            if name.startswith('$') or name == '<clinit>':
                continue
            prefix = '  ' + ('static ' if acc & ACC_STATIC else '')
            if section == 'field':
                lines.append(f'{prefix}{_types(desc + "@")[0][0]} {name}')
            else:
                args, ret = _types(desc)
                lines.append(f'{prefix}{ret} {name}({", ".join(args)})')
    return '\n'.join(lines)


def _classes(path: str):
    if path.endswith('.class'):
        yield path, io.open(path, 'rb').read()
        return
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if name.endswith('.class'):
                yield name, archive.read(name)
            elif name.endswith('.jar'):
                with zipfile.ZipFile(io.BytesIO(archive.read(name))) as inner:
                    for entry in inner.namelist():
                        if entry.endswith('.class'):
                            yield f'{name}!{entry}', inner.read(entry)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    path, filters = argv[1], [f.lower() for f in argv[2:]]
    found = 0
    for name, data in _classes(path):
        if filters and not any(f in name.lower() for f in filters):
            continue
        text = dump(data)
        if not text:
            continue
        found += 1
        print(text)
        print()
    print(f'-- {found} 个类', file=sys.stderr)
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
