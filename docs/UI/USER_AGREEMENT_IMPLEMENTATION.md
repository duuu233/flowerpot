# 用户协议 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma 的“用户协议”画板。

## 兄弟项目参考

法律长文的章节数据结构和滚动正文组织参考同目录兄弟项目 `D:\Work\learn\flutter` 的 `features/settings/presentation/user_agreement_page.dart` 与 `legal_document_view.dart`。页面视觉仍完全采用 YSplanter 当前 Figma 和本项目 Design Token。

## Page

- 文件：`lib/src/features/profile/presentation/legal_page.dart`
- 路由：`AppRoutes.agreement`，路径为 `/legal/agreement`。
- 用户协议与隐私政策复用同一个 Material 3 `LegalPage`，通过 `privacy: false` 选择用户协议模型。
- 页面使用 `AppPageScaffold`、`AppPageHeader`、`AppBackButton` 和 `ResponsiveContent`。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `LegalDocumentCard` | `lib/src/features/profile/presentation/widgets/legal_document_card.dart` | 半透明长文卡片、协议标题、日期元信息、章节标题与正文排版 |

页面复用隐私政策已经建立的法律文档组件，没有创建重复卡片或页面组件。

## Model 结构

模型文件：`lib/src/features/profile/models/legal_document_page_model.dart`

- `LegalDocumentPageModel.agreement()` 提供 Figma 中的前言、服务说明、账号规则、设备使用、行为规范、知识产权、服务变更、免责声明、协议更新和联系方式。
- `LegalDocumentSection` 继续承载单个章节的标题与正文。

## 图片与资源

本页面为纯文本协议，不需要图片资源，也未裁剪或引用 Figma 截图。

## 尺寸适配与测试

- 375 × 812 为设计基准，复用法律正文卡片的 23px 页面边距和 17px 卡片内边距。
- 320 × 568 紧凑视口支持完整纵向滚动，正文和日期栏不溢出。
- Widget 测试覆盖 Figma 首屏文案、滚动至最后章节和紧凑视口。

## 内容说明

当前协议正文依据 Figma 展示内容和产品功能整理为静态模型；正式发布前仍应由法务根据实际运营主体、服务范围、争议解决方式和联系方式完成审核。

## 校验状态

- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 164 项测试。
