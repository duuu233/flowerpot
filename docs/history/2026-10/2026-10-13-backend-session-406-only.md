# 仅业务码 406 清除 APP 后端会话

> 文档类型：Historical Change Record
> 日期：2026-10-13
> 环境：办公室（work）
> 分支与起始版本：main / b7dfb72
> 范围：公共网络异常分类、定制动画后端会话与回归
> 当前权威文档：PRODUCT_RULES.md §4.3.1、COMMON_MODULES.md、AI_CONTEXT.md

## 背景与目标

用户反馈定制动画每次上传都提示 APP 后端登录失效，后端没有配置 Token 有效期。
只读核查确认客户端没有 TTL，上传前 Token 为空会发该提示；旧网络层及状态层均把 401 与 406 视为失效。
用户明确「406 才是登录失效，其它不要清除」，本轮按业务字段 retCode 而非 HTTP 状态实施。
没有现场日志或已连接手机，不据此认定先前每次失败的真实接口和响应；也不继续此前暂停的纪念日问题。

## 变更内容

- `ApiClient._parse` 仅业务 406 清 Token / 调用 onSessionExpired；其它错误保留原异常、Token 与持久化值。
- `ApiException.isAuthError` 仅允许业务 406，HTTP 406 的 authError:false 保持普通传输错误，401 即使显式 authError:true 也不能触发状态层清除。
- 状态层继续复用公共分类，只更新相关注释；主动退出/注销及登录失败的一致性处理未改变。
- 新增公共请求策略矩阵和实际 FlowerpotState / HttpAppBackendRepository 的定制动画失败重试回归。
- 更新产品口径、当前技术说明与索引，同时纠正公共模块说明中已陈旧的 HTTP 默认地址 / none 配置描述。

## 外部操作

开始前显式 pull 当前同名 main。仅按用户授权暂存两份本地协议/机器日志文档，pull 后原字节恢复；这两份用户文档不提交。
无真实业务接口请求、发布或部署。之前诊断仅读取公开 Swagger，客户端行为验证均使用捕获请求桩。
交付前同步本机 CodeGraph；提交后再次保护同两份文档、pull 当前 main，再恢复并核验 SHA256 后 push。

## 验证结果

- 五份相关测试共 **61 项通过**：api_client_test、api_safety_test、backend_session_policy_test、app_backend_repository_test、state_backend_session_policy_test。
- 覆盖 GET、JSON POST、multipart 上传的 HTTP/业务码组合，清除回调及持久化；HTTP 401/406、业务 401/403/500 不清 Token，业务 406 仍清除。
- 定制动画实际状态链验证：普通错误后原 Token 可继续上传；406 后下一次上传才被本地会话门禁拦截，涂鸦登录保留。
- 两个核心网络文件及两份新测试 Dart analyze 无问题。首轮新增测试的单条 if 格式提示已修正。
- 三项全库 Dart 自检通过；第四项三元空下标扫描在未改的 mower_device.dart:683 留有既有提示，HEAD 原版隔离扫描同样命中。本轮五份 Dart 文件的该项扫描通过，测试编译成功，不宣称全库第四项通过。
- 差异、新增文档链接与信息隔离检查随交付完成；CodeGraph 同步检查。

## 未完成项与风险

未真机、未打包 APK。非 406 的真实接口错误仍可能导致上传失败，本轮改变的是登录态清除条件，不将普通错误当作成功或跳过鉴权。

## 回滚或恢复

回退本次网络分类与测试提交可恢复旧的 401/406 行为；无需修改后端、涂鸦配置或设备 DP。
