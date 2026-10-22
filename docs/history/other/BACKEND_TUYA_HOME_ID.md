# 涂鸦家庭 ID：当前行为与后端接口需求

> 文档类型：Active（接口契约需求）
> 最后核验：2026-10-08
> 事实来源：`lib/src/state.dart`、Android/iOS 原生桥接、`lib/src/core/backend/app_backend_repository.dart`、涂鸦官方 SDK 文档。后端字段支持为客户端源码核对，未在本轮请求生产接口。

## 为什么需要它

涂鸦 Home SDK 里，**设备属于家庭，家庭属于账号**：

- 设备列表按家庭查：`newHomeInstance(homeId).getHomeDetail().getDeviceList()`；
- 配网令牌按家庭取：`getActivatorToken(homeId)`——**配网时用哪个 homeId，设备就落进哪个家庭**。

家庭 id 由**涂鸦云端分配**（Long），App 只能查（`queryHomeList` → `getHomeId`）或建（`createHome` 的回调里返回云端分配的 id），不能自己生成，也**不能拿 `userNo` / `userId` 顶替**（哪怕转成 long）：它们是 APP 后端自己的标识，涂鸦的家庭表里没有这条记录，`getHomeDetail` / `getActivatorToken` 会直接失败；更坏的情况是这个数字落在有效区间、命中**别人**的家庭。`createHome` 也不接受指定 id。

一个账号名下可能有多个家庭（用户自己在涂鸦「智能生活」App 里建过，或早期版本在家庭列表瞬时为空时自动建过）。此时"这次登录用哪个家庭"如果靠列表顺序决定，就会出现**重新登录后读不到已绑定设备**。所以需要一处权威存储，按账号固定住这个 id——后端是唯一能跨设备、跨重装保留它的地方。

## 当前落地方案（2026-09-09 与后端确认后）

后端不再新增 `tuYaHomeId` 字段，改为**在登录响应里多返回一个 `userId`**，作为「这个家庭属于哪个账号」的依据。注意 `userId` **不是家庭 id**，也当不了家庭 id（见下节）；它的用法是：

- App 用它拼出家庭名标记 `YS-<userId>`：**建家时用这个名字**，之后从涂鸦家庭列表认领时**优先认这个名字**；
- 本地缓存（`SharedPreferences`）也按它作键存那次真正用上的涂鸦家庭 id。

后端没下发 `userId` 时，App 退回用涂鸦 uid（即 `userNo`）作为同一用途的键，行为不变。

效果：标记跟**账号**走、不跟手机走。同一个账号键能稳定认领同名家庭；若历史上已有多个家庭、家庭名被改过或账号键发生变化，仍需核对设备实际所在的家庭，不能仅凭标记认定归属正确。

`tuYaHomeId` 字段与回写接口（下节）仍然是更快、更准的方案（省掉按名字认领这一步），后端愿意做的话 App 侧代码已经就绪。

## （可选）需要后端做的两件事

### 1. 登录 / 注册响应增加 `tuYaHomeId`

模型：`UserInfoDetailApiOut`（`/Client/User/loginByCode`、`loginByPassword`、注册等登录类接口的 `retData`）。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `tuYaHomeId` | string（long 也可，App 一律按字符串处理） | 该账号绑定的涂鸦家庭 id。**还没有值时返回 null 或不返回这个 key**，不要给 `0` 或空串以外的占位值。 |

命名沿用现有的 `tuYaPwd` / `tuYaRemark` 写法。App 侧已兼容 `tuYaHomeId` / `tuyaHomeId` / `homeId` 三种拼法，取到即用。

### 2. 提供一个保存接口，让 App 回写

家庭 id 只有 App 在调涂鸦 SDK 时才拿得到，**后端自己变不出来**：第一次登录时后端字段必然是空的，要等 App 解析（或创建）出家庭之后写回去。

建议：

```
POST /Client/User/setTuyaHomeId
入参：{ "userToken": "...", "tuYaHomeId": "123456789" }
出参：标准 retCode / retMsg 结构即可
语义：按当前登录账号覆盖保存；同一个账号重复提交同一个值应当幂等。
```

接口名和入参形状由后端定，定下来告诉客户端即可接上（客户端改动约十几行）。

## App 侧当前行为（已实现）

优先级：**后端 `tuYaHomeId` > 本地缓存 > 涂鸦家庭列表现挑**。

