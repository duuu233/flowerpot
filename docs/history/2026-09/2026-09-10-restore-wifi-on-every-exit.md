# 2026-09-10（晚）每条退出路径都把手机 Wi-Fi 还回去（并修掉成功路径漏放）

## 产品要求

> 因为搜索出设备就会自动连接设备的热点，这样会导致没网络，要确保用户取消操作后、
> 假如退出 APP 或者怎么样，用户手机假如连接了 wifi，就要给它还原回去。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `78afe2a`。

## 机制：原语是对的，缺的是"保证调到"

原生 `leaveDeviceHotspot` → `unbindProcessNetwork()` 做两件事：取消
`WifiNetworkSpecifier` 的 `NetworkCallback` 注册（系统随即断开这条进程专属连接，
**Wi-Fi 自动切回已保存的路由器**）、`bindProcessToNetwork(null)` 解开进程绑定。

所以"还原"不需要记住原来连的是哪个网络——放掉请求，系统自己会回去。**问题全在调用点。**

## 审计结果

| 退出路径 | 改之前 |
| --- | --- |
| 配网中途「取消配网」 | ✅ `cancelPairing` → `stopActivator` → `unbindProcessNetwork` |
| 配网失败 | ✅ `_releaseDeviceHotspotPairing` |
| 搜索页连完热点后返回 | ❌ 什么都不放 |
| 进了「连接 Wi-Fi」页又退回来 / 输到一半退出 | ❌ 只在"配网真的跑起来过"（`_pairingState != null`）时才放 |
| **配网成功** | ❌ 不放 |
| App 被切到后台（进程还活着） | ❌ 不放，手机一直没网直到进程被杀 |
| App 被杀 | ✅ 进程专属连接随进程消失 |

**"配网成功不放"是个真 bug**：凭据一交给设备，它就关掉自己的热点去连路由器；进程这时
还绑在那个已经消失的网络上，紧接着 `_pairInternal` 要读设备列表、要连云端，自然失败——
表现正是代码里那句兜底文案「配网成功，但暂时读不到设备信息，请回设备列表下拉刷新」。

## 改动

### `lib/src/state.dart`

- 新增 `releaseDeviceHotspot()`：**不走 `_guard`、不抛错、可重复调**。职责就是"无论如何
  把网络还回去"，任何一次失败都不该盖过调用方真正要报的错。
- `pairViaDeviceHotspot` 在 `mark('配网')` 之后、进 `connectingCloud` **之前** `await` 它
  ——修掉上面那个真 bug。

### `lib/src/features/devices/presentation/device_search_page.dart`

- 新增 `_hotspotState`（`dispose` 里不能查 InheritedWidget，所以连的时候就留引用；
  **失败也留**，因为可能已经留下半条连接）。
- `dispose`：无条件放。幂等，而漏放的代价（用户莫名断网）远大于多调一次。
  本页在配网期间不会被 dispose——下一页是 push 上去的。
- 混入 `WidgetsBindingObserver`，`paused` 时放掉，并把界面退回「点连接」之前的状态
  （`_hotspotReady = false; _autoOpened = false`），如实反映连接已经没了。
  ⚠️ `_connecting` 为真时跳过：系统入网确认框会把本页 pause，那时放等于自己把刚发出去的
  请求撤回。

### `lib/src/features/devices/presentation/pairing_page.dart`

- 新增 `_scopeState`（同样给 `dispose` 用）。
- `dispose`：配网在跑 ⇒ `cancelPairing()`（内部会解绑）；**没跑也要放** ⇒
  `releaseDeviceHotspot()`。改之前这条 else 分支整个不存在。
- `didChangeAppLifecycleState` 增加 `paused` 分支：放掉（`_pairing` 时除外——那会掐断
  正在用的通道）。用户多半只是去别处看一眼 Wi-Fi 密码；真要配网时
  `pairViaDeviceHotspot` 的第①步会重新连（已连则跳过）。

### 文档

- `docs/PRODUCT_RULES.md` 新增 1.4.1：一张表列清每条退出路径怎么处理，以及**唯一两个
  不能放的时机**（配网进行中、系统确认框正显示）。
- `AI_CONTEXT.md` 记下 `releaseDeviceHotspot()` 是统一入口，以及成功路径漏放这个历史 bug。

## 验证

**未验证。** 本机没有 Flutter/Dart/Kotlin 工具链。静态自检：三个改动文件括号配平、与 HEAD
同基线。

## 遗留

- 真机验证重点：① 连上热点后按返回，手机是否自动回到原来的 Wi-Fi；② 切后台再回来，
  界面是否退回「点连接」且能重新连上；③ **配网成功后设备列表能否立刻读到**（这是上面那个
  真 bug 的验证点）。
