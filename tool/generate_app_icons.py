#!/usr/bin/env python3
"""从一张方形 LOGO 生成 iOS / Android 全套 App 图标。

对齐兄弟项目（`../flutter`）`docs/runbooks/BUILD_RELEASE.md` 第五条的图标要求：

- Android 自适应图标背景为白色（`values/ic_launcher_background.xml` = `#FFFFFF`），
  前景 inset 30%，观感对齐 iOS 的「白底 + 品牌标」。不要改回品牌色底：
  前景 PNG 里属于品牌标的浅色区域一旦是透明的，彩色底会把它吃掉。
- App Store 用的 1024 图标必须去 alpha（本脚本所有 iOS 图标都写成不带 alpha 的 RGB）。
- Android 五档密度的 `ic_launcher.png` 与 `ic_launcher_foreground.png` 都要齐全。

用法：

    python3 tool/generate_app_icons.py [源图路径]

源图默认取 `assets/微信图片_20260814224541_891_12.png`，要求是方形 PNG。
本机没有 Pillow/ImageMagick，所以 PNG 解码、Lanczos3 重采样和编码都在这里自己实现。
"""

from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = REPO_ROOT / "assets" / "微信图片_20260814224541_891_12.png"

# iOS：文件名 -> 像素边长。Contents.json 已是 Flutter 默认模板，无需改动。
IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

# Android：密度目录 -> 像素边长（mdpi 48dp 基准）。
ANDROID_DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ADAPTIVE_ICON_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- Android 8+ 自适应图标：没有它，桌面会把方形 PNG 缩进白色圆片，观感差。
     背景为白色，对齐 iOS 图标观感（白底 + 品牌标）。不要改成品牌色底：
     前景 PNG 中属于品牌标的浅色区域若为透明，彩色底会把它吃掉，
     桌面上就只剩一整块纯色。前景 inset 30%，保证圆形/圆角遮罩下内容不被切。 -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground>
        <inset
            android:drawable="@mipmap/ic_launcher_foreground"
            android:inset="30%"/>
    </foreground>
</adaptive-icon>
"""

LAUNCHER_BACKGROUND_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- 自适应图标背景：白色，对齐 iOS 的「白底 + 品牌标」观感。
         不要改成品牌色：前景 PNG 中的浅色区域若是透明的，彩色底会把它吃掉，
         桌面图标会退化成一整块纯色（见 mipmap-anydpi-v26/ic_launcher.xml）。 -->
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
"""


class Image:
    """极简 RGBA 位图，通道顺序 R,G,B,A，每通道 8 位。"""

    def __init__(self, width: int, height: int, pixels: bytearray):
        self.width = width
        self.height = height
        self.pixels = pixels


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def decode_png(path: Path) -> Image:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} 不是 PNG 文件")

    idat = bytearray()
    palette = b""
    trns = b""
    width = height = bit_depth = color_type = interlace = 0
    offset = 8
    while offset < len(data):
        (length,) = struct.unpack(">I", data[offset : offset + 4])
        chunk_type = data[offset + 4 : offset + 8]
        body = data[offset + 8 : offset + 8 + length]
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(
                ">IIBBBBB", body
            )
        elif chunk_type == b"PLTE":
            palette = body
        elif chunk_type == b"tRNS":
            trns = body
        elif chunk_type == b"IDAT":
            idat += body
        elif chunk_type == b"IEND":
            break
        offset += 12 + length

    if interlace:
        raise ValueError("暂不支持 Adam7 隔行 PNG，请先另存为非隔行 PNG")
    if bit_depth not in (8, 16):
        raise ValueError(f"暂不支持 {bit_depth} 位深，请先另存为 8 位 PNG")

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    sample_bytes = bit_depth // 8
    bpp = channels * sample_bytes
    stride = width * bpp

    raw = zlib.decompress(bytes(idat))
    scanlines = bytearray(height * stride)
    previous = bytearray(stride)
    pos = 0
    for row in range(height):
        filter_type = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride
        if filter_type == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif filter_type == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif filter_type == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif filter_type == 4:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                upper_left = previous[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + _paeth(left, previous[i], upper_left)) & 0xFF
        elif filter_type != 0:
            raise ValueError(f"未知的 PNG 行过滤器：{filter_type}")
        scanlines[row * stride : (row + 1) * stride] = line
        previous = line

    pixels = bytearray(width * height * 4)
    for index in range(width * height):
        base = index * bpp
        if color_type == 3:
            entry = scanlines[base] * 3
            r, g, b = palette[entry], palette[entry + 1], palette[entry + 2]
            a = trns[scanlines[base]] if scanlines[base] < len(trns) else 255
        elif color_type == 0:
            r = g = b = scanlines[base]
            a = 255
        elif color_type == 4:
            r = g = b = scanlines[base]
            a = scanlines[base + sample_bytes]
        elif color_type == 2:
            r = scanlines[base]
            g = scanlines[base + sample_bytes]
            b = scanlines[base + 2 * sample_bytes]
            a = 255
        else:
            r = scanlines[base]
            g = scanlines[base + sample_bytes]
            b = scanlines[base + 2 * sample_bytes]
            a = scanlines[base + 3 * sample_bytes]
        out = index * 4
        pixels[out] = r
        pixels[out + 1] = g
        pixels[out + 2] = b
        pixels[out + 3] = a

    return Image(width, height, pixels)


