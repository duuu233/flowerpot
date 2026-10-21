# 读取数据去缓存、去延时第二轮（含后端数据）

> 文档类型：Historical Change Record
> 日期：2026-10-21
> 环境：远程 SSH 服务器
> 分支与起始版本：main / 88ecd95
> 范围：消息页、OTA 进度弹层、植物资料、纪念日页、基础数据
> 当前权威文档：PRODUCT_RULES.md §4.26；简明说明 [reports/2026-10-21-读取数据不缓存不延时.md](../../reports/2026-10-21-读取数据不缓存不延时.md)

## 背景与目标

用户要求再次检查：「所有读取到的数据不做任何缓存、延时等机制，就原始赤裸就行，及时展示在 APP 的页面」，并生成简明 .md。干净工作区先 `git pull --ff-only origin main`（已最新）。本机没有 `.codegraph/` 和 flutter/dart 工具链，按源码阅读定位。

全量排查结论：设备 DP、清单、在线、固件、型号等 SDK 读取在同日第一轮已去缓存。剩余项分两类：
- 与已有产品口径冲突的：写入回显保护（亮度 5 秒、割草机 5 秒、普通设置先显示下发值）、消息推送后等 2 秒、OTA 98% 停 0.9 秒（2026-09-18 用户要求）。按 PRODUCT_RULES「冲突先问」询问用户。
- 后端数据缓存：植物目录会话缓存及「查不到」负缓存、纪念日拉取失败显示本机旧列表、基础数据拉到一次就复用。询问范围是否包括后端数据。

用户答复：回显保护保留；消息改为立即拉 + 2 秒补拉；去掉 98% 停留；范围包括后端数据。

## 变更内容

- `DeviceMessagesView`：推送到达立即 `_reload()`，再保留一个 2 秒补拉计时器；`_reloadGeneration` 让并发查询只有最后发起的那次落到页面。
- `ota_progress_dialog.dart`：删除 `_holdAt98`/`_holding`/`_held98` 及 `otaRunningLabel` 的 `stageOverride` 参数，弹层直接用模型 `displayStage` 与百分比。
- `FlowerpotState.ensurePlantProfile`：去掉「目录已有就跳过」与 `_unresolvedPlantIdentifiers` 负缓存，每次调用都拉 `getProductPlantList`；按拉完时设备当前 116 解析；同一株资料对象换新时也替换显示。`_applyDeviceUpdate` 只在报文带 116（或整台设备信息）时补拉，避免每条传感器上报都打接口。新增 `_localPlantFor`：本机选过的植物只在与当前 116 一致（或设备未报 116）时显示，`_withLocalOverrides` 同口径。
- `refreshMemorials` 不再吞错；新增 `memorialsFromBackend`。`MemorialPage` 接后端时先显示加载，失败显示 `AppLoadStateView` 错误态与重试，成功才显示列表；未接后端行为不变。本机 `deviceMemorials` 仍保存，但接后端时不参与显示。
- `loadBasicData` 去掉 `refresh` 参数，每次调用都拉；`MinePage` 调用同步更新。失败仍保留本次登录上一次拉到的值。
- 测试：`device_other_settings_page_test` 两处去掉 98% 停留断言；`mower_messages_history_test` 改为推送后立即 +1、2 秒后再 +1；`state_basic_data_refresh_test` 改为每次现拉；新增 `state_backend_integration_test`「植物资料每次现拉；设备换报目录里没有的 116 时不拿上一株顶替」、`memorial_page_test`「接了后端时拉取失败显示重试，不拿上次拉到的旧列表顶替」。
- 文档：PRODUCT_RULES §4.26（标题与条目）、§4.10/§4.15 消息刷新表述、AI_CONTEXT、OTA_实现说明、MOWER_MACHINE_LOGS、MOWER_DP_GAP_REPORT、UI/MINE_PAGE_IMPLEMENTATION、上一份简明说明的保留项指向、docs/README 与 history 索引。

## 关键决策

- 写入回显保护不是读缓存，去掉会重现亮度回跳，用户确认保留。
- 消息「立即 + 补拉」而不是「只立即」：云端入库晚于推送时，只立即拉会漏掉这条新消息。
- 植物目录接口分页，不能用一次拉取整表替换内存目录；后台删除或改标识的植物在本次登录内可能仍匹配。
- 植物资料与基础数据拉取失败时保留本次登录已拉到的内容，页面不变空；纪念日按用户选择显示失败与重试。
- 花盆未上报 DP 按 0/出厂默认显示属于「无数据」显示口径，本轮未改，在简明说明中列为待确认。

## 外部操作

无。未连接设备、后台或平台，未改依赖与原生代码。

## 验证结果

本机无工具链：**没有运行** `flutter test`、`flutter analyze`、`dart format`。仅人工走查：逐处核对改动的调用方（`otaRunningLabel` 两处、`loadBasicData` 五处、`refreshMemorials` 四处、`ensurePlantProfile` 四处）、受影响用例的时序假设，以及业务仓信息隔离检查。待有工具链时执行简明说明第 7 节的命令。

## 未完成项与风险

- 测试、静态分析、格式化、真机验收均待执行。
- `memorial_page_test` 新用例依赖 `pumpAndSettle` 在加载完成后结束；若加载动画或 SharedPreferences 时序与预期不同需调整。
- 设备在 116 无法解析时，每次带 116 的上报都会拉一次植物目录。

## 回滚或恢复

撤销本次提交即可恢复第一轮后的状态（消息 2 秒延时、98% 停留、植物目录缓存、纪念日本机兜底、基础数据复用）。不涉及后端数据、平台配置或固件。
