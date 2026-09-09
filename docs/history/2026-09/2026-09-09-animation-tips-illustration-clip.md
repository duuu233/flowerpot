# 定制动画「提示」卡右下角背景图被裁

> 文档类型：Historical Change Record
> 日期：2026-09-09
> 环境：SSH
> 分支与起始版本：main / e355274
> 范围：`lib/src/features/devices/presentation/animations_page.dart`
> 当前权威文档：`docs/UI/定制动画.png`（设计稿）、`AI_CONTEXT.md`

## 背景与目标

反馈：定制动画页「提示」盒子右下角的背景图，在盒子高度改短之后显示不完整。

## 变更内容

`_AnimationTipsCard` 重排：

- 卡片改为 `padding: EdgeInsets.zero`，内边距 `EdgeInsets.fromLTRB(16, 14, 14, 14)` 挪到文案那一层的 `Padding`；`SizedBox` 高度由 126 改成 `126 + 内边距上下 28 = 154`，卡片外形高度不变。
- 背景图从 `Positioned(right: -14, bottom: -18)` 改为 `Positioned(right: 0, bottom: 14)`：右边贴着卡片边缘，底部留出和文案一样的 14px。图片尺寸仍是 118 见方、透明度仍是 .42。
- 图片加 `Key('animation-tips-illustration')`，`_FilePreviewIllustration` 补 `super.key`。

## 关键决策

- 根因不是图片本身被缩放坏了，而是**被裁**：`Stack` 的 `clipBehavior` 默认是 `Clip.hardEdge`，而那张图被负偏移顶到 `SizedBox` 之外 18px（下）/ 14px（右），顶出去的部分根本不画。卡片当时留着 14px 内边距，本来是有地方放的。盒子高度压到 126 之后，被切掉的正好是文件夹的下沿和右边的叶子。
- 也核对了缩放：素材 `animation_upload_illustration.png` 是 670×304 的宽图，`BoxFit.cover` + `alignment: centerRight` 把它裁到 118 见方时，取的是源图右侧 304px 那一窗，文件夹和叶子整个在窗内——所以 `cover` 不是问题，不动它。
- 没有改用 `Stack(clipBehavior: Clip.none)` 让图继续往外出血：卡片圆角 16px，出血到底边会让叶子尖被圆角削掉。按设计稿 `docs/UI/定制动画.png` 的摆法——右边出血、底部与文案齐平——图整块都在卡片内，圆角碰不到它。

## 外部操作

无。

## 验证结果

- 本机（SSH 开发机）**没有 Flutter/Dart SDK**，`flutter analyze` 与 `flutter test` 均未执行。改动经人工通读，括号与缩进已核对。
- 新增用例（未运行）：`test/features/devices/animations_page_test.dart` 断言背景图 118×118、右边与卡片右缘对齐、底边距卡片底缘 14px、上下左右都在卡片矩形内。旧写法下底边会落到卡片外 4px，用例能挡住回归。

## 未完成项与风险

- 需要在有 Flutter SDK 的机器上跑 `flutter analyze` + `flutter test`，并在真机/模拟器上看一眼这张卡。
- 卡片外形高度没变（154），文案区可用高度仍是 126；若之后再压高度，注意图是 118 见方，低于 132 就又会顶到文案区。
