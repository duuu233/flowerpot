# 隐私政策 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma 的“隐私政策”画板。

## 兄弟项目参考

法律长文的标题、更新与生效日期、分节数据结构和滚动正文组织参考同目录兄弟项目 `D:\Work\learn\flutter` 的 `features/settings/presentation/privacy_policy_page.dart` 与 `legal_document_view.dart`。页面视觉仍完全采用 YSplanter 当前 Figma 和本项目 Design Token。

## Page

- 文件：`lib/src/features/profile/presentation/legal_page.dart`
- 路由：隐私政策使用 `AppRoutes.privacy`，路径为 `/legal/privacy`；用户协议继续使用 `AppRoutes.agreement`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton` 和 `ResponsiveContent`。
- 同一 Page 根据 `privacy` 参数选择对应文档模型，避免复制两套法律长文页面。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `LegalDocumentCard` | `lib/src/features/profile/presentation/widgets/legal_document_card.dart` | 半透明长文卡片、文档标题、日期元信息、章节标题与正文排版 |

正文容器复用 Design System 的 `AppSurfaceCard`，颜色、圆角、字体和间距均来自现有 Token。

## Model 结构

模型文件：`lib/src/features/profile/models/legal_document_page_model.dart`

- `LegalDocumentPageModel`：页面标题、文档标题、更新日期、生效日期和章节集合。
- `LegalDocumentSection`：单个章节的标题与正文。
- `privacy()` 与 `agreement()` 工厂分别提供隐私政策和用户协议内容，两者复用相同 Page 与 Widget。

## 图片与资源

本页面为纯文本法律文档，不需要图片资源，也未裁剪或引用 Figma 截图。

## 尺寸适配与测试

- 375 × 812 为设计基准，正文卡片左右边距 23px，卡片内边距 17px。
- 正文使用纵向滚动，固定页面标题不会随长文丢失。
- 320 × 568 紧凑视口支持完整滚动，无固定高度和不可达内容。
- Widget 测试覆盖 Figma 首屏内容、末尾章节滚动、用户协议兼容和紧凑视口。

## 内容说明

当前正文依据 Figma 展示内容和产品功能整理为静态模型；正式发布前仍应由法务根据实际主体、服务器区域、第三方 SDK 清单和联系方式完成审核。

## 校验状态

- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 113 项测试。
