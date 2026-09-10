# 2026-09-10（晚，定稿）配网新流程：全程不用 `WifiNetworkSpecifier`，并收拢反复改动的文档

## 用户口径

> 不要弹框，已经接入了涂鸦的新模式的 AP 接入，不需要弹框的。
> 现在的改动都是为了绕开 Android 系统的入网授权框。`WifiNetworkSpecifier` 在
> Android 10+ 必弹 这个限制。
>
> 记得改文档不要来来回回的乱改啊。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `3ec6577`。

## 我之前的判定错在哪

当天较早我把 `_joinHotspotForPairing`（`WifiNetworkSpecifier`）加回了配网流程，依据是
「不连热点就配不上」。**这个依据不成立**，因为它来自一次不完整的对照：

| 尝试 | 实际调用 | 结果 | 缺了什么 |
| --- | --- | --- | --- |
| A | 搜索页调 `queryDeviceConfigState` | 卡住到超时 | 位置错（手机还在路由器上，取令牌/取安全配置都要外网），**且当时还没有 `getDeviceSecurityConfigs`** |
| B | 只调 `startActivator` | `out of time`，无 207xxx | **把 `queryDeviceConfigState` 整个删了** —— 而新流程里建立与设备那条通道的正是它 |
| C | 自己连热点 + `startActivator` | `207220` 配网任务整体超时 | 仍然缺 `queryDeviceConfigState`；而且把要绕开的框请回来了 |

B 被我当成了「SDK 自己不会连热点」的证据，其实它只证明了「没有①就不行」。
**完整序列（安全配置 + 令牌预取 → `queryDeviceConfigState` → `startActivator`）在这之前
从未被完整试过一次。**

## 改动

### `lib/src/state.dart` — `pairViaDeviceHotspot` 去掉 `WifiNetworkSpecifier`

序列收敛为两步，**App 侧不再碰任何连 Wi-Fi 的系统 API**：

```
connectingDevice: ① apQueryDeviceWifi(timeout: 45s)
                     = queryDeviceConfigState，SDK 自己连设备热点并查设备状态
                       （设备 Wi-Fi 列表收下不展示；只容忍 207207）
sendingWifi:      ② apStartPairing(ssid, password, timeout: 120s)
connectingCloud:  1–2s 随机停留后按成功处理
```

- 删掉 `_joinHotspotForPairing` 调用。文档注释里写明**铁律**：不要为了「先把热点连上」
  去调 `joinDeviceHotspot`，那等于把框原样请回来、等于白做这套新流程。
- `queryTimeout` 由 25s 提到 **45s**：这一步现在要自己完成「找热点 + 连上 + 握手」。
- 失败收尾改用新增的 `_releaseDeviceHotspotPairing()` → `apStopPairing()`。热点连接挂在
  **SDK 的配网器**上，不是 `joinDeviceHotspot` 的进程网络绑定，所以**不能**用
  `leaveDeviceHotspot`。
- `hotspotSsid` 参数保留但只进诊断文案（新流程不需要我们给热点名，SDK 自己找）。
- 每步耗时仍记进失败消息（`｜连设备 8.2s · 配网 120s`）。

### `lib/src/features/devices/presentation/pairing_page.dart`

调用点注释重写成一句定论 + 指向 `pairViaDeviceHotspot` 的文档注释，不再在页面里复述序列。

### `AI_CONTEXT.md` — 收拢，不再增量打补丁

那一段已经堆成一串自相矛盾的过程记录（同一个「要不要连热点」来回三遍），而
`AI_CONTEXT.md` 自己的规则是「current facts 的快照，不是时间日志」。这次把整段 AP 配网
内容**一次性替换**成一个定稿块：铁律 → 四步动线 → 桥接与死代码 → 涂鸦不提供 AP 发现
能力 → 失败码 → 产品事实 / iOS，并删掉两处与定论矛盾的旧句（「Android 那个『要连接至
设备吗?』…只能做到不重复弹」、「`pairViaHotspot` 串完取令牌 → App 连设备热点 → 配网」）。
末尾注明：**三次试错的过程细节在 `docs/history/2026-09/` 里，不在 AI_CONTEXT 重复。**

以后这类反复只写进 history，AI_CONTEXT 只留结论。

## 验证

**未验证。** 本机没有 Flutter/Dart/Kotlin 工具链。静态自检：

- `state.dart` 括号增量与 HEAD 同基线（该文件在 HEAD 上本来就有 1 个 `(` 的计数偏差，
  来自多行字符串，是脚本已知假阳性）；`pairing_page.dart` 配平为 0。
- `state_pairing_test.dart` 的新流程用例：现在的序列是 `apQueryDeviceWifi` →
  `apStartPairing`，两者 mock 都有实现且返回成功，`joinDeviceHotspot` 不再被调用，
  断言（配网成功、`selectedDevice` 非空、`pairingStage` 回到 idle、
  `stopDevicePairing` 后列表清空）均不受影响。

## 遗留

- **这是第一次完整跑官方序列，必须真机复测。** 若 ① 仍然超时，下一步**不是**再把
  `WifiNetworkSpecifier` 加回来，而是：
  - 先看失败消息里的耗时行——`连设备` 那段用了多久，45s 是否真的跑满；
  - 查 `207201`（和设备建立连接通道失败）是否出现，它才是「通道建不起来」的专用码；
  - 必要时向涂鸦工单确认 `queryDeviceConfigState` 在 Android 10+ 上**内部**是怎么连 AP 的
    （如果它自己也用 `WifiNetworkSpecifier`，框会由 SDK 弹出来，那就是系统层面无解，
    需要产品重新决策）。
