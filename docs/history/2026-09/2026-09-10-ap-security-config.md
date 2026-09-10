# 2026-09-10（晚）固件确认 ≥3.6.1 后补齐新流程的 `getDeviceSecurityConfigs`

## 背景

设备团队确认固件 **TuyaOS > 3.6.1**，「热点配网新流程」的固件前提成立。

这条确认推翻了 `2026-09-10-drop-device-wifi-query-step.md` 的首要假设：
搜索页卡在「正在连接【SmaXXXX】」**不是**固件不支持。重新读文档后的解释是：

> `queryDeviceConfigState` 要先和设备建立通道才能「查询设备此时的状态」，
> 它**要求手机已经连在设备热点上**。文档里「在配网过程中，SDK 会在指定时间内自动去
> 连接 AP 热点」那句写在**配网过程**（`startActivator` / `resumeAPConfigWifi`）的说明里，
> 不是查询那一步的保证。

当时手机还连着路由器，这一步没有对象可问，于是一直等到超时。
**结论不变**：产品不需要设备视角的 Wi-Fi 列表，这一步该去掉（已去掉）。

但固件既然是新的，新流程**该带的东西就要带齐**——而官方流程的第一步我们完全没做。

## 诊断

官方新流程的步骤顺序（[Wi-Fi 热点模式](https://developer.tuya.com/cn/docs/app-development/hotspot-mode?id=Kaixk6wxla1oy)，
存档 `docs/reference/tuya-ap-mode-android.md`）：

1. **获取对应的安全配置列表** —— `getDeviceSecurityConfigs(IThingDataCallback<String>)`
2. `ThingApActivatorBuilder` → `newOptimizedActivator`
3. （可选）`queryDeviceConfigState` 查设备扫到的 Wi-Fi 列表
4. `ApActivatorBuilder` …… `.setSecurityConfig(securityConfig)` → `startActivator`

`setSecurityConfig` 的说明：「获取对应的安全配置列表（可选）**主要是给设备配网对应
安全等级信息**」。

核对代码：`getDeviceSecurityConfigs` **在整个项目里一次都没有被调用**，Dart 侧也从不
传 `securityConfig`，所以 `apStartWithToken` 里那个
`call.argument<String>("securityConfig")?.let { setSecurityConfig(it) }` 分支是**死代码**
——新流程一直在不带安全配置的情况下配网。文档标它可选，但它本来就是为新固件准备的。

## 改动

`android/app/src/main/kotlin/com/common/yikaltd/MainActivity.kt`

1. 新增字段 `deviceSecurityConfig`，缓存 `getDeviceSecurityConfigs` 的返回。
2. 新增 `prefetchDeviceSecurityConfig()`，挂在 `prepareActivatorToken()` 里一起预取。
   **和取令牌同一个理由**：这是云端请求，必须在手机**还连着路由器**时完成，配网一开始
   SDK 就会把手机连到没有外网的设备热点上。搜索页进页面时就会跑到（`prepareForPairing`）。
3. 不拦路：不挂在 `result` 上、不报错，老 SDK 上没有这个方法时由 `runCatching` 吞掉，
   只打一行日志。取不到照样能配网——文档标它可选。
4. `apStartWithToken`：`securityConfig` 取「Dart 显式传的值 ?: 预取到的那份」，
   `setSecurityConfig` 失败也只记日志。

`lib/src/features/devices/presentation/pairing_failure_page.dart`

- `207206` 的提示不再指向固件版本（已确认满足），改成「设备已退出配网状态，请重新上电
  后重试；也可能正被另一台手机占着配网」——那才是固件达标时这个码的实际含义。

## 验证

**未验证。** 本机没有 Flutter/Dart/Kotlin 工具链。静态自检：

- 括号配平通过。
- 反射调用可行性核对：`invokeWithCallback(activatorApi, "getDeviceSecurityConfigs", …)`
  不带业务参数，`optionalCallbackMethod` 的条件是
  `parameterTypes.size == args.size + 1 && last().isInterface`，对
  `getDeviceSecurityConfigs(IThingDataCallback)` 恰好成立；`callbackProxy` 认
  `onSuccess` / `onError`，与 `IThingDataCallback<String>` 的签名一致。
- ⚠️ 真机上若该方法不存在，会被 `runCatching` 静默吞掉并打日志，不影响配网。

## 遗留

- 安全配置到底影响哪些设备、不带会不会失败，文档没说，只能真机比对。
- 配网本身能否成功仍待真机：`startActivator` 是否真的会自己连上 AP 热点是这次改动的
  核心假设，依据是文档那一句。若不成立，回退到原流程（`pairViaHotspot` +
  `joinDeviceHotspot`，代价是系统入网授权框），代码都还在。
