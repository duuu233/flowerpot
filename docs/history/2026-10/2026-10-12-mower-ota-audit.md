# Android 割草机 OTA 耗时与差分配置核查

> 文档类型：Historical Change Record
> 日期：2026-10-12
> 环境：办公室 / work
> 分支与起始版本：main / d15eef0974d01e138f91c37238157d4ee6ad6d4d
> 范围：割草机 OTA 发起、Android 回调、共享状态与完成弹层；仅文档改动
> 当前权威文档：[OTA 实现说明](../../OTA_实现说明.md) §2、§5、§6；产品规则 §4.14；割草机协议 V2.6 §7.2/7.3

## 背景与目标

用户反馈 Android 同一台割草机在本 App OTA 约 4–5 分钟，涂鸦自有 App 约 1 分钟多；是否设备早已完成而 UI 等待尚不清楚。要求核查进度上报与差分标识，并对照涂鸦 AI 给出的 60 秒超时、自动重试、默认差分及关闭通知的解释。

## 变更内容

仅更新 OTA Active 文档、文档入口与历史索引。本轮未改运行时代码、依赖、平台配置或设备固件；不生成 APK。

核查模块：Android `MainActivity.checkFirmware/startFirmwareUpgrade/otaListenerProxy/emitOta/otaInstance`，Flutter `FlowerpotState.upgradeFirmware/_applyOtaProgress/_confirmOtaByReportedVersion/_confirmOtaByResultDp`，共用升级入口与进度弹层，以及 `MowerDevice._readSnapshot`。

## 关键决策与发现

- 两个用户询问的 C 标识归设备 TuyaOS，App 源码无显式调用/赋值；仓库没有割草机固件，不能据此判断设备开关状态。
- Android Home SDK 为 7.5.1，Expansion 为 7.8.0。OTA 按 SDK 原生流程立即启动；进度回调实际签名 `(int, int)` 与桥接取末位数字一致。没有 App 自写下载、分片、烧录，也没有超时后自动重启 OTA 的循环。
- 从本机 7.5.1 `thingsmart-device-api` AAR 核实 `IOtaListener`：当前漏接 `onTimeout(int)` 和 `onFailureWithText(int, String, OTAErrorMessageBean)`。这是确定的终态覆盖缺口，可能导致失败时仍等待，尚不是本次耗时差异的已证根因。
- 割草机 DP112 仅在当前升级仍 running 且进入安装阶段（≥98% 或 stage 6）时可兜底，必须本条上报含版本且等于 pending 目标；提前到达的版本上报不会被随后阶段重验。产品先前明确要求阶段限制，本轮不擅自放宽。
- DP116 的实时拒绝/失败仅提示，没有结束共享 OTA 状态。DP168 是花盆的结果上报，割草机不使用；修正文档遗漏。
- 10 分钟是事件静默后的停滞判断阈值，900ms 是显示过渡，不能作为 4–5 分钟等待的解释或下载提速手段。
- 官方文档中确有特定方案的 60 秒超时，但未证明当前 PID 的实际设置或自动重试；差分需要固件能力、对应版本差分包和平台启用，不能认定智能生活默认差分、SDK App 默认全量。
- 设备 `notify=FALSE` 是把进度上报责任从 SDK 交给设备应用层；不能仅为提速关闭。缓冲、Flash、校验优化亦在设备侧，须依据实际时序。

官方依据与最小采集表已放入 OTA Active 文档 §6，便于后续实测沿用。

## 外部操作

- 核实干净工作区、origin 同名远端分支，开始前显式 `git pull --ff-only origin main` 成功，基线 d15eef0。
- `codegraph sync .` 最新；结构定位先用 CodeGraph，随后读取当前源码。只读解析本机 SDK 缓存 AAR；没有下载或升级 SDK。
- 阅读涂鸦设备/平台官方文档，未登录或修改云平台。
- `adb devices -l` 没有连接设备；启动了正常 adb 服务，未安装/升级设备。

## 验证结果

`flutter test --no-pub test/state_ota_test.dart test/tuya/device_updates_test.dart test/app/firmware_reminder_test.dart --reporter expanded`：44 项中 42 通过、2 失败。首次 compact 输出截断，改 expanded 保存完整输出以核实失败。

两个失败在本轮无代码改动的基线上可复现：

1. `OTA is not a function point; only the version reports are`：期望无 OTA 功能点，实际已含 `ota_result`，断言与新增 DP168 口径不一致。
2. DP168 success 用例：成功后期望设备版本为 `1.1.0`，实际仍为 `1.0.0`，版本显示收尾另有待查；不能据此推断割草机速度。

既有失败如实保留，不宣称回归全绿。文档链接、`git diff --check` 和信息隔离自查完成后按仓库流程提交、再 pull 与 push；最终提交见 Git 记录。

## 未完成项与风险

需实际设备日志、平台部署/包类型与固件配置，核实差分是否启用、进度报告方以及耗时阶段。确定的回调覆盖缺口和 DP116 收尾可作为下一轮代码修复目标；任何成功判定调整应先核对组件/版本契约与真机时序。本轮没有证据承诺缩短至 1 分钟。

## 回滚或恢复

本轮为文档核查，可回退对应文档提交；没有 OTA、刷机、发布或依赖升级动作。
