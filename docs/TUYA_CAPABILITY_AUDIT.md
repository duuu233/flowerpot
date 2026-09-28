# 涂鸦能力核对（2026-09-10）

口径：**涂鸦支持的就用涂鸦的 SDK，不支持的再自己实现。**

核对方式是把 `MainActivity.kt` 桥接层真正向涂鸦要的每一项能力，逐条对照
developer.tuya.com 上的官方文档。下面每条都注明依据；**没有依据的写「未核实」，
不猜。** 本机没有 Flutter/Dart/Kotlin 工具链，本文只做静态核对，不含运行验证。

## 一、已经在用涂鸦官方 API（保持现状）

| 功能点 | 桥接方法 | 涂鸦入口 |
| --- | --- | --- |
| 登录 / 注册 / 验证码 / 改密 / 登出 / 注销 / 改昵称 / 当前用户 | `login` `loginWithUid` `register` `sendVerificationCode` `resetPassword` `logout` `cancelAccount` `updateNickname` `currentUser` | `ThingHomeSdk.getUserInstance()` |
| 家庭查询与切换 | `currentHomeId` `setHomeId` `setHomeTag` | `getHomeManagerInstance()` / `newHomeInstance(id)` |
| 设备列表 | `getDevices` | `newHomeInstance(id)` 家庭详情 |
| 重命名 / 移除 / 恢复出厂 | `renameDevice` `removeDevice` `resetFactory` | `newDeviceInstance(devId)` 同名方法 |
| DP 下发与监听 | `publishDps` / `onDpUpdate` `onDevInfoUpdate` `onRemoved` | `newDeviceInstance` + `registerDevListener` |
| 固件检查与升级 | `checkFirmware` `startFirmwareUpgrade` | `newOTAInstance(devId)` |
| 配网取令牌 | `prepareActivatorToken` | `getActivatorInstance().getActivatorToken(homeId, …)` |
| 设备消息（消息中心） | `deviceMessages` | `getMessageInstance().getMessageListByMsgSrcId(...)`，见下面「五」 |
| AP 热点配网（新流程） | `apQueryDeviceWifi` `apStartPairing` `apStopPairing` | `ThingApActivatorBuilder` → `newOptimizedActivator` → `queryDeviceConfigState` / `startActivator` |

这一档不需要改动。

## 二、涂鸦不支持，只能自己实现（保留自研）

### 1. AP 待配网设备的「发现」

**已核实涂鸦没有这个能力。**

