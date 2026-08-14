# 本地操作更新记录

> 文档类型：历史记录规范与索引
> 状态：Active
> 最后核验：2026-08-14
> 事实来源：`AGENTS.md` 与项目文档治理约定

本目录补充 Git 提交，记录集中修改的背景、外部操作、验证和未完成项，但不替代源码、提交历史或 Active 文档。文件使用 `YYYY-MM/YYYY-MM-DD-topic.md`，任务完成后冻结。

## 模板

```markdown
# 主题

> 文档类型：Historical Change Record
> 日期：YYYY-MM-DD
> 环境：办公室 / 家庭 / SSH / 其他
> 分支与起始版本：branch / short-sha
> 范围：模块或仓库
> 当前权威文档：相关 Active 文档

## 背景与目标
## 变更内容
## 关键决策
## 外部操作
## 验证结果
## 未完成项与风险
## 回滚或恢复
```

只写实际完成的动作与验证。跨项目同步还要写上游来源、新契约、已同步内容、有意差异和未同步事项。禁止记录任何密钥、Token、签名材料、真实 Wi-Fi 信息、用户数据或完整环境文件。

## 索引

- [`2026-08/2026-08-12-ai-context-codegraph-maintenance.md`](2026-08/2026-08-12-ai-context-codegraph-maintenance.md)：建立项目专属 AI 上下文、文档入口与 CodeGraph/历史记录规则。
- [`2026-08/2026-08-12-ui-reference-reaudit-continuation.md`](2026-08/2026-08-12-ui-reference-reaudit-continuation.md)：续作 UI 参考图复核，统一普通页面背景并清理品牌与选中态的复杂手绘图形。
- [`2026-08/2026-08-13-ui-runtime-visual-alignment.md`](2026-08/2026-08-13-ui-runtime-visual-alignment.md)：在 Android 12 模拟器中复核当前构建，校准主要页面位置、状态摘要卡与资源失败占位。
- [`2026-08/2026-08-14-android-split-release-build.md`](2026-08/2026-08-14-android-split-release-build.md)：解除 Flutter ABI 拆分与应用层 ABI 过滤冲突，生成并校验三个 release APK。