def encode_png(image: Image, path: Path, *, with_alpha: bool) -> None:
    """写出 8 位 PNG。`with_alpha=False` 时输出不含 alpha 通道的 RGB。

    App Store 的 1024 图标不允许带 alpha，因此 iOS 全套都走 RGB。
    """
    channels = 4 if with_alpha else 3
    width, height = image.width, image.height
    stride = width * channels
    src = image.pixels

    raw = bytearray()
    previous = bytearray(stride)
    for row in range(height):
        line = bytearray(stride)
        src_base = row * width * 4
        if with_alpha:
            line[:] = src[src_base : src_base + width * 4]
        else:
            for column in range(width):
                s = src_base + column * 4
                d = column * 3
                line[d] = src[s]
                line[d + 1] = src[s + 1]
                line[d + 2] = src[s + 2]
        # 全部使用 Paeth 过滤：渐变图上压缩率明显优于不过滤。
        filtered = bytearray(stride)
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            upper_left = previous[i - channels] if i >= channels else 0
            filtered[i] = (line[i] - _paeth(left, previous[i], upper_left)) & 0xFF
        raw.append(4)
        raw += filtered
        previous = line

    def chunk(tag: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + tag
            + body
            + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 6 if with_alpha else 2, 0, 0, 0)
    payload = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def _lanczos(x: float, lobes: int = 3) -> float:
    if x == 0.0:
        return 1.0
    if x <= -lobes or x >= lobes:
        return 0.0
    px = math.pi * x
    return lobes * math.sin(px) * math.sin(px / lobes) / (px * px)


def _contributions(src_size: int, dst_size: int) -> list[tuple[int, list[float]]]:
    """按目标像素给出 (起始源索引, 权重表)，缩小时自动展宽滤波器。"""
    scale = dst_size / src_size
    filter_scale = 1.0 / scale if scale < 1.0 else 1.0
    support = 3.0 * filter_scale
    result = []
    for i in range(dst_size):
        center = (i + 0.5) / scale
        left = max(0, int(math.floor(center - support)))
        right = min(src_size, int(math.ceil(center + support)))
        weights = [
            _lanczos((j + 0.5 - center) / filter_scale) for j in range(left, right)
        ]
        total = sum(weights)
        if total != 0.0:
            weights = [w / total for w in weights]
        result.append((left, weights))
    return result


