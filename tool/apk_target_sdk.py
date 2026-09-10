#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""离线读出一个 APK 的 targetSdkVersion / minSdkVersion 与 Wi-Fi 相关权限。

为什么需要它：Android 的 Wi-Fi 限制是按**应用的 targetSdkVersion** 生效的，不是按手机
系统版本。`WifiManager.addNetwork()` / `enableNetwork()` 对 `targetSdk >= 29` 的应用
「always fail」，而 `targetSdk <= 28` 的应用在新系统上仍能静默连自己加的网络、不弹框。
排查「为什么别家 App 配网不弹授权框」时，第一件要确认的就是对方的 targetSdk。

用法：
    python3 tool/apk_target_sdk.py 智能生活.apk

拿到 APK 的办法（手机开 USB 调试后）：
    adb shell pm list packages | grep -iE 'tuya|thing|smartlife'
    adb shell pm path <包名>
    adb pull <上一步打印的 /data/app/.../base.apk> ./smartlife.apk

⚠️ 只读，不解包、不改写 APK。不依赖 Android SDK / aapt，纯标准库解析二进制
AndroidManifest.xml（AXML）。
"""
from __future__ import annotations

import struct
import sys
import zipfile

# AXML 块类型
_CHUNK_STRING_POOL = 0x0001
_CHUNK_START_TAG = 0x0102

# 属性值类型
_TYPE_INT_DEC = 0x10

_WIFI_PERMISSIONS = (
    'CHANGE_WIFI_STATE',
    'ACCESS_WIFI_STATE',
    'ACCESS_FINE_LOCATION',
    'ACCESS_COARSE_LOCATION',
    'NEARBY_WIFI_DEVICES',
    'CHANGE_NETWORK_STATE',
)


def _read_string_pool(data: bytes, offset: int) -> list[str]:
    """解析 AXML 的字符串池。属性名、标签名都是它的下标。"""
    string_count, _style_count, flags, strings_start, _styles_start = struct.unpack_from(
        '<IIIII', data, offset + 8
    )
    utf8 = bool(flags & (1 << 8))
    offsets_at = offset + 28
    base = offset + strings_start
    out: list[str] = []
    for index in range(string_count):
        (string_offset,) = struct.unpack_from('<I', data, offsets_at + index * 4)
        at = base + string_offset
        if utf8:
            # UTF-8：两个长度字段（字符数、字节数），各自可能是 1 或 2 字节
            at += 1 if data[at] & 0x80 == 0 else 2
            if data[at] & 0x80:
                length = ((data[at] & 0x7F) << 8) | data[at + 1]
                at += 2
            else:
                length = data[at]
                at += 1
            out.append(data[at:at + length].decode('utf-8', 'replace'))
        else:
            length = struct.unpack_from('<H', data, at)[0]
            if length & 0x8000:
                length = ((length & 0x7FFF) << 16) | struct.unpack_from('<H', data, at + 2)[0]
                at += 4
            else:
                at += 2
            out.append(data[at:at + length * 2].decode('utf-16-le', 'replace'))
    return out


def parse_manifest(axml: bytes) -> dict[str, object]:
    """从二进制 AndroidManifest.xml 里取出我们关心的几项。"""
    strings: list[str] = []
    result: dict[str, object] = {'permissions': []}
    offset = 8  # 跳过文件头（type/headerSize/fileSize）
    size = len(axml)
    while offset + 8 <= size:
        chunk_type, header_size, chunk_size = struct.unpack_from('<HHI', axml, offset)
        if chunk_size <= 0 or offset + chunk_size > size:
            break
        if chunk_type == _CHUNK_STRING_POOL:
            strings = _read_string_pool(axml, offset)
        elif chunk_type == _CHUNK_START_TAG and strings:
            name_index, = struct.unpack_from('<I', axml, offset + 20)
            tag = strings[name_index] if name_index < len(strings) else ''
            attr_start, _attr_size, attr_count = struct.unpack_from('<HHH', axml, offset + 24)
            # attributeStart 是相对 ResXMLTree_attrExt 起点的偏移，而 attrExt 从
            # offset+16 开始（ResChunk_header 8 + lineNumber 4 + comment 4）。
            at = offset + 16 + attr_start
            for _ in range(attr_count):
                attr_name_index, _raw = struct.unpack_from('<II', axml, at + 4)
                data_type = axml[at + 15]
                value, = struct.unpack_from('<I', axml, at + 16)
                attr = strings[attr_name_index] if attr_name_index < len(strings) else ''
                if tag == 'uses-sdk' and data_type == _TYPE_INT_DEC:
                    if attr in ('targetSdkVersion', 'minSdkVersion'):
                        result[attr] = value
                if tag == 'uses-permission' and attr == 'name':
                    raw_index = _raw
                    if raw_index < len(strings):
                        name = strings[raw_index]
                        if any(name.endswith(item) for item in _WIFI_PERMISSIONS):
                            result['permissions'].append(name)  # type: ignore[union-attr]
                at += 20
        offset += chunk_size
    return result


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    with zipfile.ZipFile(argv[1]) as apk:
        axml = apk.read('AndroidManifest.xml')
    info = parse_manifest(axml)
    target = info.get('targetSdkVersion')
    print('minSdkVersion    :', info.get('minSdkVersion', '未读到'))
    print('targetSdkVersion :', target if target is not None else '未读到')
    permissions = sorted(set(info.get('permissions') or []))  # type: ignore[arg-type]
    print('Wi-Fi 相关权限   :', '、'.join(permissions) if permissions else '（无）')
    if isinstance(target, int):
        print()
        if target <= 28:
            print('结论：targetSdk ≤ 28 —— 这个 App 仍可用旧的 addNetwork()/enableNetwork()')
            print('      静默连 Wi-Fi，不会弹系统授权框。这就是它和我们行为不同的原因。')
        else:
            print('结论：targetSdk ≥ 29 —— 旧 API 对它同样 always fail，它不弹框另有原因，')
            print('      需要继续查（例如系统记住了授权、或用了 WifiNetworkSuggestion）。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
