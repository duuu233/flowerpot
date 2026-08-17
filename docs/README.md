# 项目文档导航

> 文档类型：文档治理入口
> 状态：Active
> 最后核验：2026-08-14
> 事实来源：当前源码、CodeGraph、项目配置与下列文档

本文件是 `docs/` 的统一导航。根目录保留执行规则 `AGENTS.md`、当前 AI 快照 `AI_CONTEXT.md` 和现有的结构入口 `PROJECT_STRUCTURE.md`；其余知识、平台手册、UI 规范和历史记录统一从这里查找。

## 推荐阅读顺序

1. `AGENTS.md`
2. `AI_CONTEXT.md`
3. 本文件
4. 与任务相关的 Active/Tracking 文档
5. CodeGraph 中的当前源码和调用链
6. 仅在需要理解原因时读取 Historical 记录

## 当前知识入口

| 文档 | 状态 | 职责 |
| --- | --- | --- |
| [`../PROJECT_STRUCTURE.md`](../PROJECT_STRUCTURE.md) | Active | 当前目录、分层和主要模块。 |
| [`COMMON_MODULES.md`](COMMON_MODULES.md) | Active | 已复用的网络、会话、校验和共享能力及产品边界。 |
| [`PRD_IMPLEMENTATION.md`](PRD_IMPLEMENTATION.md) | Tracking | PRD 功能落地和平台待联调项。 |
| [`TUYA_SDK_SETUP.md`](TUYA_SDK_SETUP.md) | Active Runbook | 涂鸦平台、Android/iOS SDK 和秘密管理要求。 |
| [`FLUTTER_PROJECT_ARCHITECTURE.md`](FLUTTER_PROJECT_ARCHITECTURE.md) | Design Reference | 目标架构；与当前源码冲突时不作为实现事实。 |
| [`UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`](UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md) | Active | 本项目 UI 页面和组件实施规范。 |
| [`UI/UI_ASSET_INTEGRATION_PROGRESS.md`](UI/UI_ASSET_INTEGRATION_PROGRESS.md) | Tracking | 图片和图标接入进度。 |
| [`history/README.md`](history/README.md) | Active | 本地操作更新记录规则、模板与索引。 |

`FIGMA_DESIGN_ANALYSIS.md` 和 `UI/*_IMPLEMENTATION.md` 是设计分析或页面级说明；使用前核对其日期和当前源码。[`TEMP_STATIC_PAGE_PREVIEW.md`](TEMP_STATIC_PAGE_PREVIEW.md) 描述当前静态演示构建的动线与开关，不承担生产配置说明。原始 DOCX 和 PNG 是输入资料，不是当前代码事实。

## CodeGraph 与文档的边界

- 当前文件、符号、依赖、调用链和影响范围：源码与 CodeGraph。
- 产品口径、DP/平台契约、人工流程、UI 规范和发布要求：最新 Active 文档。
- 功能覆盖状态：Tracking 文档，并核对最后核验日期。
- 修改原因：对应 Historical 记录。

```bash
codegraph status .
codegraph explore 要理解的问题、文件或符号
codegraph sync .
```

拉取后运行 `codegraph sync .`；结构性源码修改后再次同步并检查状态。完整 `index` 只在索引缺失、损坏或工具建议时运行。`.codegraph/` 每台机器自行建立，永不提交。

## 文档生命周期

- `Active`：描述当前事实，直接更新正文，不追加流水账。
- `Tracking`：持续维护的进度清单，必须标明最后核验日期。
- `Design Reference`：目标方案或参考，不自动代表已经实现。
- `Historical`：一次任务结束后冻结，只用于追溯。
- `Superseded`：已被替代，开头必须链接新的权威文档。

新增、移动或替代文档时同步更新本索引。若文档与代码冲突，先通过源码和 CodeGraph 确认当前行为，再修正负责该事实的 Active 文档，并为实质性调整建立历史记录。

## 历史记录

记录路径为 `history/YYYY-MM/YYYY-MM-DD-topic.md`。一次集中修改对应一份记录，不维护无限增长的单文件日志。不得记录 Token、涂鸦密钥、安全组件、签名资料、Wi-Fi 密码、个人数据或完整本地配置。

最近记录：[`history/2026-08/2026-08-17-tuya-android-release-signing-validation.md`](history/2026-08/2026-08-17-tuya-android-release-signing-validation.md)。
