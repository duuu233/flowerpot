# 割草机 OTA 终态与版本时序修复

> 文档类型：Historical Change Record
> 日期：2026-10-12
> 环境：办公室 / work
> 分支与起始版本：main / 7ce31b366b87e592c137b7b97c749ddf5f026f43
> 范围：Android OTA 回调桥接、共享 OTA 状态、实时设备 DP 与相关测试
> 当前权威文档：[OTA 实现说明](../../OTA_实现说明.md)；[产品规则](../../PRODUCT_RULES.md) §4.14；[割草机功能覆盖](../../MOWER_DP_GAP_REPORT.md)

## 背景与目标

前一轮核查发现三项确定缺口，用户授权优化：Android 漏接超时/文本失败；DP112 提前上报未在安装阶段重验；DP116 拒绝/失败只提示，弹层仍等待。改善客户端收尾，不将它们直接认定为同设备 4–5 分钟与涂鸦 App 1 分钟多的全部根因。

## 变更内容

- `TuyaOtaListenerBridge.kt` 集中映射实际 SDK 7.5.1 `IOtaListener`，补 `onTimeout` / `onFailureWithText`；文本取 bean 正文、标题、默认原因。原进度参数顺序、进行中阶段码与旧回调兼容。
- `MainActivity.kt` 每次发起分别保证方法回答与终态只处理一次，成功/失败释放 SDK OTA 实例。
- `DeviceUpdate.reportedDps` 携带本条实时 DP 原值；仓库不从历史整包快照制造新 DP 事件，避免旧 DP116 错误误杀升级。
- `FlowerpotState` 在原生启动前初始化本次 OTA，保留即时进度/成败，启动抛错结束等待。仅记录本次开始后真实上报的版本，进入安装阶段（≥98% 或 stage 6）再比较目标；不同/无效后续版本替换/清除证据。开始、重试、清理、收尾、退登、移除设备均清除。
- 本次进行中的割草机升级收到实时 DP116=7/20 立即失败，可关闭弹层，不依赖页面打开。同条错误与目标版本优先错误；SDK 与 DP 第一份终态生效。
- 最新设备快照先写入再执行 OTA 收尾，修复目标版本被旧快照覆盖；花盆 DP168 原有口径保留。
- 状态/事件/升级入口相关测试扩充；页面夹具暂停轮询、等待滚动布局并实际关闭成功弹层，避免残留计时器、动画导致错误超时。未改页面运行时布局。
- 同步 Active OTA、产品规则、割草机覆盖、AI 快照及文档索引；前一轮历史记录保持冻结。

## 关键决策

保留安装阶段限制、98% 显示停留与 10 分钟停滞阈值。版本缓存仅当前尝试的内存证据，不持久化、不使用旧设备列表。DP116 不当作进度；花盆同号 DP 不参与割草机错误判定。

没有改设备固件、TuyaOS 差分配置、SDK 版本或 OTA 传输参数，也没有添加自动重试。App 修复不能代替平台包类型、设备下载和 Flash 擦写优化。

## 外部操作

开始前工作区干净，显式 `git pull --ff-only origin main` 成功；先 CodeGraph 定位并核对当前源码。使用本机 SDK 缓存核实接口并运行测试，不下载/更新依赖。提交后按当前同名分支再次 pull，再 push。

Gradle 生成的 `android/.kotlin/` 缓存仅加入本机 `.git/info/exclude`，保留原文件；不提交缓存、SDK 包、构建产物或索引。没有云平台改动、安装包发布或设备升级操作。

## 验证结果

- 最终 `flutter test --no-pub` 六个相关文件：`state_ota_test.dart`、`tuya/device_updates_test.dart`、`app/firmware_reminder_test.dart`、`features/devices/device_other_settings_page_test.dart`、`features/mower/mower_live_test.dart`、`features/mower/mower_lifecycle_test.dart`，**111 项全部通过**。
- `tools/tests/TuyaOtaListenerBridgeTest.kt` 与生产桥接一起用 Kotlin 编译，并运行在实际 SDK 7.5.1 device-api `classes.jar` 上，**23 项断言通过**。覆盖回调签名、超时、文本/空 bean/默认原因、旧失败回调、进度和阶段、代理 Object 方法。测试需要本机 Kotlin 编译器及 SDK 类路径，不增加生产依赖。
- Android `:app:compileDebugKotlin -Ptarget-platform=android-arm64 --offline` 最终 **BUILD SUCCESSFUL（17 秒）**；既有 Wi-Fi/Gradle 弃用告警保留。未生成 APK、未 Xcode 编译。
- 六个改动 Dart 文件 analyze 没有新增诊断；存在原有 `state.dart._filterToOurProduct` 未使用 warning、仓库注释尖括号 info，工具退出 1，不宣称 analyze 全绿。
- `lib test` 四项 Dart 静态自检（344 文件）通过；MainActivity 与新桥接 Kotlin 悬空引用检查通过。
- 扩大到植物后台集成测试时有两项不相关断言失败：期望仅含 DP116/161，实际还包含既有 DP162=false。本轮未修改植物确认下发业务。扩大回归中其余三项升级页面测试失败已通过夹具/交互步骤修正，包含在上述最终 111 项中。
- 最终 diff、文档相对链接、信息隔离与 CodeGraph 同步状态检查后提交。

## 未完成项与风险

没有真机时间线；尚未验证同设备实际 OTA 耗时、设备重启及联网时刻，也不能承诺缩短到 1 分钟。App 重启后升级状态恢复、iOS 阶段码、新版本发现延迟等原有缺口未在本轮扩展。

建议 Android 真机依次验证：普通完成；DP112 先于安装阶段到达后正确完成；非待机拒绝/包校验失败能关闭并重试；SDK 超时/文本失败可见原因。全程记录发起、首次进度、安装、设备重启/DP112、最终弹层时间，并与起始/目标版本、包类型和网络一致的涂鸦 App 对照。

## 回滚或恢复

需要回滚时在当前分支 revert 本次提交；不需要回滚设备或平台配置。各电脑拉取后自行同步 CodeGraph，本机缓存不作为交付依赖。
