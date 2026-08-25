# 设备 DP 实时上报、单位跟随与 iOS 桥接补齐

> 文档类型：Historical Change Record
> 日期：2026-08-20
> 环境：SSH（Linux，无 Flutter/Dart/Gradle/Xcode 工具链）
> 分支与起始版本：main / 665ce5c
> 范围：`lib/src/tuya`、`lib/src/state.dart`、devices 页面、`android/app`、`ios/`
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`、`AI_CONTEXT.md`

## 背景与目标

`docs/DP_GAP_REPORT.html` 按 PID `orhqsdjyigmh8bwa` 的 50 条功能点列出了 14 项缺口。产品方逐条给了口径，这次按该口径落地其中可以在 App 侧完成的部分。

产品口径（原话要点）：

- G01 DP 实时上报要接，原生侧设备监听 + 事件通道是涂鸦 SDK 现成的，调用即可。
- G03 图片下发（142/143/144）后续由 Java 后端提供图片地址，本次不做。
- G04 五条没有数据源的曲线，空着就行。
- G05 温标/时间格式下发后 App 自身也要跟随。
- G07 恢复出厂要下发 DP 141，固件收到后的行为待沟通；重新配网不需要下发 150，触发时重走配网流程即可。
- G09 分享按涂鸦 SDK 文档做，不设计固件 DP；OTA 直接对接涂鸦后台的固件升级接口。
- iOS 安全组件已提供（`assets/iOS_SDK (1)`），iOS 端一并接入。

## 变更内容

**设备 DP 实时上报（G01）**

- 新增事件通道 `com.common.yikaltd/tuya_events`（`TuyaConfig.eventChannelName`）。
- Android：`TuyaSdkBridge` 按设备 id 注册 `registerDevListener`（接口类型仍从方法签名反查，不硬编码），转发 `onDpUpdate` / `onStatusChanged` / `onNetworkStatusChanged` / `onRemoved` / `onDevInfoUpdate`；`getDevices` 成功后按返回集合增删监听，配网成功补一台，解绑/恢复出厂/退出/注销时释放，Activity 销毁时全量释放。
- iOS：`FlowerpotTuyaBridge` 实现 `ThingSmartDeviceDelegate` 与 `FlutterStreamHandler`，持有 `ThingSmartDevice` 实例（delegate 是弱引用），生命周期与 Android 对齐。
- Dart：`TuyaRepository.deviceUpdates` 新契约；`MethodChannelTuyaRepository` 保留每台设备最近一次原始 map，把增量合并后重新解码；`FlowerpotState` 订阅并替换设备、刷新本地设置副本、处理远端解绑。`MockTuyaRepository` 提供 `pushDeviceUpdate` 供测试驱动，默认不自己制造变化。

**报表空态（G04）**

温度、湿度、电量、DLI 与报表页在系列为空时显示空态卡片，不再用当前读数画一个点。新增 `MetricHistoryEmptyCard`。

**温标与时间格式跟随（G05）**

`DeviceControlSettings` 新增 `temperatureSymbol` / `temperatureFromCelsius` / `formatTemperature` / `formatCelsiusRange` / `formatClock` / `formatPeriod`。首页温度卡、温度状态页（含阈值与建议文案）、温度趋势图与报表页跟随 146；行为作息标签跟随 147。写回设备的值不变。

**震动的两个场景开关（G06）**

震动设置页在主卡下方新增 `VibrationSceneSwitchesCard`：触摸按键震动（123）与触摸植物震动（124）。读写链路早就通了，只差界面。两项不在 Figma 画板里，所以放在独立第二张卡，主卡 335×339 的画板尺寸不变。

**恢复出厂（G07）**

`FlowerpotState.removeDevice(resetFactory: true)` 先下发 DP 141，再调用 SDK 的 `resetFactory`；设备离线或拒绝不阻断解绑。重新配网维持现状，不下发 150。

**iOS 接入**

- 安全组件放到 `ios/TuyaSDK/`（已在 `.gitignore`）。
- `ios/Podfile`：`ThingSmartHomeKit` 由 `~> 7.5.0` 改为 `~> 7.8.0`，跟随随安全组件下发的官方 Podfile；移除未使用的 `ThingSmartBusinessExtensionKit`；`post_install` 仅在 SDK 接入时设置 `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`。
- 补齐 `scanWifi`、`prepareActivatorToken`（含 8 分钟令牌缓存与单次使用）、`checkFirmware`、`startFirmwareUpgrade`（`getFirmwareUpgradeInfo` → `upgradeFirmware`）。

**测试**

新增 `test/tuya/device_updates_test.dart`（事件解码、合并、上下线、解绑、未知设备、raw 历史刷新，以及 `FlowerpotState` 的应用）与 `test/tuya/device_control_settings_test.dart`（单位与时钟格式化）。

## 关键决策

1. **DP 增量必须合并进快照**：上报只带变化的功能点，直接解码会把没提到的字段清成默认值。合并落在 Repository，`FlowerpotState` 只换整台设备。
2. **本地设置副本以设备为准**：设备回执到达时用设备值刷新 `_settingsOverrides`，否则在设备上按实体键改的设置会被本地旧值盖掉。
3. **温度不做二次换算**：功能点表里 DP 112 的单位写的就是 `°C/°F`，设备切到华氏后上报值已是华氏。需要换算的只有 App 自己的摄氏阈值。
4. **iOS 没有 Wi-Fi 扫描**：`scanWifi` 只回当前 SSID，列表恒空——这是平台限制，不是未实现。
5. **iOS 分享保持错误码**：iOS Home SDK 只有按账号分享，没有生成分享链接的接口；改造需要产品先决定分享页是否收集接收方账号，所以没有猜一个 API 写上去。

## 外部操作

无。未执行 `pod install`、Gradle 构建或真机安装。

## 验证结果

**没有任何自动化验证。** 本机没有 Flutter/Dart 工具链（`flutter`、`dart` 均不存在），也没有 Android SDK 与 Xcode，因此：

- `dart format` / `dart analyze` / `flutter test` 未运行；新增测试未执行过。
- Android Kotlin 未编译；iOS Swift 未编译；`pod install` 未执行。
- 涂鸦 SDK 接口按官方文档核对：Android `IThingDevice.registerDevListener(IDevListener)`、`onDpUpdate(devId, dpStr)` 为 `{"101": true}` 形式的 JSON 字符串；iOS `ThingSmartDeviceDelegate` 的 `device:dpsUpdate:` / `deviceInfoUpdate:` / `deviceRemoved:`、`getFirmwareUpgradeInfo` / `upgradeFirmware`。

## 未完成项与风险

- 上述所有改动均需在有工具链的机器上跑 `dart format lib test`、`dart analyze lib test`、`flutter test`，再做 Android/iOS 构建。
- iOS `ThingSmartFirmwareUpgradeModel` 的 `upgradeStatus` / `type` / `version` 属性名依据文档，未经编译验证。
- `NEHotspotNetwork.fetchCurrent` 需要 Xcode Target 打开 Access WiFi Information 能力；当前工程没有 entitlements 文件，未开时只是读不到当前 SSID。
- 实时刷新覆盖设备卡片与状态页读数（`FlowerpotScope` 是 `InheritedNotifier`，`notifyListeners` 后依赖页面重建）。趋势图不同：`historyFor` 的 `Future` 只在进页面时取一次，新到的历史包要重新进入页面才会画出来。
- G03（142/143/144）、G08（修复系统文件）、G10–G14 未处理。
- 123/124 是否随 122 主开关联动由固件决定，当前界面不做联动置灰。
- **`assets/iOS_SDK (1)/` 下的 iOS 安全组件已经被提交进 Git**（`git ls-files` 可见）。它与 AppKey/AppSecret/Bundle ID 绑定，涂鸦文档明确要求不得外泄。建议 `git rm -r --cached` 后加入忽略规则，必要时在平台重建安全组件。本次没有擅自改动仓库跟踪状态。
