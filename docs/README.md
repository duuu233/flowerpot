# 项目文档导航

- [2026-10-19 OTA 准备阶段与恢复](history/2026-10/2026-10-19-mower-ota-preparing-recovery.md)：Android Service、状态查询兜底、终态与停滞提示，未真机。

- [2026-10-16 割草机离线交互与充电文案](history/2026-10/2026-10-16-mower-offline-dialog-charging-copy.md)：撤回整页只读，操作弹离线提示，未充电不显示状态词。

- [2026-10-16 修边独立与纪念日内容二选一](history/2026-10/2026-10-16-schedule-edge-memorial-content.md)：复制只影响时段，切换保留草稿，保存只提交当前内容。

> 文档类型：文档治理入口
> 状态：Active
> 最后核验：2026-09-05
> 事实来源：当前源码、CodeGraph、项目配置与下列文档

本文件是 `docs/` 的统一导航。根目录保留执行规则 `AGENTS.md`、当前 AI 快照 `AI_CONTEXT.md` 和现有的结构入口 `PROJECT_STRUCTURE.md`；其余知识、平台手册、UI 规范和历史记录统一从这里查找。

本轮构建：[用户版 Android 打包与兼容说明](USER_RELEASE_BUILD.md)。更改记录：[2026-10-16 用户版调试总闸](history/2026-10/2026-10-16-user-release-build.md)。

此前修复：[2026-10-15 DP117状态含义文案](history/2026-10/2026-10-15-mower-dp117-status-labels.md)。

此前修复：[2026-10-15 割草机消息按标题分类](history/2026-10/2026-10-15-mower-message-title-categories.md)。

此前修复：[2026-10-15 恢复割草机涂鸦历史消息](history/2026-10/2026-10-15-mower-cloud-message-history.md)。

此前修复：[2026-10-15 首页居中与消息独立页面](history/2026-10/2026-10-15-mower-home-messages-layout.md)。

此前修复：[2026-10-15 割草机计划星期与消息首页交互](history/2026-10/2026-10-15-mower-schedule-messages-home.md)。DP101星期布局以产品确认的功能点备注为准，详见[MOWER_SCHEDULE_DP.md](MOWER_SCHEDULE_DP.md)。