def resize(image: Image, size: int) -> Image:
    """Lanczos3 分离式重采样到 size×size（放大缩小通用）。"""
    if image.width == size and image.height == size:
        return Image(size, size, bytearray(image.pixels))

    src = image.pixels
    src_w, src_h = image.width, image.height

    # 水平方向：src_h 行 × size 列，浮点中间结果。
    horizontal = [0.0] * (src_h * size * 4)
    x_taps = _contributions(src_w, size)
    for row in range(src_h):
        row_base = row * src_w * 4
        out_base = row * size * 4
        for column, (left, weights) in enumerate(x_taps):
            r = g = b = a = 0.0
            offset = row_base + left * 4
            for weight in weights:
                r += src[offset] * weight
                g += src[offset + 1] * weight
                b += src[offset + 2] * weight
                a += src[offset + 3] * weight
                offset += 4
            out = out_base + column * 4
            horizontal[out] = r
            horizontal[out + 1] = g
            horizontal[out + 2] = b
            horizontal[out + 3] = a

    # 垂直方向：size 行 × size 列，写回 8 位。
    pixels = bytearray(size * size * 4)
    y_taps = _contributions(src_h, size)
    for row, (top, weights) in enumerate(y_taps):
        out_base = row * size * 4
        for column in range(size):
            r = g = b = a = 0.0
            offset = (top * size + column) * 4
            step = size * 4
            for weight in weights:
                r += horizontal[offset] * weight
                g += horizontal[offset + 1] * weight
                b += horizontal[offset + 2] * weight
                a += horizontal[offset + 3] * weight
                offset += step
            out = out_base + column * 4
            pixels[out] = min(255, max(0, int(r + 0.5)))
            pixels[out + 1] = min(255, max(0, int(g + 0.5)))
            pixels[out + 2] = min(255, max(0, int(b + 0.5)))
            pixels[out + 3] = min(255, max(0, int(a + 0.5)))

    return Image(size, size, pixels)


def flatten_on_white(image: Image) -> Image:
    """把 alpha 合成到白底上，供 iOS（禁止 alpha）和 Android 传统图标使用。"""
    pixels = bytearray(image.pixels)
    for index in range(0, len(pixels), 4):
        alpha = pixels[index + 3]
        if alpha != 255:
            ratio = alpha / 255.0
            for channel in range(3):
                value = pixels[index + channel] * ratio + 255 * (1.0 - ratio)
                pixels[index + channel] = min(255, max(0, int(value + 0.5)))
            pixels[index + 3] = 255
    return Image(image.width, image.height, pixels)


def main() -> int:
    source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not source_path.is_absolute():
        source_path = (REPO_ROOT / source_path).resolve()
    if not source_path.exists():
        print(f"找不到源图：{source_path}", file=sys.stderr)
        return 1

    source = decode_png(source_path)
    if source.width != source.height:
        print(
            f"源图必须是正方形，当前为 {source.width}x{source.height}",
            file=sys.stderr,
        )
        return 1
    print(f"源图：{source_path.name}（{source.width}x{source.height}）")
    if source.width < 1024:
        print(
            f"提示：源图仅 {source.width}px，放大到 1024 的 App Store 图标会偏软，"
            "建议后续换更高分辨率原图重跑本脚本。"
        )

    opaque = flatten_on_white(source)

    ios_dir = REPO_ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, size in sorted(IOS_ICONS.items(), key=lambda item: item[1]):
        encode_png(resize(opaque, size), ios_dir / name, with_alpha=False)
        print(f"  iOS  {name} ({size}x{size})")

    res_dir = REPO_ROOT / "android/app/src/main/res"
    for density, size in ANDROID_DENSITIES.items():
        encode_png(
            resize(opaque, size), res_dir / density / "ic_launcher.png", with_alpha=False
        )
        # 自适应图标前景保持 alpha 通道；XML 里 inset 30% 负责留出遮罩安全区。
        encode_png(
            resize(source, size),
            res_dir / density / "ic_launcher_foreground.png",
            with_alpha=True,
        )
        print(f"  安卓 {density} ic_launcher / ic_launcher_foreground ({size}x{size})")

    adaptive = res_dir / "mipmap-anydpi-v26/ic_launcher.xml"
    adaptive.parent.mkdir(parents=True, exist_ok=True)
    adaptive.write_text(ADAPTIVE_ICON_XML, encoding="utf-8")
    background = res_dir / "values/ic_launcher_background.xml"
    background.parent.mkdir(parents=True, exist_ok=True)
    background.write_text(LAUNCHER_BACKGROUND_XML, encoding="utf-8")
    print("  安卓 mipmap-anydpi-v26/ic_launcher.xml + values/ic_launcher_background.xml")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
