# 配网三页接入真实涂鸦 SDK 调用

> 文档类型：Historical Change Record
> 日期：2026-08-26
> 环境：SSH（无 Flutter/Dart 工具链）
> 分支与起始版本：main / 9cb9d0c
> 范围：`lib/src/features/devices/presentation/`（配网动线）、`lib/src/state.dart`、`lib/src/tuya/tuya_models.dart`、相关测试与文档
> 当前权威文档：[`../../TUYA_SDK_SETUP.md`](../../TUYA_SDK_SETUP.md) 6.3、[`../../PRD_IMPLEMENTATION.md`](../../PRD_IMPLEMENTATION.md)

## 背景与目标

SDK 联调页（`/devtools/tuya`）已经把配网需要的三个桥接方法跑通：`scanWifi` 确认频段与设备热点、`prepareActivatorToken` 在离开路由器前取云端令牌、`pairWifiDevice` 真正配网。但产品动线只有 Wi-Fi 页调用了 `pairWifiDevice`，搜索页是 2 秒定时器动画、选择页是写死的 `YSplanter-01/02/03`、Wi-Fi 页的「切换」弹窗是写死的示例网络名，AP 模式也没有取令牌这一步——按 `TUYA_SDK_SETUP.md` 的说明，AP 在真机上必然以一个与设备无关的网络错误失败。

本次把联调页验证过的这组调用接进真实业务页面，去掉配网动线里的全部模拟数据。不新增原生代码，只使用已有桥接方法。

## 变更内容

模型与状态：

- `WifiNetwork` 增加 `signalBars`（dBm → 1–4 格）与静态 `isDeviceHotspotName`；`WifiScan` 增加 `deviceHotspots`、`routerNetworks`（按 SSID 去重、按信号排序）、`currentIsDeviceHotspot`，并把 `currentIs24g` 在频率 ≤ 0 时改判为「未知」而不是 5G。
- `FlowerpotState` 记录 `prepareActivatorToken` 的取回时间，暴露 `activatorTokenReady`（7 分钟，短于原生缓存的 8 分钟）；配网成功与清理会话时置空。`probeWifi` 的定位从「仅诊断」改为配网动线与联调页共用。

页面：

- `DeviceSearchPage`：进页调 `probeWifi`。扫到设备热点才自动进入选择页；扫不到、`networks` 为空或扫描被拒绝时停在本页，按错误码给出原因（`wifi_disabled` / `location_disabled` / `permission_denied`），并提供「重新扫描」与「设备已在配网状态，继续」（直接进 Wi-Fi 页）。雷达扫描动效随扫描结束而停。
- `DeviceSelectionPage`：列表改为 `scan.deviceHotspots`，名称与信号格来自真实扫描结果；无结果时是带原因的空态。选中的热点名通过新增的 `PairingArguments.hotspotSsid` 传给 Wi-Fi 页。移除 600ms 假连接延时。
- `PairingPage`：进页自动带入手机当前连接的 2.4G 网络名（仅使用真实扫描值，排除 5G 与设备热点）；「切换」弹窗改为 `scan.routerNetworks`，带重新扫描与空态。AP 模式拆成两步——按钮先是「下一步：连接设备热点」（调 `prepareActivatorToken`），令牌就绪后显示热点引导卡片（可「检查连接」重扫确认当前 SSID）并变成「开始配网」。EZ 保持一步，手机在 5G 时给出红色提示。

测试：三页的 widget 测试改为覆盖真实链路，新增无热点、平台不枚举网络（iOS 形状）、扫描被拒绝、AP 两步顺序与 EZ 单步的用例。

文档：`TUYA_SDK_SETUP.md` 新增 6.3 并改写第 6 节「设备发现」段；`AI_CONTEXT.md` 第 5、9 节与 `PRD_IMPLEMENTATION.md` 配网行同步。

## 关键决策

- **不实现设备发现**。产品确认只有 2.4GHz Wi-Fi 配网、没有蓝牙，涂鸦 SDK 也没有扫描接口。唯一能真实观测到的设备是 AP 模式下它自己拉起的热点，三页因此建立在 `scanWifi` 上，而不是造一个假的发现流程。
- **「扫不到」永远不等于「没有设备」**。iOS 的 `scanWifi` 只返回当前 SSID、`networks` 恒为空，Android 扫描还受频率与定位开关限制。三页在列表为空时说的是「无法列出」，并且始终保留手动继续入口，配网本身不依赖扫描结果。
- **AP 两步是协议要求而非交互偏好**。取令牌是云端调用，连上设备热点后就没有外网。产品页与联调页采用同一顺序：填凭据 → 取令牌 → 连热点 → 开始配网。令牌仍只存在原生层，Dart 侧只存取回时间。
- 「连接」按钮不代表应用会去加入热点：两个平台都不允许静默加入指定 Wi-Fi，按钮只负责把热点名带到下一页并由引导卡片说明。

## 外部操作

无。未改动 Android/iOS 原生代码、密钥、安全组件与签名材料。

## 验证结果

- 本机（SSH 环境）没有 Flutter/Dart 工具链：`dart format`、`flutter analyze`、`flutter test` **均未运行**，仅做了人工复核与括号/字符串配对的静态检查。
- 未做真机或模拟器验证，未验证真实设备热点的 SSID 前缀。

## 未完成项与风险

- 必须在有工具链的电脑上补跑 `dart format lib test`、`flutter analyze lib test`、`flutter test`，尤其是三份重写过的 widget 测试。
- 热点识别前缀目前是 `SmartLife-`、`TY_`、`YSplanter-`，量产设备实际 SSID 需真机确认；不匹配时搜索页会退化成「未发现配网中的设备」，但手动继续路径仍可用。
- AP 真机链路（取令牌 → 切热点 → 配网）尚未在真实设备上跑通，联调页此前也只验证到调用可达。
- iOS 侧所有改动仍未经 Xcode 编译或真机验证。

## 回滚或恢复

三页与模型/状态改动集中在上列文件，`git checkout -- <paths>` 即可回到 9cb9d0c 的模拟实现；没有平台侧或数据迁移。
