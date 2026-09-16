import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 上传前在前端把图片裁到设备和后端能接的大小（2026-09-16 产品）。
///
/// 两处上传共用：定制动画（`AnimationsPage`，走 `setUserProductUpload`，再由
/// DP142 通知花盆下载）和纪念日图片（`MemorialEditPage`，走 `setFileUpload`，
/// URL 进 DP154 的帧）。两条路最终都是**花盆那块小屏幕**在显示，原图动辄几 MB、
/// 几千万像素，传上去既慢又白费。
///
/// 口径：
///
/// - **总像素 ≤ [maxPixels]**（= 800 × 600）。产品给的是「分辨率 ≤ 800×600」，
///   同时说明「按总像素 ≤ 480,000 就行」——按总像素算才不会把竖图压得比横图小
///   （3:4 的竖图套 800×600 的框只剩 450×600 = 27 万像素，按总像素能留到
///   600×800 = 48 万）。等比缩放，不裁掉画面内容。
/// - **单文件 ≤ [maxBytes]**（1 MB）。像素压下来之后 JPEG 基本都在一两百 KB，
///   万一还超就按 [_qualitySteps] 逐档降质量重编。
/// - 输出一律是 JPEG：选图器给的本来就是 JPEG（`imageQuality` 已经让它重编过
///   一次，顺带把 EXIF 旋转烤进像素里），后端和固件拿到的扩展名、格式都不变。
///
/// 实现上解码和缩放交给 `dart:ui`（Skia，原生、按目标尺寸解码，不会先把整张
/// 4000×3000 铺成 48 MB 的位图），只有 JPEG 编码用 `package:image`——`dart:ui`
/// 只能编 PNG，而 PNG 存照片经常自己就顶到 1 MB。编码放在 [compute] 的后台
/// isolate 里，不卡 UI。
///
/// **失败不挡上传**：任何一步出错都原样返回原图路径。压缩是优化，不是门禁；
/// 为了压不动的一张图让用户传不上去不划算。
abstract final class UploadImage {
  /// 总像素上限，800 × 600 = 480,000。
  static const maxPixels = 800 * 600;

  /// 单文件上限，1 MB。
  static const maxBytes = 1024 * 1024;

  /// JPEG 质量档：先按第一档编，超了 [maxBytes] 再往下降。
  static const _qualitySteps = <int>[85, 75, 65, 55, 45, 35];

  /// 把 [sourcePath] 处理成可以上传的文件，返回处理后的路径。
  ///
  /// 原图已经在口径内时原样返回 [sourcePath]，不做无谓的重编码。
  static Future<String> prepare(String sourcePath) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      // 缓冲区不手动 dispose：`ImageDescriptor` 拿着它，Flutter 自己的
      // `PaintingBinding.instantiateImageCodecWithSize` 也是只放 descriptor。
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      final (targetWidth, targetHeight) = targetSize(width, height);
      if (targetWidth == width &&
          targetHeight == height &&
          bytes.length <= maxBytes) {
        descriptor.dispose();
        return sourcePath;
      }

      final codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      // Skia 有时会给出比请求值大一点的尺寸（按整数倍采样），按它实际给的算，
      // 否则 RGBA 的字节数和宽高对不上，编出来是一张斜的图。
      final decodedWidth = image.width;
      final decodedHeight = image.height;
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();
      descriptor.dispose();
      if (raw == null) return sourcePath;

      final rgba = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
      final encoded = await compute(
        _encodeJpeg,
        (rgba, decodedWidth, decodedHeight),
      );
      return _write(encoded, sourcePath);
    } catch (error) {
      // 压缩失败就传原图：设备那边最多是慢一点，总好过传不上去。
      debugPrint('[upload] 图片压缩失败，改传原图：$error');
      return sourcePath;
    }
  }

  /// 等比缩到总像素不超过 [maxPixels] 之后的宽高。已经够小就原样返回。
  ///
  /// 单独抽出来是为了能直接测：这一步是整段逻辑里唯一会算错的地方（缩放系数、
  /// 取整之后又超回去、1 像素宽的图被算成 0）。
  static (int, int) targetSize(int width, int height) {
    if (width <= 0 || height <= 0) return (width, height);
    var targetWidth = width;
    var targetHeight = height;
    if (width * height > maxPixels) {
      final scale = math.sqrt(maxPixels / (width * height));
      targetWidth = math.max(1, (width * scale).floor());
      targetHeight = math.max(1, (height * scale).floor());
    }
    // 取整是往下取的，正常不会再超；极扁的图（比如 100000×4）按比例算完仍可能
    // 压不下来，这里再收一收，免得把「≤ 48 万像素」变成一句空话。
    while (targetWidth * targetHeight > maxPixels &&
        (targetWidth > 1 || targetHeight > 1)) {
      if (targetWidth >= targetHeight) {
        targetWidth--;
      } else {
        targetHeight--;
      }
    }
    return (targetWidth, targetHeight);
  }

  /// 后台 isolate 里跑：RGBA → JPEG，超过 [maxBytes] 就降一档质量重编。
  static Uint8List _encodeJpeg((Uint8List, int, int) job) {
    final (rgba, width, height) = job;
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
    );
    var encoded = img.encodeJpg(image, quality: _qualitySteps.first);
    for (final quality in _qualitySteps.skip(1)) {
      if (encoded.length <= maxBytes) break;
      encoded = img.encodeJpg(image, quality: quality);
    }
    return encoded;
  }

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
