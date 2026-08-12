# UI 参考图复核续作

> 文档类型：Historical Change Record
> 日期：2026-08-12
> 环境：办公室 Windows / Android 12 模拟器
> 分支与起始版本：`main` / `23c94e4`
> 范围：Flutter Design System、首页、植物选择、关于页及关联测试
> 当前权威文档：`docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`、`docs/UI/UI_ASSET_INTEGRATION_PROGRESS.md`

## 背景与目标

继续此前中断的 UI 参考图复核。重点核对 `docs/UI` 中的设计图与当前实现，修正普遍存在的背景偏差，并落实“正式素材优先；缺失图标只用语义色块占位，不手绘复杂图标”的约束。开始时工作树已经包含大量未提交的 UI、资源、路由、平台和测试改动，本次未回退或覆盖这些既有改动。

## 变更内容

- 将 `AppPageBackground.standard` 统一接入正式背景资源 `assets/images/bg01.png`，与设备列表、设置、个人信息等参考图的背景一致；登录类页面继续使用独立的 `auth_background.png`，首页无设备状态继续使用纯白背景。
- 首页顶栏由文字叠加 Material 叶片改为正式 `ysplanter_wordmark.png`。
- “关于 YSplanter”页由 `CustomPainter` 手绘 Logo 和文字叠叶片改为正式 `app_logo.png` 与 `ysplanter_wordmark.png`，删除对应复杂手绘代码。
- 植物选择卡的选中徽标改用正式 `plant_selection_badge_icon.png`；缺失的植物照片仍保持语义色块，没有从 UI 截图裁切或自行绘图。
- 更新关联 Widget 测试：品牌字标改按语义或资产验证，关于页改为验证正式 Logo 与字标资源。

## 关键决策

- 登录页在已运行模拟器中与参考图对照后，面板起点、输入区和按钮字号已经基本一致，因此没有全局缩小 `AppTypography`。后续只调整具有明确截图依据的局部字号，避免破坏已经对齐的页面。
- `bg01.png` 的尺寸和构图与 375 × 812 参考视口一致，普通页面通过共享 Scaffold 复用该资源，不再用代码生成的渐变光斑模拟。
- 功能性图表可以保留绘制逻辑；品牌标识、装饰图标和插画不得继续自行复杂绘制。有正式资产时直接使用，确实缺失时使用简单色块。

## 外部操作

- 使用 CodeGraph 检查 `AppPageScaffold`、`AppPageBackground`、`AppTypography` 和 `AppAssets` 的调用范围；普通背景 Scaffold 约有 35 个页面调用方。
- 使用已连接的 Android 12 模拟器查看当前安装版本的设备列表、预览目录和登录页，并与 `docs/UI` 原图对照。
- 临时截图仅用于本机比对，完成后已从工作区删除，未作为页面资源或跨环境交接内容。

## 验证结果

- `dart format`：8 个本次涉及文件均已格式化，命令报告 0 个额外改动。
- `dart analyze lib test`：通过，`No issues found!`。
- 定向 Widget 测试：主页空设备、主页未添加植物、植物选择、关于页和总入口测试共 21 个用例全部通过。
- 全量 `flutter test --no-pub --reporter compact`：180 个用例全部通过。
- `codegraph sync .` 与 `codegraph status .`：通过，索引为最新。
- 本次未对修改后的新构建执行模拟器截图验收；模拟器中观察的是修改前已安装的版本，只用于确认既有字号比例。

## 未完成项与风险

1. 明天先重新构建/启动应用，让模拟器加载本次代码，再逐页截图核对 `standard` 背景的覆盖、裁切和滚动表现。
2. 继续按 `docs/UI` 的 49 张参考图完成逐页复核，优先检查仍有手写 17–28px 字号的页面；有截图依据再局部下调，不做无差别全局缩放。
3. 继续审计 UI 页面中的 `Icons.*` 和 `CustomPainter`：已有正式资源的替换为资源；缺资源的装饰图标改为语义色块。水位校准插画的资源加载失败分支仍保留复杂 Painter，后续应改为简单色块占位。
4. 下一批页面完成后重新运行全量 `flutter test --no-pub`，并补做修改后新构建的 375 × 812 与 320 × 568 截图检查。
5. `assets/images/bg01.png` 当前仍是未跟踪文件，跨电脑前必须与相关源码一同提交；Git 才是共享事实来源。

## 回滚或恢复

- 如需撤销普通页面背景复用，只回退 `AppPageBackground.assetPath` 中 `standard || home` 的映射，不要重置整个工作树。
- Logo、字标和植物选中徽标的替换均为独立 Widget 级改动，可按文件逐项回退；不要恢复已经删除的复杂品牌 `CustomPainter`。
