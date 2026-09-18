import 'package:flowerpot/src/shared/media/upload_image.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-09-17（随固件 1.0.12 的图片下载）：定制动画和纪念日图片上传前压成设备能
/// 显示的那一张——JPG Baseline、4:2:0、**≤ 320 × 240**、≤ 500 KB。
///
/// 尺寸口径从 09-16 那版的「总像素 ≤ 480,000」换成了**设备屏幕的框**：屏幕只有
/// 240 高，按总像素算出来的 240 × 320 竖图高度超出屏幕，居中显示会被裁掉两头。
///
/// 这里只测算尺寸那一步——解码、编码要跑 Skia 和后台 isolate，真机上才有意义；
/// 会算错的地方全在这个纯函数里。Baseline 和 4:2:0 由 `package:image` 的编码器
/// 保证（它只写 `SOF0`，chroma 显式传 `yuv420`），不在这里测。
void main() {
  test('上限就是设备屏幕的 320 × 240 和 500 KB', () {
    expect(UploadImage.maxWidth, 320);
    expect(UploadImage.maxHeight, 240);
    expect(UploadImage.maxBytes, 500 * 1024);
  });

  test('框里的图原样返回，小图不放大', () {
    expect(UploadImage.targetSize(320, 240), (320, 240));
    expect(UploadImage.targetSize(200, 150), (200, 150));
    expect(UploadImage.targetSize(120, 200), (120, 200));
    expect(UploadImage.targetSize(1, 1), (1, 1));
  });

  test('横图缩到贴着 320 那一边，长宽比不变', () {
    expect(UploadImage.targetSize(4000, 3000), (320, 240));

    final (width, height) = UploadImage.targetSize(4000, 2000);

    expect(width, 320);
    expect(height, 160);
  });

  test('竖图缩到贴着 240 那一边，高度不许超出屏幕', () {
    final (width, height) = UploadImage.targetSize(3000, 4000);

    expect(height, 240);
    expect(width, 180);
    // 按总像素算会得到 240 × 320——总像素没超，高度却超出屏幕一截。
    expect(height, lessThanOrEqualTo(UploadImage.maxHeight));
  });

  test('只超一边的图也按框缩', () {
    // 宽没超、高超了：只按高度缩。
    expect(UploadImage.targetSize(300, 480), (150, 240));
    // 高没超、宽超了：只按宽度缩。
    expect(UploadImage.targetSize(640, 200), (320, 100));
  });

  test('极端长宽比也压得进框，且不会算出 0', () {
    for (final size in const <(int, int)>[
      (100000, 4),
      (4, 100000),
      (20000, 1),
      (9000, 9000),
    ]) {
      final (width, height) = UploadImage.targetSize(size.$1, size.$2);
      expect(width, greaterThan(0), reason: '$size');
      expect(height, greaterThan(0), reason: '$size');
      expect(width, lessThanOrEqualTo(UploadImage.maxWidth), reason: '$size');
      expect(height, lessThanOrEqualTo(UploadImage.maxHeight), reason: '$size');
    }
  });

  test('拿不到尺寸时不硬算', () {
    expect(UploadImage.targetSize(0, 0), (0, 0));
    expect(UploadImage.targetSize(-1, 10), (-1, 10));
  });
}
