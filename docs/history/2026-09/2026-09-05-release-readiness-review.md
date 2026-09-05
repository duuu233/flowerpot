# Android/iOS 发布、健壮性与性能评审

> 文档类型：Historical Change Record
> 日期：2026-09-05
> 环境：Windows / PowerShell，D:\work\flowerpot
> 分支与起始版本：main / 2a8b5a336216d0cc4fb12a9e90cb8a3ff352b038
> 范围：客户端安全、会话、配网、性能与双端平台准备度
> 当前权威文档：[发布评审](../../RELEASE_READINESS_REVIEW.md)、[SDK 接入](../../TUYA_SDK_SETUP.md)

## 背景与目标

根据文档检查优化空间、漏洞风险、健壮性及 Android/iOS 接近原生体验的路径，给出可以据此实施的建议。起始工作树干净。

## 变更内容

- 新增 `docs/RELEASE_READINESS_REVIEW.md`，区分源码确认、测试复现、待真机验证和性能建议，附优先级与验收方式。
- 修正 `AI_CONTEXT.md`、`docs/COMMON_MODULES.md` 关于未配置 API 地址即禁用后端的旧描述；明确当前 HTTP 回落和测试需要单独注入后端。
- 修正 `docs/TUYA_SDK_SETUP.md` 的 iOS SDK 版本、DP 表 PID/范围及纪念日后端同步描述。
- 修正 `docs/PRD_IMPLEMENTATION.md` 的头像接入状态和旧 HTTPS 故障口径；HTTPS 恢复只引用既有 09-03 记录，本轮未重新探测服务器。
- 更新文档与历史索引；链接核验发现本地生成的 DP_GAP_REPORT.html 缺失，索引改为说明生成入口及核验要求。没有修改 Dart/Kotlin/Swift、平台配置、依赖或签名材料。

## 关键决策

保留 Flutter + 原生桥接及既有 UI 设计，优先关闭生产安全风险，再处理会话/取消/重试与真实 SDK 发布闭环，最后按 Profile 数据优化启动和通知边界。发现 Git 跟踪的安全组件副本后，仅记录路径与管理缺口；未读取内容、移除跟踪、删除文件或改写历史。

## 外部操作

只读查阅 Flutter、Android、Apple 和 shared_preferences 官方文档，来源链接保存在评审正文。Flutter 分析和测试获准在沙箱外执行，以使用工作区外的工具链。未调用业务服务器写接口、未发短信、未控制设备、未发布或提交 Git。

## 验证结果

- Flutter 3.44.6 / Dart 3.12.2；使用本机既有依赖执行 `--no-pub`。
- `codegraph status .`：索引最新。通过 CodeGraph 定位网络、State、事件及原生调用路径，再做定点源码核对。
- `flutter analyze --no-pub`：退出码 1，2 warning / 1 info，无编译级 error。位置为 memorial_edit_page:306、pairing_page:364、app_backend_repository:831。
- 首次全量 `flutter test --no-pub --reporter compact`：计数到 271 通过、32 失败后数分钟不再输出，未正常结束；发出中断后子进程仍存在。
- 为判断卡住情况，复核 `flutter test --no-pub --timeout 60s --reporter expanded`：同样计数到 271 通过、32 失败后未退出；单项超时未解决进程收尾问题。两次均不是完整通过报告。通过核对 PID、父子关系和命令行，清理本轮遗留测试进程，保留编辑器 Flutter daemon。
- 配网退出用例明确复现 widget tree locked：dispose → cancelPairing → 同步通知。OTA 多项失败的 helper 未调用 initialize 建立订阅，应先修测试初始化；未据此判定真机 OTA 损坏。其余失败含旧 UI 文案/元素断言，尚未逐项归因。
- 源 assets/images：103 个文件，约 4.34 MiB；不是发布包体积或运行内存测量。
- 未做 Android 构建、iOS/Xcode 编译、真机性能和端到端测试。文档链接及 `git diff --check` 在交付前核对；没有源代码变更，不需要 CodeGraph sync。

## 未完成项与风险

评审中列出的代码整改全部待实施；测试未正常退出原因尚未确定。业务服务器授权、安全组件历史传播、SDK 采集行为、依赖可利用漏洞、16KB 原生库兼容及 iOS 最终隐私清单均需要专项验证。不要将本次文档修订当作风险已关闭。

## 回滚或恢复

本轮只有文档变更，可按本次 diff 撤回。Git 提交是跨电脑共享入口；当前修改尚未提交。本机测试日志位于临时目录 `flowerpot-audit-tests-20260905.log` 与 `flowerpot-audit-tests-bounded-20260905.log`，测试缓存、SDK、安全组件和 `.codegraph/` 为本地状态，不作为交接依赖。本轮未生成 Android/iOS 发布包。
