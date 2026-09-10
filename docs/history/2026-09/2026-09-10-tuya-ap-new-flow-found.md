# 找到了：涂鸦「热点配网新流程」——SDK 自己会连热点，不用弹框

> 文档类型：Historical Change Record（**仅文档，无代码改动**）
> 日期：2026-09-10
> 环境：SSH
> 分支与起始版本：main / b371412
> 范围：`docs/reference/tuya-*.md`（新增官方文档存档）、本记录
> 权威来源：涂鸦官方文档「Wi-Fi 热点模式」Android 版
> （`developer.tuya.com/cn/docs/app-development/hotspot-mode?id=Kaixk6wxla1oy`，**匿名可读**）

## 结论先行：我此前「授权框无法避免」的结论是**错的**

官方 Android 热点配网文档里有一节 **「热点配网新流程」**，原文：

> 为了提高用户的配网体验，减少出错概率，提高 SDK 用户的配网成功率，因此引入一套新的配网流程机制。
> ……
> **在配网过程中，SDK 会在指定时间内自动去连接 AP 热点**，如果连上后，SDK 内部会去获取设备状态，
> 上报给业务方。只针对新设备固件有效。

**SDK 自己负责把手机连上设备热点。** 这解释了测试反馈的「同机同设备，智能生活不跳设置也不弹框」——
官方 App 走的就是这条新流程，而我们走的是文档里的「**原流程**」（原流程开头就写着
「但用户需要手动切换手机的 Wi-Fi 设置」）。

## 前置条件（**这是唯一的拦路项**）

> :::info
> 待配网设备的应用固件使用的 TuyaOS 版本号，**不低于 3.6.1**。
> :::

新流程**只对新设备固件有效**。设备固件的 TuyaOS 版本必须 ≥ 3.6.1，需要向设备开发确认。

## SDK 里确实有（已实测，不是听说）

从官方 Maven 下载 7.5.1 各模块解 AAR 核对，**全部存在**，`thingsmart` 已传递依赖，**无需升级 SDK**：

| 类 / 接口 | 所在模块 |
| --- | --- |
| `com.thingclips.smart.home.sdk.builder.ThingApActivatorBuilder` | `thingsmart-hardware-business-api` |
| `com.thingclips.smart.sdk.api.IThingOptimizedActivator` | `thingsmart-hardware-business-api` |
| `com.thingclips.smart.sdk.bean.ApActivatorBuilder` | `thingsmart-hardware-business-api` |
| `com.thingclips.smart.sdk.bean.ApQueryBuilder` | `thingsmart-hardware-business-api` |
| `com.thingclips.smart.sdk.api.IThingSmartActivatorListener` | `thingsmart-hardware-business-api` |
| `com.thingclips.smart.home.sdk.bean.ApHandlerBean` | `thingsmart-hardware-api` |

方法名 `newOptimizedActivator` / `queryDeviceConfigState` / `getDeviceSecurityConfigs` /
`resumeAPConfigWifi` 也都在 `thingsmart-hardware` 的实现里查到。

## 新流程的调用顺序（照文档）

```java
// 1. 取安全配置（可选，给设备下发对应安全等级）
ThingHomeSdk.getActivatorInstance().getDeviceSecurityConfigs(IThingDataCallback<String>);

// 2. 建配网器
ThingApActivatorBuilder b = new ThingApActivatorBuilder().setContext(activity);
IThingOptimizedActivator activator =
        ThingHomeSdk.getActivatorInstance().newOptimizedActivator(b);

// 3. 查「设备自己扫到的 Wi-Fi 列表」——SDK 在这一步自动连上设备热点
ApQueryBuilder q = new ApQueryBuilder.Builder().setContext(ctx).setTimeout(ms).build();
activator.queryDeviceConfigState(q, IThingResultCallback<List<WifiInfoBean>>);
//    WifiInfoBean: ssid / rssi / sec（0 OPEN、2~5 需 ≥8 位密码）

// 4. 开始配网
ApActivatorBuilder ab = new ApActivatorBuilder.Builder()
        .setSsid(ssid).setPwd(pwd).setTimeout(ms).setToken(token)
        .setSecurityConfig(securityConfig)
        .setListener(IThingSmartActivatorListener).build();
activator.startActivator(ab);

// 5. 密码错时恢复配网 / 结束
activator.resumeAPConfigWifi(new ApHandlerBean.Builder().setSsid(s).setPassword(p).build());
activator.stopActivator();
```

错误码 `207201`~`207222`（建连失败 / 设备状态异常 / 密码错 / 找不到路由器 / DHCP 失败 /
连云失败 / 超时……），比现在拿到的 `1006` 有用得多。

## 对我们的动线意味着什么

1. **不再需要 `WifiNetworkSpecifier`**：`joinDeviceHotspot` 那一整套（含系统授权框）可以删掉。
2. **不再需要在手机侧扫热点**：`queryDeviceConfigState` 直接返回**设备自己扫到的 Wi-Fi 列表**，
   用户从中挑路由器；搜索页那套「扫描配额 / 读缓存 / 白名单认热点」大部分可以退休。
3. **密码可以提前校验**：`sec` 值给出加密方式，2≦sec≦5 时密码必须 ≥8 位。
4. **失败原因具体化**：错误码能直接映射成人话。

## 未完成项与风险

- ⚠️ **设备固件 TuyaOS 版本待确认（≥ 3.6.1）**。低于此版本新流程无效，只能留在原流程。
- ⚠️ 文档只说「SDK 会自动去连接 AP 热点」，**没有说明它在 Android 10+ 上用什么机制**。是否
  仍会弹一次系统框，必须真机验证。测试反馈官方 App 不弹，倾向于不弹。
- iOS 侧的对应文档（`activator_wifiAp_ios`）流程图里仍是「引导用户连接到设备热点」，
  iOS 可能没有等价能力，需另行确认。
- 官方文档已存档到 `docs/reference/tuya-ap-mode-android.md` 等三份，避免线上改版后失联。
