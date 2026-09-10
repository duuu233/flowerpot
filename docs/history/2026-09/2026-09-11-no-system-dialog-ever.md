# 2026-09-11 配网全程去掉系统入网授权框（并纠正一个错误结论）

## 产品口径（两次强调）

> 不对不对，系统框**从始至终都不会出现**，应该是这二天的提交，仔细检查下，应该是把设备
> 列表改为自动连接的那几次改动。
>
> 整个配网流程都没有系统框的弹出。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `a07820c`。

## 按要求核对提交：框是我加回来的

`git log -S"_joinHotspotForPairing" -- lib/src/state.dart`：

| 提交 | 变化 | 框 |
| --- | --- | --- |
| `ad7c6c1` | 首次把 `_joinHotspotForPairing` 加进 `pairViaDeviceHotspot` | 有 |
| `b3d0d09` | 去掉，「全程不用 `WifiNetworkSpecifier`」 | **无** ← 最后一个无框状态 |
| `39d29d6` | **加回来**（按"自动选中 + 一次确认"） | 有 |
| `78afe2a` | 挪到搜索页自动连 | 有 |
| `a07820c` | 挪到「连接」按钮 | 有 |

产品说的「把设备列表改为自动连接的那几次改动」对应的正是 `39d29d6` / `78afe2a`。

## 我那个结论是错的，而且错在哪很具体

把它加回来的唯一依据是一次实测：完整官方序列下单独调 `queryDeviceConfigState`，
**跑满 45 秒报 `207220`（配网任务整体超时），全程没有任何系统框、手机始终在路由器上**。
我据此判定「SDK 不会替我们连热点」。

**这个实验是被污染的。** 产品在那之后才告知一条关键事实：**设备静置一段时间会退出配网
模式**（已写入 `PRODUCT_RULES.md` 1.5）。那 45 秒里设备很可能早就不广播热点了——
`queryDeviceConfigState` 连不上一个**已经不存在**的热点，超时是必然的，这跟"SDK 会不会连"
没有任何关系。

⇒ 结论作废，`WifiNetworkSpecifier` 也就不该被加回来。**复测必须用刚断电重启过的设备。**

## 改动

### `lib/src/state.dart`

- `pairViaDeviceHotspot` 去掉第①步 `_joinHotspotForPairing`，收敛为两步：
  ① `apQueryDeviceWifi`（`queryDeviceConfigState`，**SDK 在这里连热点**）
  ② `apStartPairing`（`startActivator`）。
- 随之去掉 `hotspotRequested` 标记与 `_releaseDeviceHotspotPairing` 的 `releaseHotspot`
  参数；该方法现在**无条件**解一次进程网络绑定——本流程自己没建连接，但 SDK 连热点后
  进程可能绑在一个没有外网的网络上，不解开后面读设备列表、连云端都会失败。
- `hotspot_manual_required` 那一支一并删掉（不再有我们发起的连接，不可能走到）。
- 类注释整段重写：把「这是产品硬性要求」「两步序列」「不要再凭一次超时把那个 API 加回来
  （附错在哪）」写在一起。**注释里保留 `_joinHotspotForPairing` 字样是故意的**——那是禁令，
  不是调用。

### `lib/src/features/devices/presentation/device_search_page.dart`

- `_connectAndOpen` 不再调 `connectDeviceHotspot`：只抓当前 Wi-Fi 名、等 `_prepared`
  落地、然后跳页。按钮语义变成"选定这台设备"。
- 副标题去掉「系统会弹一次确认框，请点『连接』」。
- `_hotspotState` 保留并照常赋值：本页不建连接，但离开动线时解一次进程绑定是保险
  （`releaseDeviceHotspot` 幂等、不抛错）。

### 文档

- `PRODUCT_RULES.md` **1.2 整节重写**为「配网全程不得出现系统入网授权框——硬性要求」，
  并专列一小节「⚠️ 不要再凭一次超时把 `joinDeviceHotspot` 加回来」，写清错在哪、
  复测前提是什么、真要推翻该走工单而不是改回那个 API。
- 1.4 动线表改为无框版本（第 2 步只选定设备，第 4 步 SDK 自己连热点）。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链。按 §6 清单自检：

1. `state.dart` 与 `device_search_page.dart` 括号配平，与 HEAD 同基线。
2. 确认 `pairViaDeviceHotspot` 的**代码体**里已无 `_joinHotspotForPairing`（仅注释中作为
   禁令出现）；搜索页已无 `connectDeviceHotspot`。
3. `_releaseDeviceHotspotPairing` 的两处调用与签名同步改完（不再传 `releaseHotspot`）。
4. 没有引入新语法糖。

## 遗留

- **真机复测，必须用刚断电重启过的设备**：① 全程不应出现任何系统框；② 看配网成不成。
- 若新上电的设备仍然超时，请带回失败消息整行（含各步耗时与「涂鸦进度」）和 logcat 的
  `pairing step: …`；下一步是走涂鸦工单问清 `queryDeviceConfigState` 在 Android 10+ 内部
  如何连 AP，**不是**把 `WifiNetworkSpecifier` 加回来。