本轮核查：[2026-10-14 割草计划DP来源与下发](history/2026-10/2026-10-14-mower-schedule-dp-source-audit.md)。此前修复：[2026-10-14 复制整周与修边](history/2026-10/2026-10-14-mower-copy-week-edge.md)。此前修复：[2026-10-14 离线门禁与割草机继续](history/2026-10/2026-10-14-offline-controls-mower-resume.md)。此前外观核验：[2026-10-14 割草计划可见滚动条](history/2026-10/2026-10-14-visible-mower-plan-scrollbar.md)。此前修复记录：[2026-10-14 设备在线状态唯一来源](history/2026-10/2026-10-14-device-online-sdk-only.md)。此前修复记录：[2026-10-14 弹框长内容与滚动](history/2026-10/2026-10-14-dialog-scroll-audit.md)。此前修复记录：[2026-10-13 仅业务码 406 清除 APP 后端会话](history/2026-10/2026-10-13-backend-session-406-only.md)。此前修复记录：[2026-10-13 OTA 充电条件与故障提示](history/2026-10/2026-10-13-ota-charging-fault-guidance.md)。此前修复记录：[2026-10-13 固件升级弹框切换](history/2026-10/2026-10-13-ota-dialog-sequencing.md)。此前实现记录：[2026-10-12 控制反馈与机器日志初版](history/2026-10/2026-10-12-mower-feedback-machine-logs.md)。此前修复记录：[2026-10-12 割草机 Wi-Fi 恢复原样与状态核查](history/2026-10/2026-10-12-mower-wifi-original-style.md)。此前修复记录：[2026-10-12 割草机 OTA 终态与版本时序修复](history/2026-10/2026-10-12-mower-ota-terminal-fixes.md)。此前检查记录：[2026-10-12 Android 割草机 OTA 与差分核查](history/2026-10/2026-10-12-mower-ota-audit.md)。此前记录：[2026-10-10 割草机 DP115 异常弹窗](history/2026-10/2026-10-10-mower-command-results.md)。此前记录：[2026-10-10 割草机启动安全确认与整小时设置](history/2026-10/2026-10-10-mower-start-safety-duration.md)。此前记录：[设备同类提示一致性](history/2026-10/2026-10-10-device-feedback-consistency.md)。

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
| [`RELEASE_READINESS_REVIEW.md`](RELEASE_READINESS_REVIEW.md) | Tracking | 安全、健壮性、性能与 Android/iOS 发布评审；含源码依据、整改顺序和验证边界。 |
| `DP_GAP_REPORT.html`（本地生成） | Tracking | 功能点实现对照及缺口清单；由 [`../tool/build_dp_gap_report.py`](../tool/build_dp_gap_report.py) 生成。当前工作树没有此 HTML，使用前生成并核对脚本中的表是否跟随最新 DP 导出；改状态请改脚本后重跑。 |
| [`Grass_Master_Automower_Tuya_DP协议_V2.6.md`](Grass_Master_Automower_Tuya_DP协议_V2.6.md) | Reference Contract | 当前割草机协议，DP115回执与拒绝码定义见§4.5/8；已移除的 V2.3/V2.5 通过 Git 历史查阅。 |
| [`MOWER_MACHINE_LOGS.md`](MOWER_MACHINE_LOGS.md) | Active | 控制反馈、code26新鲜DP111、DP事件机器日志初版及逐项真机验收边界。 |
| [`APP机器日志对接表.md`](APP机器日志对接表.md) | Reference Contract | 产品提供的 DP120 事件编号、等级、中英文文案及 DP111 位对照；实现覆盖仍以 MOWER_MACHINE_LOGS.md 为准。 |
| [`涂鸦推送_App机器日志对接说明.md`](涂鸦推送_App机器日志对接说明.md) | Design Reference | 基于 DP 上报流的 App 日志方案与去重规则；不代表全部已实现或真机验收。 |
| [`涂鸦推送_App机器日志方案_分析稿.md`](涂鸦推送_App机器日志方案_分析稿.md) | Analysis Reference | 方案分析及待确认项；已被对接说明取代的部分按文首修订说明查阅。 |
| [`YUSEN Robot Mower(mz7g3yzaufvoh4ls)_10_13.xlsx`](<YUSEN Robot Mower(mz7g3yzaufvoh4ls)_10_13.xlsx>) | Reference Input | 2026-10-13 产品提供的功能点表，作为协议对照输入；本轮未逐项核验固件或 App 实现。 |
| [`MOWER_DP_GAP_REPORT.md`](MOWER_DP_GAP_REPORT.md) | Tracking | 割草机功能点落地差距（与上一行花盆那份同一口径）：协议 V2.6 的 24 个 DP 逐条状态、没接的原因、P0/P1/P2 缺口、待产品 / 固件答复的问题、稿子与协议的空档，以及整体模块流程（入口动线、模块与 DP 分布、下发 / 上报链路）。改了割草机 DP 相关代码后回来改附录 A。 |
| [`TUYA_SDK_SETUP.md`](TUYA_SDK_SETUP.md) | Active Runbook | 涂鸦平台、Android/iOS SDK 和秘密管理要求。 |
| [`BACKEND_TUYA_HOME_ID.md`](BACKEND_TUYA_HOME_ID.md) | Active | 涂鸦家庭 ID 的来源与归属、后端接口需求、双端家庭选择规则、花盆 / 割草机注册共用范围，以及设备丢失时排除家庭问题的证据边界。 |
| [`FLUTTER_PROJECT_ARCHITECTURE.md`](FLUTTER_PROJECT_ARCHITECTURE.md) | Design Reference | 目标架构；与当前源码冲突时不作为实现事实。 |
| [`UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`](UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md) | Active | 本项目 UI 页面和组件实施规范。 |
| [`UI/UI_ASSET_INTEGRATION_PROGRESS.md`](UI/UI_ASSET_INTEGRATION_PROGRESS.md) | Tracking | 图片和图标接入进度。 |
| [`PRODUCT_RULES.md`](PRODUCT_RULES.md) | Active | **产品口径与硬性要求**（必须怎样 / 绝对不要怎样）。动手前先读；与它冲突的改动先停下来问。技术事实在 `AI_CONTEXT.md`，试错过程在 `history/`。 |
| [`OTA_实现说明.md`](OTA_实现说明.md) | Active | 固件升级状态监控：新版本怎么发现（拉取）、升级中状态怎么收（SDK 推送）、兜底与现状缺口，含花盆与割草机差异。 |
| [`TUYA_CAPABILITY_AUDIT.md`](TUYA_CAPABILITY_AUDIT.md) | Active | 项目功能点逐条对照涂鸦官方文档：哪些已用官方 API、哪些涂鸦不支持只能自研、哪些接错了 SDK。 |
| [`reference/`](reference/) | Reference | 涂鸦官方文档的本地存档（AP 热点模式 Android / iOS、扩展 SDK），仅作依据引用，不是本项目口径。 |
| [`更新说明-2026-09-17-第二轮.md`](更新说明-2026-09-17-第二轮.md) | Historical | 2026-09-17 第二轮的速览（定制动画改单选、日报表一次拿 7 天并按日期左右切；上传压缩那条本轮只核对未改）。 |
| [`更新说明-2026-09-17.md`](更新说明-2026-09-17.md) | Historical | 2026-09-17 那一轮改了哪些地方的速览（上传图片改成设备口径 Baseline 4:2:0 / 320×240 / 500KB，DP165 按 2 字节解）。 |
| [`更新说明-2026-09-16.md`](更新说明-2026-09-16.md) | Historical | 2026-09-16 那一轮改了哪些地方的速览（状态文案、温湿度日历史 164/165、光照默认日 + 折线、上传前压缩）。⚠️ 其中第 5 条「上传前裁剪压缩」的尺寸与失败口径已被 09-17 那份覆盖。 |
| [`history/README.md`](history/README.md) | Active | 本地操作更新记录规则、模板与索引。 |

