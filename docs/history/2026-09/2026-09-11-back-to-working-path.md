# 2026-09-11 回到 git 里最后一版能配网成功的路径；授权统一收在「连接」按钮

## 产品口径

> 原则就是整个配网流程都不弹出系统的 UI，用我们自己的页面。搜索的设备列表、设备右边的
> 连接按钮，**假如必须要授权，是否可以在那个按钮上统一处理**。或者你看以前的代码，
> 那个是可以配网成功的，为什么现在就出现超时等问题。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `fbf1f76`。

## 按要求查 git：答案很确定

`git show 223bdae^:lib/src/features/devices/presentation/pairing_page.dart` —— 那是**最后
一版能配网成功**的代码，配网页调的是 `state.pairViaHotspot(...)`，而该方法的序列是：

```
取令牌 → _joinHotspotForPairing（= WifiNetworkSpecifier，App 自己把手机连上热点）
       → _pairInternal → pairWifiDevice（涂鸦「原流程」ActivatorModelEnum.TY_AP）
```

**老版能成，正是因为它自己把手机连上了热点。**

提交 `223bdae`「配网切到涂鸦『热点配网新流程』，SDK 自己连热点」把这一步换成了"指望 SDK
自己连"。**从那以后全是 `207220`（配网任务整体超时）。** 这就是"为什么现在超时"的答案——
反复实测（45s 空等、设备侧一个具体码都没回）证明 **SDK 并不连**。

## 产品给的出路正好可行

"如果必须授权，就统一收在那颗『连接』按钮上" —— 这正是能同时满足两件事的办法：

- 配网能成（热点真的被连上）；
- 系统 UI **只在一处、只出现一次**，之后的页面（输密码、配网进度）一个框都没有。

## 改动

### `lib/src/features/devices/presentation/device_search_page.dart`

`_connectAndOpen` 恢复为**真的连热点**：抓当前路由器名 → `await _prepared`（云端三件事必须
在连热点之前）→ `connectDeviceHotspot(确切 SSID)` → 成功才跳页；失败把原因画在页面上，
再点一次即可。副标题写明"系统会弹一次确认框，请点「连接」"。

文档注释里把 git 查证结论写进去了：`223bdae^` 能成、`223bdae` 之后超时，**这一步不能省**。

### `lib/src/features/devices/presentation/pairing_page.dart`

`_startPairing` 改回 **`state.pairViaHotspot(...)`**（取令牌 → 连热点 → `pairWifiDevice`）。
手机已经在热点上了（搜索页那颗「连接」干的），所以它内部的连热点一步会检测到"已在目标
热点上"而跳过——**这一页不会再弹系统框**。

新流程的代码（`pairViaDeviceHotspot` / `apStartPairing` / 安全配置预取 / `onStep` 进度 /
207xxx 失败码）**全部保留**，将来要再试只需换这一处调用点。

### `docs/PRODUCT_RULES.md`

- **1.2 整节重写**为「系统 UI 只允许出现在一处：搜索页那颗『连接』」，并把 git 查证
  （`223bdae^` 能成 / `223bdae` 之后超时）写成「⚠️ 这一步不能省」。
- 1.4 动线表改为：第 2 步连热点（框只在此出现一次），第 4 步走 `pairViaHotspot` 且
  **不会再弹任何系统框**。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链。按 §6 清单自检：

1. 两个改动文件括号配平。
2. `pairViaHotspot` 的签名与调用一致（`ssid` / `password` / `hotspotSsid`，
   `hotspotJoinedManually` 有默认值）。
3. `connectDeviceHotspot` / `pairViaHotspot` 都存在且各有一个调用点。
4. 没有引入新语法糖。

## 遗留

- 真机验证：**框只在点「连接」时出现一次**，输完密码点「开始配网」不再出现；以及**配网
  能否成功**（这是回到老路径的全部目的）。
- 若仍失败，失败消息现在末尾会带「手机在「xxx」(设备热点/不是设备热点)」——先看这一项。
- 新流程那套代码留着，等涂鸦工单说清 `queryDeviceConfigState` 在 Android 10+ 内部如何连 AP
  之后再考虑切回去。
