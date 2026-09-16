import 'package:flowerpot/src/shared/media/upload_image.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-09-16 产品：定制动画和纪念日图片上传前在前端裁一下，总像素 ≤ 480,000
/// （= 800 × 600）、单文件 ≤ 1 MB。
///
/// 这里只测算尺寸那一步——解码、编码要跑 Skia 和后台 isolate，真机上才有意义；
/// 会算错的地方全在这个纯函数里。
void main() {
  test('上限就是 800 × 600 的总像素', () {
    expect(UploadImage.maxPixels, 480000);
    expect(UploadImage.maxBytes, 1024 * 1024);
  });

  test('已经够小的图原样返回，不做无谓的重编码', () {
    expect(UploadImage.targetSize(800, 600), (800, 600));
    expect(UploadImage.targetSize(640, 480), (640, 480));
    expect(UploadImage.targetSize(1, 1), (1, 1));
  });

  test('超了就等比缩，长宽比不变', () {
    final (width, height) = UploadImage.targetSize(4000, 3000);

    expect(width * height, lessThanOrEqualTo(UploadImage.maxPixels));
    // 4:3 缩完还是 4:3（取整之内）。
    expect((width / height - 4 / 3).abs(), lessThan(.01));
    // 按总像素算，不是套 800×600 的框：留下的像素要贴着上限。
    expect(width * height, greaterThan(UploadImage.maxPixels * .98));
  });

  test('竖图按总像素算，不会被 800×600 的框压掉一半', () {
    final (width, height) = UploadImage.targetSize(3000, 4000);

    expect(width * height, lessThanOrEqualTo(UploadImage.maxPixels));
    expect(height, greaterThan(width));
    // 套 800×600 的框只剩 450×600 = 27 万像素；按总像素能留到 48 万上下。
    expect(width * height, greaterThan(400000));
  });

  test('极端长宽比也压得下来，且不会算出 0', () {
    for (final size in const <(int, int)>[
      (100000, 4),
      (4, 100000),
      (20000, 1),
      (9000, 9000),
    ]) {
      final (width, height) = UploadImage.targetSize(size.$1, size.$2);
      expect(width, greaterThan(0), reason: '$size');
      expect(height, greaterThan(0), reason: '$size');
      expect(
        width * height,
        lessThanOrEqualTo(UploadImage.maxPixels),
        reason: '$size',
      );
    }
  });

  test('拿不到尺寸时不硬算', () {
    expect(UploadImage.targetSize(0, 0), (0, 0));
    expect(UploadImage.targetSize(-1, 10), (-1, 10));
  });
}
