# 定制动画：操作按钮改底部悬浮，有图才画删除与取消

> 文档类型：Historical Change Record
> 日期：2026-09-10
> 环境：SSH（无 Flutter/Dart 工具链）
> 分支与起始版本：main / 4eabac5
> 范围：`lib/src/features/devices/presentation/animations_page.dart`、`test/features/devices/animations_page_test.dart`
> 当前权威文档：`docs/UI/v2/智能花盆ysplanter/定制动画-已上传图片（图库管理）.png`（有图态）、`docs/UI/定制动画.png`（空态）、`AI_CONTEXT.md`

## 背景与目标

先核对页面和 v2 设计稿的差距，再按产品这轮的要求改：

1. 上传按钮悬浮固定在页面底部。
2. 「删除选中」「取消选择」只有在已经有上传的图片时才出现。
3. 其余按 v2 设计稿；顶部「仅支持屏幕录制或本地文件。点击这里重新授权」那条权限提示不需要。

核对结果（改动前）：

- v2 那张卡（三列缩略图 + 右上角勾选圈 + `6/10` 计数 + 一排三个圆按钮 + 长按置顶）2026-09-04 就已经落地。
- 顶部权限提示条和右上角「文件同步」按钮 2026-09-08 已按产品口径整体下线，本轮无需再动；提示卡第一条也在那次由「支持屏幕录制文件或本地文件上传」改成「支持本地图片文件上传」。
- **唯一和 v2 对不上的地方**：虚线「上传文件」位一直常驻，有图时它还压在图库卡上面，而 v2 那一屏没有这块。

## 变更内容

- `AnimationsPage.build` 的 body 由单个 `CustomScrollView` 改为 `Stack`：滚动内容 + 底部 `Positioned` 的 `_GalleryActionBar`。
- 新增 `_GalleryActionBar`：上传按钮常驻，`hasFiles` 为真时才追加「删除选中」「取消选择」。三颗按钮的可用性判断（`busy` / 数量上限 / 有没有选中）上移到页面，条子只收 `VoidCallback?`。
- `_UploadedFilesCard` 去掉卡内那排圆按钮，连带去掉 `busy` / `onUpload` / `onDeleteSelected` / `onClearSelection` 四个入参，只剩网格。
- 虚线上传位 `_UploadCard` 改为**只在图库为空时**画，对齐 v2；它的副标题不再有「文件数量已达到上限」分支——只在空态出现，这句永远轮不到，而 `busy` 期间显示它是错的。
- 滚动内容底部内边距由写死的 40 改为 `_GalleryActionBar.height + AppSpacing.xxl`（= 56 + 12×2 + 24 = 104），保证滚到底时最后一行缩略图不会钻到按钮下面。
- `_GalleryAction` 提出 `diameter = 56` 常量供条子算高度，并在可用时加 `elevation: 4`——按钮离开白卡片、浮在内容之上，没有投影会和缩略图糊在一起。

## 关键决策

- **虚线上传位留作空态，不删**。`docs/UI/定制动画.png` 画的就是 `0/10` 时的这一屏，删掉空态只剩一张提示卡。有图时按 v2 让位给网格，上传入口由底部那颗常驻按钮承担，两态都有明确的上传去处。
- **悬浮条用 `Stack` + `Positioned`，不用 `Scaffold.bottomNavigationBar`**。`AppBottomActionBar` 是不透明白底、给整宽主按钮用的（当前仓库里没有调用方），而这里要的是三颗圆按钮浮在页面渐变背景上。`AppPageScaffold` 已经把 body 包在 `SafeArea` 里，条子贴 `bottom: 0` 正好落在 Home Indicator 之上。
- **条子底色用透明到 `canvas` 的渐变**，不铺实底：缩略图从按钮下面滚过去时把它压淡，圆按钮才始终看得清。`DecoratedBox` 自己不参与命中测试，条子空白处的点击和拖拽仍然会落到下面的滚动区。
- **数量满 10 张时上传按钮置灰**，不改成点了弹提示：图库卡上方就是 `10/10` 计数，灰按钮和「删除选中」没选中时的灰是同一套语义。
- **「文件同步」按钮和权限提示条不恢复**——那是 2026-09-08 的产品决定，本轮要求里也明确说提示条不需要。

## 外部操作

无。未连真机。

## 验证结果

- 本机（SSH 开发机）**没有 Flutter/Dart SDK**，`dart format`、`flutter analyze`、`flutter test` 一条都没跑。
- 已做的静态自检：改动过的两个文件跑了自写的 Dart 感知括号配平检查（跳过注释、字符串、原始串和 `${}` 插值），均平衡；改动逐行通读，`_UploadedFilesCard` 删掉的四个入参在仓库里已无其他调用方。
- 测试改动（**未运行**）：
  - 空态用例补断言——底部只有 `animation-upload-action`，`animation-delete-action` 与 `animation-clear-selection-action` 都不画。
  - 新增「有图时画图库网格，虚线上传位让位给它」：`AnimationsPage.uploadZoneKey` 不存在、`animation-file-count` 为 `1/10`。
  - 新增「有图才画删除选中与取消选择，上传按钮一直在」。
  - 新增「底部按钮悬浮固定，滚到底最后一行也不会被压住」：9 张图 + 320×568 矮屏，拖动后首格上移而按钮矩形不变，拖到底后末格底边不超过按钮条顶边——这条正是用来挡住底部内边距算错的回归。
  - 删除旧用例 `uploaded files appear and can be deleted with a long press`：它断言的是 `find.text('demo.gif')` 和长按即删，而 2026-09-04 换成网格后格子里根本不画文件名、长按也改成了置顶（DP 157），这条用例从那时起就和实现对不上。

## 未完成项与风险

- 需要在有工具链的机器上补跑 `dart format lib test`、`flutter analyze lib test`、`flutter test`，并在真机/模拟器上看一眼两态的版式与安全区。
- 提示卡第二条写的是「长按文件可删除已选文件」（照 v2 设计稿），但实现里长按是**置顶**（DP 157），图库卡副标题也写着「长按可置顶」——同一屏两句话互相打架，文案该按哪边改需要产品确认，本轮没动。
- 悬浮条固定 56×3 按钮 + 20 间距，最窄按 320 宽算占 208，两侧还剩富余；再加按钮或换更大的圆需要重新核对窄屏。