1. 账号键优先用后端 `userId`，取不到退回涂鸦 uid（`userNo`）；家庭名标记为 `YS-<账号键>`，本地家庭缓存键为 `tuyaHome:<账号键>`。这些账号标识没有被用作涂鸦家庭 ID。
2. 登录 / 注册拿到有效 `tuYaHomeId` → `setHomeId` 钉给原生，并写入本地缓存；后端没给则使用本地缓存；两者都没有才解析涂鸦家庭列表。
3. **Android 现挑规则**：名字等于账号标记的优先，其次按家庭列表对象中的设备数从多到少，最后按 `homeId` 从小到大。此处没有逐个读取家庭详情，列表对象的设备计数不等于本轮已经核对过全部家庭设备。
4. **iOS 现挑规则**：名字等于账号标记的优先，其次按 `homeId` 从小到大，没有 Android 的设备数排序。两类产品在各自平台内共用家庭逻辑；双模 BLE 激活桥接目前只在 Android 实现。
5. **自愈触发条件**：本次设备列表为 0 台，且 `_pinnedHome != null`，才清除固定家庭并重选一次。只少了一台、列表还留着割草机等设备时不会触发。重选沿用相同标记规则，不会遍历所有家庭核对某个 `deviceId`。
6. 配网准备阶段先 `currentHomeId()`，再取令牌。Android 在家庭列表为空且进程仍绑着设备热点时回 `home_offline`；正常网络下空列表重查一次，仍空才建家。iOS 空列表重查后建家，不能将 Android 的热点门禁表述为双端都已实现。原生返回明确查询错误时准备失败；返回 `0` 时仅记录诊断，不再用 `home_unresolved` 拦路。

## 花盆与割草机的注册共用范围

Android 当前产品入口屏蔽 AP（`PairingGate.apEnabled = false`），两类设备均走 BLE 双模配网：搜索页 `prepareForPairing` → `pairViaBle` → 原生 `pairBleDevice` → `startMultiModeActivatorWithHome`。原生将同一个会话家庭传给令牌接口和配网配置的 `gid`，没有按花盆 / 割草机分别选择家庭的业务分支；扫描得到的设备对象由 SDK 按其真实产品与能力处理。

正常成功路径只认 SDK `onSuccess(DeviceBean)`，随后 `_pairInternal` 将设备加入本地列表、作废令牌；没有立即回查家庭设备列表核对本次设备 ID，也没有独立校验 `wifiEnable`。配网与列表读取均不依赖 `addUserProduct` / `getUserProductList`，本轮不存在花盆漏调后端注册、割草机另调后端注册的差异。

SDK 报错时 `_recoverPairedDevice` 回查当前家庭三次，按“本地旧列表之外的新设备”恢复成功；没有按本次扫描 UUID 或产品 ID 匹配。这是两类设备共用的恢复边界。

## 排除家庭问题的证据边界

- **只能排除产品分支差异**：同一 App 会话里，两类设备的家庭选择、缓存和令牌流程一致。这不足以证明历史上每次注册实际使用了相同家庭。
- **同一账号多个家庭**：列表只读当前家庭。若花盆落在另一个家庭而当前家庭还有割草机，现有空列表自愈不会发现。应按丢失设备 ID 核对账号名下所有家庭，而不是只看当前家庭设备总数。
- **令牌与家庭切换**：原生令牌缓存只记录令牌和时间；`setHomeId` 没有同步作废令牌。若取令牌后家庭发生切换，当前代码没有校验令牌对应家庭与配网 `gid` 一致。本轮只确认该防护缺口，未复现这种切换，也未认定它是偶现原因。
- **本地激活与云端激活**：涂鸦官方说明部分双模设备支持蓝牙兜底，Wi-Fi 激活失败时可处于蓝牙本地连接状态，`DeviceBean.meta["wifiEnable"]` 可用于区分云端链路激活。当前成功路径未做该检查；需真机确认具体花盆是否支持以及成功回调实际字段，不能直接把蓝牙兜底认定为丢失原因。依据：[涂鸦蓝牙单点 / 双模设备文档](https://developer.tuya.com/cn/docs/app-development/android-bluetooth-ble?id=Karv7r2ju4c21)。
- **设备移除与离线**：SDK `onRemoved` 转为 `removed` 事件，状态层移除该设备；`onStatusChanged` 只更新在线状态，离线不会按此路径删除设备。花盆“恢复出厂 / 重新配网”会发 DP141 并调用 SDK `resetFactory`，割草机当前只有普通删除入口。源码未发现配网成功后自动调用这类解绑入口。依据：[涂鸦设备管理文档](https://developer.tuya.com/en/docs/app-development/devicemanage?id=Ka6ki8r2rfiuu)。

彻底排除家庭问题需要：丢失前后是否为同一涂鸦账号、配网用的家庭、列表读取的家庭、目标设备在账号各家庭中的归属，以及是否收到设备移除事件。本轮为源码检查，没有生产账号查询或丢失现场日志。

## 排查现场信息

设备列表页在「读不到设备」和「暂无设备」两种状态下，底部会显示一行可复制的诊断信息：

```
uid <userNo> · 家庭 <homeId> · 设备 N 台 · <失败原因>
```

Android 原生日志使用 `FlowerpotTuya` 标签：`adb logcat -s FlowerpotTuya flutter`。可核对 `home pinned to <id>`、`home picked <id> (name=..., ... devices) of <m> homes, tag=...` 与 `ble pair: 并行配网 config(..., gid=<id>, ...)`；状态层联调日志中的 `上报 ← 设备被解绑 <deviceId>` 来自设备移除事件。现有日志会带 Wi-Fi 名称和账号归属信息，对外分享前应脱敏，禁止复制令牌与密码。
