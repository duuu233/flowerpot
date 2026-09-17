import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 上传前在前端把图片压成花盆能下载、能显示的那一张（2026-09-17 口径，随固件
/// 1.0.12 的「图片下载」一起定的）。
///
/// 两处上传共用：定制动画（`AnimationsPage`，走 `setUserProductUpload`，再由
/// DP142 `dl_url` 通知花盆下载）和纪念日图片（`MemorialEditPage`，走
/// `setFileUpload`，URL 进 DP154 的帧）。两条路最终都是**花盆自己把图下载下来、
/// 在那块 320 × 240 的屏幕上显示**，固件的解码器只认一种图：
///
/// - **JPG Baseline，不能是 Progressive**。`package:image` 的 JPEG 编码器只写
///   `SOF0`（baseline），根本没有渐进模式，这一条由编码器保证。
/// - **4:2:0 采样**：`img.JpegChroma.yuv420`。⚠️ `encodeJpg` 的默认值是
///   `yuv444`，**必须显式传**，漏了就是 4:4:4。
/// - **尺寸 ≤ [maxWidth] × [maxHeight]**：宽、高**各自**不超过一边，等比缩放，
///   任意宽高比都行（设备居中显示）。**小图不放大。**
/// - **单文件 ≤ [maxBytes]**。
///
/// ⚠️ 尺寸口径和 2026-09-16 那一版不一样：上一版是「总像素 ≤ 480,000」，按总像素
/// 算竖图能留到 600 × 800；现在这个 320 × 240 是**设备屏幕的框**，一张 240 × 320
/// 的竖图总像素没超、高度却超出屏幕一截，设备居中显示就只能把上下裁掉。所以这一
/// 版按框缩，不按总像素。
///
/// 实现上解码和缩放交给 `dart:ui`（Skia，原生、按目标尺寸解码，不会先把整张
/// 4000×3000 铺成 48 MB 的位图），只有 JPEG 编码用 `package:image`——`dart:ui`
/// 只能编 PNG，也给不了 4:2:0。编码放在 [compute] 的后台 isolate 里，不卡 UI。
///
/// ⚠️ **压不出合格的图就不传**（2026-09-17 改口径）：[prepare] 返回 null，两处
/// 调用都提示「图片处理失败」并中止上传。上一版是「压不动就原样传原图」，那时候
/// 压缩只是省流量；现在格式是**设备解码器的硬要求**，传一张 Progressive 或者超框
/// 的图上去，花盆下载完显示不出来，手机上却一切正常——比当场报错难查得多。
abstract final class UploadImage {
  /// 宽度上限，就是设备屏幕的宽。
  static const maxWidth = 320;

  /// 高度上限，就是设备屏幕的高。
  static const maxHeight = 240;

  /// 单文件上限，500 KB。
  static const maxBytes = 500 * 1024;

  /// JPEG 质量档：先按第一档编，超了 [maxBytes] 再往下降。
  ///
  /// 320 × 240 的 4:2:0 图按 85 编出来通常就二三十 KB，离 500 KB 差着一个数量级，
  /// 后面几档实际上用不到；留着是为了「上限是硬的」这句话在代码里也成立。
  static const _qualitySteps = <int>[85, 75, 65, 55, 45, 35];

  /// 把 [sourcePath] 处理成可以上传的文件，返回处理后的路径。
  ///
  /// 返回 null 表示**没能做出一张合格的图**（解码失败、编码失败、或者降到最低
  /// 质量仍然超过 [maxBytes]）。调用方必须中止上传并告诉用户，不要退回原图。
  ///
  /// 原图就算已经够小也照样重编一遍：选图器交上来的那张是什么采样、是不是
  /// Progressive，App 这边看不出来，只有经过自己的编码器才能保证 Baseline +
  /// 4:2:0。重编一张 320 × 240 的图只有几毫秒。
  static Future<String?> prepare(String sourcePath) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      // 缓冲区不手动 dispose：`ImageDescriptor` 拿着它，Flutter 自己的
      // `PaintingBinding.instantiateImageCodecWithSize` 也是只放 descriptor。
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final (targetWidth, targetHeight) = targetSize(
        descriptor.width,
        descriptor.height,
      );

