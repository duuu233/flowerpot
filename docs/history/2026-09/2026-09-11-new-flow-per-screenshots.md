# 2026-09-11 照智能生活截图把「新流程」这一版做出来

## 来由

产品提供的两张截图（`docs/配网1.jpg` / `配网2.jpg`）证明智能生活走的是涂鸦**新流程**：
连上设备 → 让**设备**扫 Wi-Fi → 把**设备扫到的**列表给用户选 → 输密码 → 配网。
产品要求照这个步骤做一版；**UI 风格保持本项目现有的，只改步骤**。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `9d48a63`。

## 改了什么

### 1. 进度从三步扩成五步（`tuya_models.dart`）

`PairingStage` 由 `connectingDevice / sendingWifi / connectingCloud` 改成：

| 阶段 | 我们的标签 | 智能生活原文 | 谁来驱动 |
| --- | --- | --- | --- |
| `connectingDevice` | 连接设备 | 正在尝试建立连接… | `queryDeviceConfigState` 前半段 |
| `deviceScanning` | 设备找网络 | 设备寻找可用Wi-Fi | `queryDeviceConfigState` 返回列表即完成 |
| `connectingRouter` | 设备连路由器 | 设备正在连接路由器… | `startActivator` 发出凭据后 |
| `activating` | 云端激活 | 设备激活中 | `onStep` |
| `goingOnline` | 设备上线 | 设备即将上线 | `onStep` |

**用词沿用本项目原有的短标签风格**（产品：「UI 风格不用改，只是改步骤」），细节放在
每步的 `hint` 里，不照抄智能生活的长句。进度页的标题/副标题也保持原样。

### 2. 后三步由 `onStep` 真实驱动（`state.dart`）

`pairViaDeviceHotspot` 里订阅 `pairingSteps`，按**到达顺序**推进
`connectingRouter → activating → goingOnline`（顺序由 SDK 保证；常量名官方没列，原生每收到
一条打一行 `pairing step: …`，真机日志确认后可改成按名字精确映射）。多余的上报停在最后一步。

### 3. 前两步由 `connectDeviceForPairing` 覆盖（`state.dart`）

调用期间是 `connectingDevice`；**列表拿回来就意味着「设备找网络」也做完了**，所以成功后把
阶段推到 `deviceScanning` 再收尾（失败才复位到 idle）——这样进度页上那两行的状态是真的。

### 4. 搜索页：点「连接」走新流程 + 盖进度页（`device_search_page.dart`）

- `_connectAndOpen` 由 `connectDeviceHotspot`（`WifiNetworkSpecifier`）改为
  **`connectDeviceForPairing()`**（`queryDeviceConfigState`，SDK 自己连）。
- `_connectingIndex != null` 时整页盖上 `PairingProgressView`（对应 `配网1.jpg` 那张进度卡），
  标题沿用「搜索设备」——UI 风格不变。
- 新增 `_cancelConnect()`：进度页的「取消」中止 `stopDevicePairing()` 并回到列表。

### 5. 连接 Wi-Fi 页：列表换成设备扫到的（`pairing_page.dart`）

- 「切换」弹层的数据源由手机扫描结果改为 **`state.deviceWifiNetworks`**
  （`WifiInfoBean{ssid, rssi, sec}` → 弹层按 `rssi` 画格数）；设备没给（老固件 `207207`）
  才退回手机扫到的。
- 「刷新」= 再调一次 `connectDeviceForPairing()`，让**设备**重扫（对应截图右上角那颗）。
- 进页面若还没选网络就**自动弹出列表**（这时手机挂在设备热点上，SSID 必然为空）。只弹一次。
- 配网调用改回 `pairViaDeviceHotspot`。

## 随时可切回 AP 原流程

两条路径的代码都完整保留，**各自的调用点都写了注释指路**：

- 搜索页：`connectDeviceForPairing()` ↔ `connectDeviceHotspot(hotspotSsid:)`
- 配网页：`pairViaDeviceHotspot(...)` ↔ `pairViaHotspot(...)`

换这两处即可回到 `223bdae^` 那版能配成的路径。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链。按 §6 清单自检：

1. 五个改动文件括号配平，`state.dart` 与 HEAD 同基线。
2. 新符号来源与引用逐个查过：`deviceScanning` / `connectingRouter` / `activating` /
   `goingOnline`（models + state）、`_deviceNetworks` / `_maybeOpenPicker` / `_pickerOffered`
   （pairing_page）、`_cancelConnect`（search page）、`PairingProgressView`（两页 + 组件），
   无悬空引用；旧的 `sendingWifi` / `connectingCloud` 在 lib 与 test 下**已全部迁移完毕**。
3. `PairingProgressView` 在搜索页新增了 import。
4. 核对既有断言：`pairing_failure_page_test` / `pairing_success_page_test` 里的
   `find.text('连接设备')` 是**页面标题**，那两页不渲染进度视图，与新步骤标签不冲突。
5. 没有引入新语法糖。

## 遗留：这一版能不能成，取决于一件事

`queryDeviceConfigState` 必须真的连得上设备热点。此前三次实测都是 45 秒超时（`207220`），
但**每次都可能撞上设备已退出配网模式**（产品后来才告知设备静置会退出）。

**复测前提：用刚断电重启过的设备。** 请带回：
- 是否出现系统弹框（这一版 App 侧一次都不调 `WifiNetworkSpecifier`，理论上不该有）；
- 进度页停在哪一步；
- 失败消息整行（末尾有各步耗时与「手机在「xxx」」）；
- logcat 里的 `pairing step: …`。