`FIGMA_DESIGN_ANALYSIS.md` 和 `UI/*_IMPLEMENTATION.md` 是设计分析或页面级说明；使用前核对其日期和当前源码。[`TEMP_STATIC_PAGE_PREVIEW.md`](TEMP_STATIC_PAGE_PREVIEW.md) 描述当前静态演示构建的动线与开关，不承担生产配置说明。原始 DOCX 和 PNG 是输入资料，不是当前代码事实。

当前弹框滚动契约：[UI/DIALOG_SCROLLING.md](UI/DIALOG_SCROLLING.md)。

当前在线状态契约：[DEVICE_ONLINE_STATUS.md](DEVICE_ONLINE_STATUS.md)。

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

本轮资料同步：[2026-10-13 割草机参考资料](history/2026-10/2026-10-13-mower-reference-materials-sync.md)。

记录路径为 `history/YYYY-MM/YYYY-MM-DD-topic.md`。一次集中修改对应一份记录，不维护无限增长的单文件日志。不得记录 Token、涂鸦密钥、安全组件、签名资料、Wi-Fi 密码、个人数据或完整本地配置。

最近记录：[割草机 OTA 终态与版本时序修复](history/2026-10/2026-10-12-mower-ota-terminal-fixes.md)。此前记录：[`history/2026-10/2026-10-10-mower-stability-plan-confirmation.md`](history/2026-10/2026-10-10-mower-stability-plan-confirmation.md)。此前记录：[`history/2026-10/2026-10-09-mower-home-loading-wifi.md`](history/2026-10/2026-10-09-mower-home-loading-wifi.md)。此前同日记录：[`history/2026-10/2026-10-09-mower-plan-delete-confirmation.md`](history/2026-10/2026-10-09-mower-plan-delete-confirmation.md)。

此前记录：[`history/2026-09/2026-09-21-我的页去掉设备设置-反馈邮箱读platformEmail-关于改智能设备.md`](history/2026-09/2026-09-21-我的页去掉设备设置-反馈邮箱读platformEmail-关于改智能设备.md)。

当前割草计划DP来源与下发契约：[MOWER_SCHEDULE_DP.md](MOWER_SCHEDULE_DP.md)。