- [设备配网业务实现](https://developer.tuya.com/cn/docs/app-development/extension-sdk-tutorial-deviceconfig?id=Kd8k3w5na6q73)：
  `ThingActivatorCoreKit.getScanDeviceManager()` 的扫描只覆盖**蓝牙**
  （MESH / SIG_MESH / SINGLE / BEACON）、**有线网关**、**Zigbee 子设备**、**Matter**。
  没有 Wi-Fi 热点（AP）设备的扫描方法，文中也完全没有「App 自行枚举附近 Wi-Fi」这回事。
- 三份热点文档（[Android 热点模式](https://developer.tuya.com/cn/docs/app-development/hotspot-mode?id=Kaixk6wxla1oy)、
  扩展 SDK 热点模式、iOS 热点模式）的步骤次序一致：
  **取 Token → 用户输入路由器 SSID/密码 → SDK 自己连设备热点 → 回调**。
  iOS 那份的时序图最直白：`用户输入路由器密码` 排在 `引导用户连接到设备热点` 之前。
- 涂鸦 UI 业务包列出的「自动发现配网」分别落在**蓝牙广播**、**有线设备局域网广播**、
  **Matter 自发现**、**Pegasus** 上，都不适用于纯 Wi-Fi AP-cfg 设备。

**结论**：`scanWifi`（`WifiManager.startScan` + `scanResults`）属于自研，无可替代。
代价是 **Android 9 起前台应用每 2 分钟只有 4 次 `startScan`** 的配额，绕不过去
（详见 `device_search_page.dart` 的排班注释）。

**推论**：智能生活 App 对 AP 设备根本不给雷达页，「打开就发现」说的是它的蓝牙/局域网
设备，与本产品无关。

### 2. Pegasus（天马座）不适用

Pegasus 是**设备端 / 路由端固件**的能力（TuyaOS 网关 SDK，用 802.11 Beacon /
Probe 帧下发凭据），需要路由器或家里已有的涂鸦设备支持。**App SDK 侧没有对应接口**，
本项目用不上。

### 3. 定制动画的图片同步（`uploadAnimation`）

[设备管理](https://developer.tuya.com/cn/docs/app-development/devicemanage?id=Kceugzegfxjk7)
里没有文件 / 图片 / 大数据传输接口。当前桩位报的
`product_protocol_required`（「图片同步需要设备 PID 对应的文件传输协议」）方向正确
——这属于**设备端 / TuyaOS 侧**要先定义的协议，不是 App SDK 能单方面接的。
**保持现状，等设备端给协议。**

## 三、涂鸦支持但我们没接对（建议改）

### 1. 设备分享挂错了 SDK ⭐

- 现状：`createShareLink` 反射 `ThingDeviceShareManager`（`extension.device.share` /
  `bizbundle.device.share`），两个包都没集成，于是永远返回
  `share_service_unavailable`。
- 官方：**核心 SDK 就有设备分享**，入口 `ThingHomeSdk.getDeviceShareInstance()`，
  方法包括 `addShareWithMemberId()` / `addShareWithHomeId()` /
  `queryUserShareList()` / `removeUserShare()` / `disableDevShare()`
  （见[共享设备](https://developer.tuya.com/cn/docs/app-development/android-saas-smart-protect-device-share?id=Kb5g8yvnikgt9)）。
- **区别在于形态**：核心 SDK 做的是「**按账号 / 家庭分享给某个人**」；
  「**生成一条分享链接**」是业务拓展 SDK 的设备分享组件才有的。
- **待产品确认**：如果需求是「把设备分享给另一个账号」，改用核心 SDK 立刻可用，
  不必集成业务拓展包；如果一定要**链接**，那才需要在涂鸦平台开通并集成业务拓展 SDK。
  在确认之前不动代码。

### 2. `joinDeviceHotspot` 已成回退路径 ⭐

`WifiNetworkSpecifier` + `requestNetwork` 这套自研连热点逻辑，是**系统入网授权框的
唯一来源**。切到热点配网新流程后由 SDK 自己连热点，这条路径只剩 legacy
`pairViaHotspot` 在用，而 UI 已不再调用它。
**建议**：明确标注为「老固件回退路径」或直接删除（连同 `EZ_MODE_NAMES` /
`DUAL_MODE_NAMES` / `"ez" ->` 那批死代码）。删除前需先确认固件 TuyaOS ≥ 3.6.1。

### 3. 设备统计（`getStatistics`）归属应在后端

App SDK 的设备管理文档里**没有**历史数据 / 趋势 / 统计接口；涂鸦的设备统计在
**云服务 API（服务端）**那一侧
（[设备管理云 API](https://developer.tuya.com/cn/docs/iot/open-api/api-list/api/device-management?id=K9g6rfntdz78a)）。
当前桩位的报错文案方向对，但实现路径应该是**后端调涂鸦云 API 再给 App**，
不是在 App 桥接层里补。**需与后端确认归属后再排期。**

### 4. 两个官方接口我们没用（可选增强）

设备管理文档里现成的：

- `requestWifiSignal()` —— 设备侧真实 Wi-Fi 信号强度。设备信息页现在没有这个数据。
- `getOfflineReminderSupportStatus()` —— 离线提醒是否可用。
- `getDp()` —— 单个 DP 主动查询，「针对不主动发送数据的设备」。

都属于「涂鸦有、我们没用」，不是 bug，按产品需要再取。

## 四、结构性待办

**搜索页不该是配网的门槛。** 按涂鸦的次序，AP 配网从来不需要先发现设备。可以改成：
进搜索页就并行发起 SDK 的 `connectDeviceForPairing()`（SDK 自己找热点，不经过我们的
`startScan` 配额），本地扫描只负责「展示扫到了哪台」。这样配额彻底离开关键路径。

未立刻实施的原因：设备未上电时 SDK 会耗掉整个超时，需要配套的重试与 `boundNetwork`
清理逻辑；本机无法编译验证，盲改风险过高。

⚠️ 另一个尚未量化的风险：**我们自己的扫描与 SDK 内部可能的扫描共用同一份 per-app
配额**。雷达页把 4 次烧光，理论上会饿死 SDK 的连热点动作。这也是上面这条该做的理由。

## 未核实项

- SDK 内部到底如何定位设备热点（是否也调 `startScan`）—— 文档只说「SDK 会在指定
  时间内自动去连接 AP 热点」，未展开。
- ~~设备固件 TuyaOS 是否 ≥ 3.6.1~~ —— **2026-09-10 已由设备团队确认 > 3.6.1**，新流程的固件前提成立。
- 本文所有接口签名均来自官方文档，**未在本项目内编译或真机验证**。

---

## 五、消息中心（设备消息推送）—— 2026-09-20 解包核对

来源不是文档，是**解包**：`com.thingclips.smart:thingsmart:7.5.1` 的父 POM → 模块
`thingsmart-personal-api` → `thingsmart-personal-api-7.5.1.aar` → `classes.jar`，
用 `tools/aar_class_dump.py` 打签名。**以下都是类文件里实际存在的东西，不是推测。**

### 5.1 入口与签名

`ThingHomeSdk.getMessageInstance()` → `com.thingclips.smart.sdk.api.IThingMessage`
（`ThingHomeSdk` 上确实有 `getMessageInstance`，同类还有 `getPushInstance`）：

```java
void getMessageList(IThingDataCallback<List<MessageBean>>);                    // 聚合
void getMessageList(int offset, int limit, IThingDataCallback<MessageListBean>);        // 聚合
void getMessageList(int offset, int limit, long startTime, long endTime, cb);           // 聚合
void getMessageListByMsgType(int offset, int limit, MessageType msgType, cb);
void getMessageListByMsgSrcId(int offset, int limit, MessageType msgType, String msgSrcId, cb);   // ← 用这个
void getMessageListByMsgSrcId(int, int, MessageType, String, boolean encryptImage, cb);
void getMessageListByMsgSrcId(int, int, MessageType, String, boolean, boolean splitImageKey, cb);
void getMessageListByMsgSrcId(int, int, int /*类型值*/, String, boolean, boolean, cb);
void deleteMessages(List<String> mIds, IBooleanCallback);
void deleteMessageWithType(int, List, List, IBooleanCallback);
void requestMessageNew(IThingDataCallback<MessageHasNew>);
void getMessageMaxTime(IThingDataCallback<Integer>);
void cancelAll();
// 另有一整套免打扰（DND）与隐私授权方法，本项目不涉及。
```

⚠️ **必须用 `getMessageListByMsgSrcId`，不要用 `getMessageList`**（产品口径 2026-09-20）：
标准接口是**聚合**结果，按它分页拿不到某台设备的全量消息 —— 2026-09-18 那版调的就是它，
打出来的内容明显不对。桥接现在没给设备 ID 会直接如实返回「要设备 ID」，**不会**偷偷退回聚合接口。

### 5.2 类型与等级字段：有

- `MessageType`（枚举，`getValue()` / `parseInt(int)`）只有三个常量，**对应消息中心的三档**
  （值是从 `<clinit>` 字节码里读出来的，不是猜的）：
  **`MSG_REPORT` = 1（告警，设备消息推送落在这一档）**、`MSG_FAMILY` = 2（家庭）、
  `MSG_NOTIFY` = 3（通知）。
- `MessageListBean`：`getDatas()` + `getTotalCount()`。
- `MessageBean` 上的字段（这就是「有没有类型字段」的答案）：
  `int msgType` + 四个常量（ConstantValue 读出来的值）`MSG_TYPE_SYSTEM` = 0 /
  `MSG_TYPE_NEW_DEVICE` = 1 / `MSG_TYPE_NEW_FRIEND` = 2 / **`MSG_TYPE_PRD_WARN` = 4**
  （产品预警，也就是告警那一类）、`String msgTypeContent`（类型文案）、`String msgCode`、
  `String msgContent`、`String msgSrcId`（= 设备 ID）、**`int alarmType`**、
  `String extendParams` / `JSONObject extendJson`、`String actionURL`、`dateTime` / `long time`、
  `icon`、`homeId` / `homeName`、`hasNotRead`、附件三件套（图 / 视频 / 音频）。
- **后台配的「推送等级」（轻微 / …）落在哪个字段还没确认**：候选是 `alarmType`、`msgCode`、
  `extendParams`。调试板照旧**原样打印全部字段**，真机拉一次就能定这一条。

### 5.3 拉不到东西时怎么查

桥接支持 `msgType: "ALL"`：**三档依次各取一次**，结果里 `perType` 写明每一档返回几条
（某一档失败记 `-1`，原因进诊断）。三档都是 0 时，再自动探两个**无参只读**接口
`getMessageMaxTime()`（消息中心最新一条的时间）和 `requestMessageNew()`（有没有新消息），
结果同样写进诊断 —— 用来区分「是这台设备没有消息」还是「整个消息中心就是空的（账号/家庭不对、
推送没真的发出去）」。**任何情况下都不会退回聚合的 `getMessageList`。**

### 5.3.1 真机第一次跑出来的东西（2026-09-20，设备 `6c707c…m7hm`）

- 实例方法清单与上面解包的签名**完全一致**，另外能看到同一套方法的混淆孪生
  （`bdpdqbp(int, int, int, String, IThingDataCallback)` 之类）—— 反射按名字找的是公开名，没受影响；
- 这次的调用是 `MSG_REPORT(value=1) → getMessageListByMsgSrcId(int, int, MessageType, String, cb)`，
  `msgSrcId=6c707c4ee7b5e5bea5m7hm offset=0 limit=50` → **返回 0 条**；
- `getMessageMaxTime() → 1789916821`，**单位是秒**，即 **2026-09-20 15:07:01 UTC** ——
  也就是说**账号的消息中心里确实有当天的消息**，只是不在「这台设备 + 告警档」这个交集里；
- `requestMessageNew()` 回的是 `com.thingclips.smart.home.sdk.bean.MessageHasNew`，
  解包后就三个 boolean：**`alarm` / `family` / `notification`**（再次印证三档就是告警/家庭/通知）。
  第一次跑时诊断里打的是 `toString()`（`@1e8c1f6`），已改成展开字段。

调试板的默认设备 ID 已改成后台那条推送挂着的 `6c2649322ed1365a00cadl`
（常量 `_defaultDeviceId`，置空即回到「已绑定的第一台」），输入框下面还列出当前账号已绑定的设备 ID。

**两种可能，下一次跑就能分清**：① 那条消息不在告警档；② 它的 `msgSrcId` 不是这台设备的 devId
（⚠️ 后台监控列表给的是 `6c2649322ed1365a00cadl`，这次查的是 `6c707c4ee7b5e5bea5m7hm`，**不是同一台**）。
所以诊断加了：每档的返回条数、`MessageHasNew` 的三个 boolean、以及空结果时**按类型取一页**
（`getMessageListByMsgType`，最多 20 条）把每条的 `msgSrcId` / `msgType` / `msgTypeContent` /
`msgCode` / `alarmType` / `dateTime` 打出来。

### 5.3.7 结案（2026-09-21）：那几条消息是**别人账号的设备**触发的

产品确认：监控列表里 09-18 ~ 09-19 那几条记录是 `6c2649322ed1365a00cadl` 触发的，截图来自别人。
这台设备不在 `YS40301` 名下（设备日志对它回 `PERMISSION_DENIED` 已经证明），而设备消息推送只投给**触发设备的
主人 / 被分享者**——所以 `YS40301` 的消息中心里本来就不该有。**App 的查法没有问题**，一路查到的「告警 0 条」是对的。

**到此为止已经确定的**：

| 事项 | 结论 |
| --- | --- |
| 设备消息怎么取 | 安卓 `getMessageListByMsgSrcId(offset, limit, MSG_REPORT, 设备ID, cb)`；iOS `fetchEncryptMessageDetailListWithListRequestModel`（未接） |
| 有没有类型字段 | 有：`msgType` / `msgTypeContent` / **`msgCode`**（细分靠它；`msgTypeContent` 随接口变，别靠） |
| 按时间筛 | 按设备 / 按类型都**不支持**；只有聚合 `getMessageList(…, long, long, cb)`，单位**秒** |
| 设备日志（DP 上报历史） | `getRequestInstance().queryDeviceOperateLogs(...)` **已跑通**（见 5.3.6） |
| 全类型事件日志（上线/下线/重置/升级…） | 只有云端 `/v1.0/devices/{id}/logs`，要后端代理 |

**还差一条**：「推送等级（轻微）」落在哪个字段 —— 要在**本账号的设备** `6c707c…m7hm` 上真的触发一次
同产品（`ehbx83xdh9jkmxvz`）的推送规则，告警档进来一条后看 `alarmType` / `msgCode` / `extendParams`。
调试板的默认设备 ID 已改回「当前账号已绑定的第一台」（不再写死 `6c26…cadl`）。

### 5.3.6 `probe-v7` 采集：设备日志跑通；消息中心在设备、产品都对上后**告警档仍全账号 0 条**

**设备日志（`queryDeviceOperateLogs`）跑通了**，第一种取值就被接受：

```text
("6c707c4ee7b5e5bea5m7hm", "103,105,106", 0, 20, "<开始毫秒>", "<结束毫秒>", "false")
→ {"dpc":[],"dps":[{"dpId":103,"timeStamp":1789393184,"timeStr":"2026-09-14 21:39:44","value":"0"}, …],
   "hasNext":false,"total":19}
```

- 参数顺序**确认**：设备 ID、dpIds（逗号分隔，**必填**）、offset、limit、开始/结束（**毫秒字符串**）、第七个传 `"false"`；
- 返回：`dps` 是设备**上报**，每条 `dpId` / `timeStamp`（**秒**）/ `timeStr`（本地时间文本）/ `value`（字符串）；
  `dpc` 看名字是**下发**记录（这次为空）；`hasNext` + `total` 用来翻页；
- ⚠️ 第七个参数传 `"false"` 时结果按时间**升序**，和 iOS `isASC` 的字面意思对不上，语义待再比一次 `"true"`。
  → 「日志」档里的 DP 上报历史，App 侧**能直接做**。

**消息中心**：目标设备换成账号里真绑着的 `6c707c…m7hm`（`pid=ehbx83xdh9jkmxvz`，与推送规则的产品一致）之后，
按设备取告警 0 条、按类型取（全账号）告警 0 条、按时间窗 09-18 ~ 09-19 只有两条登录提醒、
`requestMessageNew` 三个标志全 `false` ——**设备、产品、时间三个变量都排除了，告警档里就是没有**。

⚠️ 关于「用哪个设备 ID 应该都一样」（产品 2026-09-21）：**查询时**确实一样——`msgSrcId` 只是过滤条件，
而且「按类型取」本来就不带设备、看的是整个账号，结论与设备 ID 无关。**但投递不是**：设备消息推送只发给
**触发它的那台设备的主人 / 被分享者**。监控列表里那些记录如果是 `6c26…cadl`（另一个账号的设备）触发的，
它们进的是那个账号的消息中心，`YS40301` 永远看不见。所以要看的是**平台侧那条记录是哪台设备触发的**，
不是 App 这边用哪个 ID 去查。

本轮补了两个探针（空结果时才跑）：`getDeviceDNDSetting()`、`getAllDNDList()` —— 排除「设备告警免打扰开着」这一种可能。

### 5.3.5 `probe-v6` 采集：`6c26…cadl` **不属于当前账号**（PERMISSION_DENIED 就是证据）

| 观察 | 结论 |
| --- | --- |
| 聚合时间窗 09-18 ~ 09-19：**毫秒 0 条、秒 2 条**（两条登录提醒，时间对得上） | `getMessageList(int, int, long, long, cb)` 的时间**单位是秒** |
| 那一段的 2 条都是 `LOGIN_MSG_CENTER`，**本设备 0 条** | 那段时间 App 侧没有任何设备消息，更没有 `text2` |
| 同一条 `LOGIN_MSG_CENTER`：按类型取时 `msgTypeContent=通知`，按时间取时 `=系统提醒` | **`msgTypeContent` 随接口变**，分档别靠它，靠查询时的 `MessageType`；细分靠 `msgCode` |
| 设备日志：dpIds 非空的三种取值都是 **`PERMISSION_DENIED 没权限`**；dpIds 为空是 `10010 Illegal parameter error.` | ①参数格式已过校验：**dpIds 必填**，毫秒时间戳字符串被接受；②卡在权限——查的设备不在当前账号 |

**所以 `6c2649322ed1365a00cadl` 不是 `YS40301` 这个账号的设备**：账号里只绑着 `6c707c4ee7b5e5bea5m7hm`，
拿别的账号的设备去查日志，服务端直接回没权限。这也就解释了为什么按它的 `msgSrcId` 永远是 0 条——
**后台监控列表里那条 `text2` 挂在另一台设备 / 另一个账号上**，用当前账号登录的 App 看不见。

两条出路：① 用绑着 `6c26…cadl` 的那个账号登录 App 再查；② 在 `6c707c…m7hm`（当前账号那台）上真的触发一条告警推送。
调试板因此加了「填账号里已绑定的那台」按钮，设备日志遇到 `PERMISSION_DENIED` 时自动换成已绑定那台重试一次。

### 5.3.4 时间筛选与产品 ID（2026-09-21 追问）

**`getMessageListByMsgSrcId` 不支持时间筛选。** 解包核对的四个重载里，除了
`offset` / `limit` / `MessageType` / `msgSrcId`，多出来的只有两个图片相关的 boolean
（`encryptImage`、`splitImageKey`）——**没有任何时间参数**；`getMessageListByMsgType` 也没有。
整个 `IThingMessage` 上带时间的只有一条，而且是**聚合**口径：

```java
void getMessageList(int offset, int limit, long startTime, long endTime,
                    IThingDataCallback<MessageListBean>)
```

所以要「只看某个时间段」只有两条路：① 用这条聚合接口（本轮已接成桥接 `messagesByTime`，
**只当诊断**；时间单位官方没写，**真机实测是秒**，原生先按秒调、空了再按毫秒兜底，被接受的写进 `unit`）；
② 按设备那条靠 `offset` 往后翻页，直到 `dateTime` 落进那一段（消息是倒序给的）。

⚠️ 但**时间不是这次查不到的原因**：告警档 `totalCount=0`、按类型取（不带时间、不带设备）全账号也是
0 条、`requestMessageNew` 的 `alarm` 还是 `false` —— 空集合不分时间段。

**产品 ID 这条更可疑。** 产品确认推送规则配在 `ehbx83xdh9jkmxvz` 上；而消息里出现的设备
`6c707c4ee7b5e5bea5m7hm` 属于哪个产品，App 这边是知道的（设备列表带 `productId`）。
调试板因此把已绑定设备打成 `设备ID(pid=产品ID)`，并直接判一行
「目标产品 `ehbx83xdh9jkmxvz`：有绑着这个产品的设备 / ⚠️ 账号里没有这个产品的设备——推送规则配在它上面就不会触发」。
**规则配在 A 产品、账号里绑的是 B 产品的设备**，就是"后台能看到消息、App 一条也收不到"的典型成因。

### 5.3.3 2026-09-21 全量采集：**告警档整个账号是空的**

`probe-v4`、`uid YS40301` / 家庭 `251447714` / 已绑定 1 台，目标设备填的是后台监控列表给的
`6c2649322ed1365a00cadl`，类型 `ALL`：

| 观察 | 值 |
| --- | --- |
| 按设备取 | `MSG_REPORT ← 0 条（totalCount=0）` |
| 按设备取（家庭 / 通知） | **`101001 JSON PARSE EXCEPTION`** |
| `requestMessageNew()` | `alarm=false, family=false, notification=true` |
| 按类型取一页（全账号） | **告警 0 条**、家庭 20 条、通知 20 条 |
| `getMessageMaxTime()` | `1789955044`（秒）＝ 通知档最新那条 `2026-9-21 09:44`，两者对得上 |

**结论 1：不是查法问题，是消息中心里压根没有告警消息。** 按设备取 0 条、按类型取（不带设备）
整个账号也是 0 条、`requestMessageNew` 的 `alarm` 也是 `false` —— 三个口径一致。
所以后台那条 `text2`（推送编号 `GYjoVtpHsqHjpZbc`、等级「轻微」）**没有落进消息中心的告警档**。
要往下查得回到平台侧：那条推送有没有真的触发过、推送渠道有没有包含「消息中心 / App 内消息」。

**结论 2：`getMessageListByMsgSrcId` 只对告警档有意义。** 同一套参数换成 `MSG_FAMILY` / `MSG_NOTIFY`
会被 SDK 报 `101001 JSON PARSE EXCEPTION`（通知档的消息本身就没有 `msgSrcId`）。
家庭 / 通知要用 `getMessageListByMsgType`。

**结论 3：类型字段完全够用**（产品最初的问题到这里可以结案）。真机上两档的实际取值：

| 档 | `msgType` | `msgTypeContent` | `msgCode` | `msgSrcId` | `alarmType` |
| --- | --- | --- | --- | --- | --- |
| 家庭 | `-1` | 添加设备 / 移除设备 | `ADD_DEVICE_FOR_LOCATION_MSG_V2` / `DEVICE_USER_DELETE_MSG_V2` | 设备 ID（`6c707c…m7hm`） | `0` |
| 通知 | `0` | 通知 | `LOGIN_MSG_CENTER` | **没有** | `0` |

→ 分三档用 `MessageType`（查询时就分开了）或 `msgTypeContent`；**细分文案用 `msgCode`**，
它比 `msgType` 有用得多（`msgType` 在家庭档甚至是 `-1`）。「推送等级」在这两档里看不到
（`alarmType` 都是 0），**只能等真的有一条告警消息进来再看**。

**顺带**：这个账号里实际绑着的是 `6c707c4ee7b5e5bea5m7hm`（家庭消息写着「YS40301添加的花盆test」），
后台监控列表给的 `6c2649322ed1365a00cadl` 在这个账号的消息里从没出现过 ——
但这**不是主因**，因为告警档全账号都是 0 条，换设备 ID 也一样。

**设备日志那一条**：`queryDeviceOperateLogs` 在实例方法清单里确实存在
（`com.thingclips.sdk.device.qbqbbdd`），但七个参数全给（时间与 dpIds 留空）时服务端回
`Illegal parameter error.` —— 是**取值**不合口径，不是签名不对。桥接已改成按四种取值逐个试
（dpIds + 毫秒时间窗 × sort=false/true、时间留空、dpIds 留空），并把每次的报错记进诊断。

### 5.3.2 ⚠️ 更正：日志接口是有的，只是不在设备实例上（2026-09-20 当天更正）

本轮先前在历史记录里写过一句「Home SDK 里没有设备日志接口」，**那是错的**——当时只翻了 `IThingDevice`。
重新解包 `thingsmart-device-api` 7.5.1 之后：

| 要什么 | 入口 | 签名（解包核对） |
| --- | --- | --- |
| **设备操作日志（DP 上报历史）** | `ThingHomeSdk.getRequestInstance()` → `IThingSmartRequest` | `void queryDeviceOperateLogs(String, String, int, int, String, String, String, IThingDataCallback)`；实现里回调泛型是 `String`（**原样一段 JSON**） |
| DP 统计（按天/周/月聚合，不是日志） | `newDeviceInstance(devId)` → `IThingDevice` | `void getDataPointStat(DataPointTypeEnum, long, int, String, IGetDataPointStatCallback)` |
| iOS 对应 | `ThingSmartDevice` | `queryDeviceOperateLogWithDpIds:offset:limit:startTime:endTime:isASC:success:failure:` |

⚠️ **七个参数的顺序官方没给**。iOS 那条是 `dpIds / offset / limit / startTime / endTime / isASC`，
安卓多一个设备 ID 在最前，所以桥接 `deviceOperateLogs` 按「设备 ID、dpIds、offset、limit、开始、结束、排序」
传，并把返回的 JSON **原样**交给页面——顺序对不对看真机那一趟的报文。

**但它只覆盖「DP 上报」这一类。** 产品问的「日志类型区别」在**云端 API** 上：
`GET /v1.0/devices/{device_id}/logs`，`type` 可多选（逗号分隔）——
**1 上线 / 2 下线 / 3 设备激活 / 4 设备重置 / 5 指令下发 / 6 固件升级 / 7 数据点上报 /
8 设备信号量 / 9 设备重启 / 10 定时信息**
（涂鸦文档口径：<https://developer.tuya.com/en/docs/cloud/0a30fc557f?id=Ka7kjybdo0jse>；
云端接口要 AK/SK 签名，**App 侧拿不到，得后端代理**）。

所以三档想做全：
- 「日志」这一档：App 侧只能拿 DP 上报历史（`queryDeviceOperateLogs`）；要上线/下线/重置/升级这些，
  必须后端把云端 `/logs` 代理出来；
- 「提醒 / 告警」：走消息中心（本节前面那套），但要先解决「消息按 `msgSrcId` 查不到」。

### 5.4 iOS 不是同名方法

iOS 侧要调的是 `ThingSmartMessage` 的
**`fetchEncryptMessageDetailListWithListRequestModel:success:failure:`**（请求模型里带
`msgSrcId` / 类型 / 分页），**不是**安卓的 `getMessageListByMsgSrcId`（产品 2026-09-20 提供，
是之前踩过的坑）。iOS 桥接本轮仍未接，Dart 侧的 `MissingPluginException` 分支已经把这行方法名带回去。

### 5.5 实时推送监听（2026-09-23 解包核对）

消息中心是事后去拉；推送到达的那一刻要收，用 `ThingHomeSdk.getPushInstance()` → `IThingPush`
（实现类 `personallib.qqpddqd` 同时是设备 MQTT 协议监听，构造时注册了三个协议 bean）：

| 方法 | MQTT 协议 | 回调里的对象 | 字段 |
| --- | --- | --- | --- |
| `registerPushAlarmListener(IThingGetBeanCallback)` | 802 | `MQ_802_PushAlarmBean` | `String type`、`String msg` |
| `registerMQPushListener(IThingGetBeanCallback)` | 52 | `MQCompensationBean`（由 `MQ_52_DataPushBean` 转来） | `String type`、`String link`、`long timeStamp` |
| `registerThingPushListener(String topic, IThingDataCallback)` | 自订阅 topic | — | 本轮未接 |

- `IThingGetBeanCallback` 只有一个 `onResult(Object)`；两个 register 只往 SDK 内部的列表里加，**没有注销方法**，
  所以桥接 `startPushListen` 整个进程只注册一次。
- 桥接把收到的对象原样 dump（全部无参 getter）经事件通道推上来（`type=pushMessage`，`source=alarm802|mq52`），
  调试板「开始接收推送（实时）」逐条打印，并按 `来源/type` 计数；`msg` 是 JSON 时再展开一层。
- 同一对象上还有 `getPushStatusByType(PushType)` / `getNonRepeatRemindByType(PushType)`（`PushType`：
  `PUSH_ALARM` / `PUSH_ALARM_SYSTEM` / `PUSH_ALARM_PHONE` / `PUSH_ALARM_SMS` / `PUSH_FAMILY` / `PUSH_NOTIFY` / `PUSH_MARKETING`），
  本轮没接；只收到第一条、后面不来时再看「不重复提醒」时长。
- `registerDevice(token, provider, cb)` 是系统推送（FCM 等）通道注册，本 App 没接，**App 在后台 / 被杀时收不到**这两路 MQTT 推送；
  测试时 App 要开在前台。

### 5.6 官方文档核对：消息通知页「日志 / 提醒 / 告警」能不能靠涂鸦接口分开（2026-09-28）

页面三档（割草机「消息通知」，稿子 `割草机-消息通知.png`）对照涂鸦开发者文档，逐档结论：

| 页面分类 | 涂鸦有没有现成的 | 依据 | 结论 |
| --- | --- | --- | --- |
| 日志 | 有：`getRequestInstance().queryDeviceOperateLogs(...)`（DP 上报 / 下发历史，5.3.6 已真机跑通） | 解包 + 真机 | **能做**。但它只给 DP 原值，稿子上「割草任务已完成 / 计划已调整」要 App 按 DP 翻成文案；「设备重新上线」这类上下线事件只有云端 `/v1.0/devices/{id}/logs`，要后端代理 |
| 告警 | 有：消息中心告警档 `MSG_REPORT`，按设备 `getMessageListByMsgSrcId`（iOS `fetchEncryptMessageDetailListWithListRequestModel`） | 官方文档：「Only the alerts of MSG_REPORT type are supported」「Per-device queries are supported only for alert-type messages」 | **能做**（已接） |
| 提醒 | **没有单独的一档** | 见下 | 涂鸦的分类本身分不出来，只能靠推送规则的「推送等级」或规则自身来分，见下 |

**为什么「提醒」没有现成的一档**：
- App SDK 的消息中心只有三类：告警（1）/ 家庭（2）/ 通知（3）；实时推送的 `PushType` 是告警 / 家庭 / 通知 / 营销。
  **平台上配的设备消息推送（不管什么等级）都进「告警」这一档**，「通知」档是账号类系统消息（登录提醒等），不是设备的。
- 涂鸦平台「推送设备消息」规则**有等级**：「共有 **通知**、**轻微**、**严重** 三种不同等级。不同设备消息推送等级在 App
  设备列表页……会展示不同的醒目颜色」（这是涂鸦公版 App 的表现）。**SDK 文档的 `MessageBean` 里没有写等级字段**
  （只列了 `dateTime` / `icon` / `msgTypeContent` / `msgContent` / `msgType` / `msgSrcId` / `id` / `hasNotRead`）。
- 解包出来的 `MessageBean` 还有文档没写的 `alarmType`、`msgCode`、`extendParams`（5.2）——**等级如果随消息下发，只可能在这三个里**。
- 查过的另两条路都不适用：「告警列表 / 告警类别（`msgCodes` + `getMessageSchemes`）」只给摄像头（IPC，`ThingSmartCameraMessage`）；
  平台「消息类型」（`bizCode`：`deviceOnline` / `deviceEventMessage` …）是云端推给后端的消息服务，不是 App 消息中心。

**所以能不能实现**：
1. 日志、告警：能，按上表。
2. 提醒 vs 告警：**取决于一次真机验证**——在本账号的设备上各触发一条「通知」等级和一条「轻微 / 严重」等级的推送，
   拉告警档看这两条的 `alarmType` / `msgCode` / `extendParams` 有没有区别：
   - 有区别（例如等级落在 `alarmType`）→ App 按等级分：通知 → 「提醒」，轻微 / 严重 → 「告警」，接口不变；
   - 没区别 → 退一步按**规则**分：两类规则的 `msgCode`（若每条规则不同）或规则内容在 App 里建一张对照表；
     这条依赖平台配置不改名，不如按等级稳。
3. 前提：推送规则要配在**本账号能看到的设备**上（5.3.7：推送只投给触发设备的主人 / 被分享者）。

**已按这个方案改页面（同日）**：割草机「消息通知」的提醒 / 告警都来自告警档（`FlowerpotState.loadAllDeviceMessages`
按设备翻页取全，每页 50、最多 500），逐条按 `_gradeOf` 分档——只认名字带 level / grade / severity / priority / 等级 的字段
（消息本身或 `extendParams` JSON 里）的**明文值**，认不出的归告警；每次加载往联调日志写「共几条 → 提醒几条、告警几条（几条没认出）」
和前 5 条的 `alarmType` / `msgCode` / `extendParams` 原值。**真机下一步**：分别触发一条「通知」和「轻微 / 严重」等级的推送，
看这几行日志——两条这三个字段有区别，就把区别补进 `_gradeOf`；没区别就按规则（`msgCode` / 标题）建对照表。

来源：[推送设备消息](https://developer.tuya.com/cn/docs/iot/alarm?id=K93ixsmlff32o)、
[Android 消息相关功能](https://developer.tuya.com/en/docs/app-development/android-message-about?id=Kaj16vvx1n8jw)、
[Android 设置消息推送](https://developer.tuya.com/cn/docs/app-development/android-message-push?id=Kaj16d3iwgq4r)、
[iOS 消息相关功能](https://developer.tuya.com/en/docs/app-development/iOS-message-function?id=Kaj0t5zaofjfd)、
[告警列表（IPC）](https://developer.tuya.com/en/docs/app-development/messagelist?id=Kdmgaswbhh83p)、
[平台消息类型](https://developer.tuya.com/en/docs/iot/message-type?id=Kavqerli65a1u)。

### 5.7 设备告警监听自带 `warnLevel`（2026-09-28 解包）与消息通知三栏新口径

产品口径改为：**日志 = 通知、提醒 = 轻微、告警 = 严重**（三栏都来自消息中心告警档）。为找等级，把本机缓存的 7.5.1 包
（`sdk-msg` / `sdk-push` 两组 aar）里消息 / 推送相关类的字符串常量全搜了一遍，只有一处带「等级」：

```java
// thingsmart-device-api
interface IThingDevice { void registerWarnMessageListener(IWarningMsgListener); }
interface IWarningMsgListener { void onWarnMessageArrived(WarnMessageBean); }
class WarnMessageBean { String uid; String devId; int warnLevel; long latestWarnTime; String productId; long lastProdWarnId; }
class MQ_56_WarnMessageBean { WarnMessageBean warnMessageBean; }   // MQTT 56 号协议
```

- **消息中心的 `MessageBean` 上没有等级字段**（只有 `alarmType` / `msgCode` / `extendParams` 三个候选）；
  `warnLevel` 只在这条**实时**的设备告警里有——只有 App 开着时收得到，历史消息拿不到。
- 已接：原生 `watchDevice` 给每台已绑定设备顺手挂 `registerWarnMessageListener`（`MainActivity.registerWarnListener`），
  收到的走现成的 `pushMessage` 事件（`source=warn56`，**不放顶层 deviceId**，免得被当成设备状态更新）。
- `warnLevel` 的数字是什么意思、`alarmType` 是不是等级，**文档都没写**（查到的「alarmType 1 自定义 / 2 设备告警」
  是商业照明云 API 的字段，不是这里）。页面按推测编码 1 = 通知、2 = 轻微、3 = 严重（`_levelCodes`，一处可改），
  判定顺序：明文等级 → 等级字段里的数字 → 页面开着时收到的 warn56（同设备 ±60 秒）→ `alarmType` → 都不行归告警。
- **真机要做的一次**：在本账号的割草机上，分别配 / 触发一条「通知」「轻微」「严重」等级的推送（`docs/涂鸦消息推送对接方案.md` 里的规则），
  App 开在消息通知页，看联调日志里的「设备告警 warn56：warnLevel=…」和「等级字段：alarmType=… → 哪栏」三行对不对。
  对不上就改 `_levelCodes`；如果 `alarmType` 三个等级都一样，说明它不是等级，把第 4 步去掉，历史消息就只能靠 warn56 当场记下。
- 2026-09-28 花盆也加了消息通知页，列表和割草机共用 `DeviceMessagesView`（`features/messages/device_messages_view.dart`），
  `_levelCodes` 等判定只有这一份，定下来两款一起生效。花盆要有消息，得在涂鸦平台上给**花盆产品**另配推送规则。

另：按 V2.5 核对 DP 表，代码与文档一致，**只缺 DP113 `shutdown_report`（V2.5 新增关机上报）**，当时未接（收到 true 应显示「已关机」、
随后离线不报异常，见协议 §4.7 / §9.9）。**同日已接上**：纯 DP 上报，不涉及 SDK 新能力——设备快照 / 实时上报里的 DP113
经 `FlowerpotState.isMowerShutdown` 判定，口径见 `PRODUCT_RULES.md` 割草机「DP113 关机上报」一条。
