# 建立 AI 上下文与 CodeGraph 长期维护机制

> 文档类型：Historical Change Record
> 日期：2026-08-12
> 环境：本地工作区
> 分支与起始版本：`main` / `23c94e4`
> 范围：文档治理、AI 上下文、CodeGraph 工作流
> 当前权威文档：[`AI_CONTEXT.md`](../../../AI_CONTEXT.md)、[`docs/README.md`](../../README.md)、[`AGENTS.md`](../../../AGENTS.md)

## 背景与目标

原 `AI_CONTEXT.md` 仍是 TODO，`docs/` 已包含大量架构、平台和 UI 资料，却缺少统一入口和长期操作更新记录。目标是依据当前 Flutter 源码和 CodeGraph 建立项目专属快照、文档状态与按日期归档的维护机制。

## 变更内容

| 文件或模块 | 变更 |
| --- | --- |
| `AI_CONTEXT.md` | 填写 Flutter 客户端架构、Mock/真实 SDK 边界、风险和跨项目同步规则。 |
| `AGENTS.md` | 增加知识来源、CodeGraph 同步、历史记录和跨环境交接要求。 |
| `docs/README.md` | 对现有架构、PRD、涂鸦和 UI 文档建立状态化导航。 |
| `docs/history/` | 建立按月归档的一次性操作记录与模板。 |

## 关键决策

- 现有大量文档不整体迁移或改写，先由统一索引明确其职责和可信边界。
- CodeGraph 管理当前源码关系，Active/Tracking 文档管理契约和进度，Historical 只用于追溯。
- 与两个 Web 兄弟项目同步维护方法，但不复制 Flutter、涂鸦、DP、移动构建或签名规则。

## 外部操作

无 SDK 平台写入、部署、签名或设备操作。没有读取或记录任何实际密钥。

## 验证结果

- `codegraph sync .`：已把任务开始前工作区中已有的源码删除与迁移同步到本机索引。
- `codegraph status .`：264 files、3,085 nodes、8,507 edges，索引为最新。
- CodeGraph 已确认 `FlowerpotApp → FlowerpotState → TuyaRepository`、命名路由和 Mock/MethodChannel 分流。
- 本次仅修改 Markdown；未运行 Flutter 构建或测试。
- 新增治理文档的相对链接检查通过；未发现粘贴凭证或行尾空白。
- `git diff --check`：通过；任务开始前已有的源码、平台、资源和测试改动保持不变。

## 未完成项与风险

- 当前工作区已有大量 UI、资源、路由、平台和测试改动，本次未覆盖、恢复或整理这些改动。
- 真实涂鸦 SDK、DP、OTA、分享和平台签名仍需平台参数及真机验证。

## 回滚或恢复

本次新增内容均为 Markdown，可按文件回退。回退时不得影响本任务开始前已有的用户工作区改动。
