# 2026-09-10（晚）配网全按新流程：补齐三步序列，并把失败码表补到官方全量

## 背景

用户定调：**「都按新流程来」**。同时测试给回了确切的失败提示：

> 配网失败，请重试
> 设备未能成功连接到当前Wi-Fi网络
> 等待设备回应超时，整条配网通道没有建立起来：请给设备重新上电…… **（207220）**

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `ad7c6c1`。

## 查证：207220 是什么

我们存档的错误码表（中文页）**只到 207218**，所以 207220 一开始查不到。从英文页
（`/en/docs/app-development/hotspot-mode?id=Kaixk6wxla1oy`）补齐后确认，中文页漏了三条：

| 码 | 官方原文 | 中文 |
| --- | --- | --- |
| 207219 | Failed to connect to iot-dns in the cloud during device activation. | 设备激活时连接云端 iot-dns 失败 |
| **207220** | **The pairing task timed out.** | **配网任务整体超时** |
| 207222 | Failed to get the Wi-Fi networks of the device. | 获取设备 Wi-Fi 列表失败 |

**关键不在 207220 本身，在于哪些码没出现**：没有 207201（和设备建立连接通道失败），
也没有 207209–207213（设备**收到配网信息之后**的各类失败）。也就是配网任务一路空转到
整体超时，设备从头到尾没有报过任何进展——正是「手机压根没连上设备热点」的表现。
（该反馈对应的包是 `816f512`，还不含 `ad7c6c1` 加回的连热点步骤。）

## 三次实测得到的结论

| # | 做法 | 结果 | 说明 |
| --- | --- | --- | --- |
| A | 搜索页调 `queryDeviceConfigState`，手机还在路由器上 | 卡在「正在连接…」到超时 | 它要先建通道才能查状态，手机不在热点上就没有对象可问 |
| B | 不连热点，直接 `startActivator` | `out of time`，**无任何 207xxx** | 设备从没收到东西；文档那句「SDK 会自动去连接 AP 热点」**不足以**替代这一步 |
| C | 连热点 + `startActivator`，跳过查询 | `2070xx`「设备连接超时」 | `startActivator` 指望查询那一步先把通道和设备状态准备好 |

⇒ **官方新流程的三步一步都不能少。** A 证明查询要放在连上热点之后（当初把它从搜索页
删掉，删的位置对、删掉本身错了）；B 证明连热点不能省；C 证明查询不能省。

## 改动

### `lib/src/state.dart` — `pairViaDeviceHotspot` 补成完整序列

```
connectingDevice:
  ① _joinHotspotForPairing(target)        手机连设备热点
  ② apQueryDeviceWifi(timeout: 25s)       queryDeviceConfigState：建通道 + 查设备状态
                                          （列表收下不展示；只容忍 207207）
sendingWifi:
  ③ apStartPairing(ssid, password)        下发路由器凭据
connectingCloud: 固定 1–2s 后按成功处理（云端那一步没有实际业务）
```

- 新增 `hotspotSsid`、`queryTimeout` 参数。
- **每一步都记耗时**，失败时以 `｜连热点 1.2s · 查设备 0.3s · 配网 120s` 附在消息后。
  失败码只说「哪一类」，耗时才说「死在哪一步」——比如「连热点」那段有耗时就说明热点
  确实连上了、失败在之后；只有「连热点」没有「查设备」就说明通道没建起来。
- 失败清理沿用原流程规则：`_abandonPairingAttempt(releaseHotspot:, invalidateToken:)`；
  `hotspot_manual_required` 不算失败。

### `lib/src/features/devices/presentation/pairing_page.dart`

调用点回到 `pairViaDeviceHotspot`（本轮中途曾按「设备方流程 = 原流程」的推理切到
`pairViaHotspot`，用户明确「都按新流程来」后撤回），并传 `hotspotSsid`。

### `lib/src/features/devices/presentation/pairing_failure_page.dart`

- 补 `207219` / `207220` / `207222` 三条提示。207220 的提示明说它是**整体超时、不指向
  某一步**，并把注意力引到耗时那一行。
- 新增 `_hintForUnknownTuyaCode`：未登记的 `207*` 码给一句**族级**提示，不编具体含义。
- 新增 `_stepsOf`：把消息里 `｜` 之后的各步耗时单独显示一行。

### `docs/reference/tuya-ap-mode-android.md`

错误码表补上三条，并注明是从英文页补的、中文页当时漏了。

### `test/features/devices/pairing_failure_page_test.dart`

原来断言各步耗时**不**显示（`isNot(contains('令牌 812ms'))`）——那正是本次要改的行为，
改成断言它显示，并补一条断言 `｜` 之前的原文不重复显示。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链。静态自检：

- `state.dart` 括号增量与 HEAD 同基线（该文件在 HEAD 上本来就有 1 个 `(` 的计数偏差，
  来自多行字符串，是脚本已知假阳性）；其余改动文件配平为 0。
  期间一次替换切多了一段、留下重复的 `} finally {…});` 尾巴，已定位并删掉。
- `state_pairing_test.dart` 那条新流程用例：不传 `hotspotSsid` 且 `_wifiScan` 为空 ⇒
  `target` 为 null ⇒ 走前缀那一支 ⇒ `MockTuyaRepository.joinDeviceHotspot` 返回 true；
  `apQueryDeviceWifi` mock 有实现并返回非空列表 ⇒ 三步都能过，断言不受影响。

## 遗留

- **要用最新包复测**：207220 那次反馈对应的是 `816f512`，不含连热点与查询两步。
- 下次失败请连**各步耗时那一行**一起带回来，它比失败码更能定位：
  - 只有「连热点」⇒ 通道没建起来，怀疑热点没真正连上（授权框被取消？热点已消失？）；
  - 有「查设备」⇒ 通道通了，失败在下发凭据之后，看 207209–207215 具体码；
  - 「连热点(已连)」⇒ 手机本来就在热点上，没有弹授权框。