      final codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      // Skia 有时会给出比请求值大一点的尺寸（按整数倍采样），按它实际给的算，
      // 否则 RGBA 的字节数和宽高对不上，编出来是一张斜的图。超出框的那点差额由
      // [_encodeJpeg] 再收一次——320 × 240 是设备的硬框，不能「大一点点」。
      final decodedWidth = image.width;
      final decodedHeight = image.height;
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();
      descriptor.dispose();
      if (raw == null) return null;

      final rgba = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
      final encoded = await compute(
        _encodeJpeg,
        (rgba, decodedWidth, decodedHeight),
      );
      if (encoded == null || encoded.isEmpty) return null;
      return _write(encoded, sourcePath);
    } catch (error) {
      debugPrint('[upload] 图片处理失败，本次不上传：$error');
      return null;
    }
  }

  /// 等比缩进 [maxWidth] × [maxHeight] 的框之后的宽高。已经在框里就原样返回
  /// （**小图不放大**）。
  ///
  /// 单独抽出来是为了能直接测：这一步是整段逻辑里唯一会算错的地方（缩放系数、
  /// 取整之后又超回去、1 像素宽的图被算成 0）。
  static (int, int) targetSize(int width, int height) {
    if (width <= 0 || height <= 0) return (width, height);
    if (width <= maxWidth && height <= maxHeight) return (width, height);
    // 两个方向各自的余量取小的那个，长边贴边、短边留白，长宽比不变。
    final scale = math.min(maxWidth / width, maxHeight / height);
    // floor 只会往小取，正常不会再超；math.min 那一层是防浮点误差把 320 算成
    // 320.000000001，以及极扁的图（100000 × 4）缩完把短边算成 0。
    final scaledWidth = (width * scale).floor();
    final scaledHeight = (height * scale).floor();
    final targetWidth = math.min(maxWidth, math.max(1, scaledWidth));
    final targetHeight = math.min(maxHeight, math.max(1, scaledHeight));
    return (targetWidth, targetHeight);
  }

  /// 后台 isolate 里跑：RGBA → Baseline 4:2:0 JPEG，超过 [maxBytes] 就降一档
  /// 质量重编；最低一档还超就返回 null（宁可不传，也不给设备一张它显示不了的图）。
  static Uint8List? _encodeJpeg((Uint8List, int, int) job) {
    final (rgba, width, height) = job;
    var image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
    );
    // Skia 给大了的那点差额在这里收掉：解码尺寸没超框时这一步不会执行。
    final (fitWidth, fitHeight) = targetSize(width, height);
    if (fitWidth != width || fitHeight != height) {
      image = img.copyResize(
        image,
        width: fitWidth,
        height: fitHeight,
        interpolation: img.Interpolation.average,
      );
    }
    var encoded = _encodeBaseline(image, _qualitySteps.first);
    for (final quality in _qualitySteps.skip(1)) {
      if (encoded.length <= maxBytes) break;
      encoded = _encodeBaseline(image, quality);
    }
    return encoded.length <= maxBytes ? encoded : null;
  }

  /// Baseline（`SOF0`）+ 4:2:0 的 JPEG。`chroma` 不传就是 4:4:4，设备不收。
  static Uint8List _encodeBaseline(img.Image image, int quality) =>
      img.encodeJpg(image, quality: quality, chroma: img.JpegChroma.yuv420);

  /// 写进系统临时目录，文件名沿用原图的主名 + `.jpg`。
  ///
  /// 上传走的是 `MultipartFile.fromPath`，文件名就是后端存下来的名字，所以名字
  /// 要保持可读；带上时间戳免得连传两张同名图时互相覆盖。
  static Future<String> _write(Uint8List bytes, String sourcePath) async {
    final directory = Directory(
      '${Directory.systemTemp.path}/flowerpot_upload',
    );
    if (!directory.existsSync()) await directory.create(recursive: true);
    final base = sourcePath
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'\.[^.]*$'), '');
    final stem = base.isEmpty ? 'image' : base;
    final file = File(
      '${directory.path}/${stem}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
