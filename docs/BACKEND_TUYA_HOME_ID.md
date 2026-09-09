# 涂鸦家庭 ID：后端接口需求

> 文档类型：Active（接口契约需求）
> 最后核验：2026-09-09
> 事实来源：涂鸦 Home SDK 行为、`https://api.yikaltd.com/v2/api-docs`、`lib/src/core/backend/app_backend_repository.dart`

## 为什么需要它

涂鸦 Home SDK 里，**设备属于家庭，家庭属于账号**：

- 设备列表按家庭查：`newHomeInstance(homeId).getHomeDetail().getDeviceList()`；
- 配网令牌按家庭取：`getActivatorToken(homeId)`——**配网时用哪个 homeId，设备就落进哪个家庭**。

家庭 id 由**涂鸦云端分配**（Long），App 只能查（`queryHomeList` → `getHomeId`）或建（`createHome` 的回调里返回云端分配的 id），不能自己生成，也**不能拿 `userNo` 顶替**——`userNo` 是涂鸦登录用的 UID（字符串），涂鸦不会把它当家庭 id 认。

一个账号名下可能有多个家庭（用户自己在涂鸦「智能生活」App 里建过，或早期版本在家庭列表瞬时为空时自动建过）。此时"这次登录用哪个家庭"如果靠列表顺序决定，就会出现**重新登录后读不到已绑定设备**。所以需要一处权威存储，按账号固定住这个 id——后端是唯一能跨设备、跨重装保留它的地方。

## 需要后端做的两件事

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

1. 登录 / 注册拿到 `tuYaHomeId` → 立刻 `setHomeId` 钉给原生，并写入本地 `SharedPreferences`（`tuyaHome:<userNo>`）。
2. 后端没给 → 用本地缓存钉住；本地也没有 → 由原生按家庭列表解析（先挑带设备的家庭，同样带设备时取 `homeId` 最小的），解析结果写回本地缓存。
3. **自愈**：用钉住的家庭读设备却读到 0 台，就作废这份缓存并按涂鸦返回的列表重新解析一次——缓存只是缓存，涂鸦返回的才是准的。
4. 配网前先 `currentHomeId()` 确认家庭再取令牌，两步都在手机还连着路由器时完成；手机已在设备热点上时家庭列表为空**不再自动建家**（直接报 `home_offline`）。

在第 2 条接口就绪之前，功能不受影响，只是换手机 / 重装 / 清数据后需要重新解析一次家庭。

## 排查现场信息

设备列表页在「读不到设备」和「暂无设备」两种状态下，底部会显示一行可复制的诊断信息：

```
uid <userNo> · 家庭 <homeId> · 设备 N 台 · <失败原因>
```

Android 日志（`adb logcat -s flutter`）另有 `home pinned to <id>` 与 `home picked <id> with <n> devices of <m> homes`——`of 2` 就说明该账号下确实有两个家庭。
