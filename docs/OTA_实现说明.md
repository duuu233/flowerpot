# 固件升级状态监控（花盆 / 割草机）

> 文档类型：实现说明
> 状态：Active
> 最后核验：2026-09-24（按当前源码）

| 日期 | 更新内容 | 落点 |
| --- | --- | --- |
| 2026-09-24 | 新增成功判定兜底：版本号 DP（花盆 148 / 割草机 112）等于目标版本即升级完成，与涂鸦成功回调并存 | §2.3、§2.5、附录 A6/A8 |
| 2026-09-24 | 新增附录：发起升级与进度的实现步骤（逐层调用的方法） | 附录 A |
| 2026-09-24 | 更正：割草机版本号是 DP112（此前误写 113）；固件方「订阅 DP112」对割草机成立 | §4、§5 |
| 2026-09-24 | 花盆与割草机的升级入口统一为 `runFirmwareUpgrade`；割草机当前版本改读设备 DP | §1 触发时机、§4、§5 |
| 2026-09-24 | 改为只讲升级状态监控：新版本怎么发现、升级中状态怎么收、结束与兜底、现状缺口 | 全文重写 |
| 2026-09-24 | 新建：花盆与割草机 OTA 实现逻辑及差异 | 全文 |

**结论**：状态监控分两段，花盆和割草机共用同一套代码，升级入口也是同一个函数 `runFirmwareUpgrade`（剩下的差异是设备侧 DP 和进设置页是否静默查，见 [§4](#4-花盆与割草机的差异)）。

| 段 | 方式 | 数据来源 |
| --- | --- | --- |
| ① 有没有新版本 | **主动拉取**，没有推送订阅 | 涂鸦云端的 OTA 记录（SDK 查询） |
| ② 升级中的状态 | **SDK 回调推送**，没有轮询 | 涂鸦 SDK 的 OTA 监听；割草机另有 DP116 |

## 1. 新版本监控（拉取）

**调用**：Android `newOTAInstance(devId).getOtaInfo()`，iOS `getFirmwareUpgradeInfo`（`state.checkFirmware` → `tuya_repository.dart` → 原生层）。

**判定**：SDK 按组件返回记录，取 `upgradeStatus == 1`（有待装版本）那一条，拿出新版本号、当前版本号、升级方式。新版本号为空或等于当前版本号 = 没有新版本；否则记进 `_availableFirmware`，小红点亮起。

**触发时机**（没有定时器，全是事件触发）：

| 触发 | 花盆 | 割草机 |
| --- | --- | --- |
| 停在设备页上：路由变化或状态刷新时检查，**同一台设备 1 分钟内只问一次**（`FirmwareReminderHost`） | ✓ | ✓ |
| 进入设置页、「其他设置」页，各静默查一次 | ✓ | — |
| 点升级入口（`runFirmwareUpgrade`）时，之前没查到新版本就当场再问 | ✓ | ✓ |
| 网络异常弹窗点「重试」 | ✓ | — |

**结果去向**：小红点，以及按升级方式弹的提醒框（提醒升级 / 强制升级 / 检测升级只亮红点）。正在升级且没卡住时，不再弹提醒框。

## 2. 升级中状态监控（推送）

### 2.1 链路

逐层调用的方法见 [附录 A](#附录-a发起升级与进度实现步骤)。

```
发起升级（原生层只回答「已发起」）
  → SDK 的 OTA 监听回调
  → 原生层发事件 {deviceId, ota:{status, percent, stage, message}}（事件通道）
  → tuya_repository.otaUpdates
  → state._applyOtaProgress（合并、记录时间）
  → 进度弹层 / 功能行 / 小红点
```

发起时 App 先把状态置为 `running 0%`，并记下目标版本号。OTA 实例一直留着引用（Android 放在 `otaInstances`，iOS 放在 `upgrading`），升级结束才释放；否则监听会被回收，进度条会停住不动。退出登录时统一释放。

### 2.2 回调 → 状态

| Android（`IThingOtaListener`） | iOS（设备 delegate） | 转成 |
| --- | --- | --- |
| `onProgress(type, percent)` | `firmwareUpgradeProgress` | `running` + 百分比 |
| `onStatusChanged(code, type)` | 无 | `running` + 阶段码（只转下表中的码） |
| `onSuccess` | `deviceFirmwareUpgradeSuccess` | `success` |
| `onFailure` / `onError` | `deviceFirmwareUpgradeFailure` | `failed` + 失败原因 |

阶段码（涂鸦 SDK 7.5.1 `DevUpgradeStatusEnum`）：

| 码 | 含义 | 界面 |
| --- | --- | --- |
| 13 / 14 / 100 | 云端排队、准备 | 固件准备中 |
| 2 | 升级中 | 固件升级中 N% |
| 5 | 等待设备唤醒 | 等待设备唤醒 |
| 6 | 固件已下载到设备 | 固件安装中 |

### 2.3 合并规则（`_applyOtaProgress`）

- 已经有了结论（成功或失败），迟到的 `running` 事件一律丢弃。
- 百分比和阶段码往往分开到达，缺哪个就沿用上一次的值，不会把进度条打回 0。
- 每收到一个事件都刷新「最后事件时间」，用于判断是否卡住。
- **成功**：熄灭小红点，版本号显示为目标版本。**失败**：弹层显示失败原因；目标版本号**保留**，供版本号兜底继续比对。

### 2.4 界面怎么读

- 百分比显示：0% → 准备中；1–97% → 升级中 N%；≥98% 或阶段码 6 → 安装中，进度条改成来回走的动画。进度自己走到 98% 时，先停留 0.9 秒再切换。
- 进度弹层在升级结束前关不掉；「其他设置」里的功能行、割草机设置页的红点也读同一份状态（升级中不显示红点）。

### 2.5 兜底

- **成功判定兜底（版本号 DP）**：设备上报的版本号等于这次升级的**目标版本**（涂鸦检测升级返回的新版本号，不是设备当前版本号），就按升级完成处理，进度弹层换成「升级完成」。花盆看 DP148，割草机看 DP112。
  - 和涂鸦成功回调**并存**：任何一方先满足就跳到成功页，后到的一方不再改变结论。
  - 条件：这条上报里真的带了版本号 DP（`changedDps`），并且 App 里发起过这次升级（`_pendingOtaVersion` 有值）；比较时忽略版本号前面的 `V`。
  - 涂鸦先报了失败（例如超时），随后版本号对上了，也会改判为升级完成。
  - 实现：`FlowerpotState._confirmOtaByReportedVersion`，在 `_applyDeviceUpdate` 里调用。
- **卡住**：10 分钟没有任何事件就判定为已中断（`otaStallTimeout`），允许用户重新检查；同时提醒框也恢复弹出。
- **割草机 DP116 `ota_status`**：设备自己上报，`"7"` 表示不在待机、拒绝升级，`"20"` 表示升级失败，收到就弹提示（`mower_device.dart`）。它是涂鸦回调之外的补充，不参与进度。

## 3. 状态存在哪

全部只存在内存里（`state.dart` 的 `_availableFirmware` / `_otaProgress` / `_otaUpdatedAt` / `_pendingOtaVersion`），不落盘。

## 4. 花盆与割草机的差异

**升级入口的逻辑和交互已统一**（`features/devices/presentation/firmware_upgrade_flow.dart` 的 `runFirmwareUpgrade`，花盆「其他设置 → 固件版本更新」和割草机「设置 → 设备升级」都调它）：

| 情况 | 两边一致的行为 |
| --- | --- |
| 正在升级（没卡住） | 重新打开进度弹层 |
| 卡住（10 分钟没有事件） | 弹「升级似乎已中断」，确认后清掉旧进度、重新问云端 |
| 设备离线 | 提示「花盆已离线，无法检查固件」或「割草机已离线，无法检查固件」，不跳页 |
| 问云端 / 发起升级期间 | 入口那一行转圈，同时挡住连点（`isCheckingFirmware`） |
| 有新版本 | 弹「检查更新」框（当前版本 → 新版本），确认后发起升级、打开进度弹层 |
| 升级提醒弹窗点「立刻更新」 | 跳到设置页（花盆「其他设置」，割草机「设置」栏），再弹「检查更新」框 |

剩下的差异都来自设备本身：

| 项 | 花盆 | 割草机 |
| --- | --- | --- |
| 当前版本号 | DP 148 `firmware_version` | DP 112 `fw_version`（如 `"1.1.3"`） |
| 版本 DP 都没报时 | 退回 SDK 的 `verSw` | 同左 |
| 设备侧升级状态上报 | 无 | DP116 `ota_status` |
| 进设置页静默查新版本 | 设置页、「其他设置」页各查一次 | 只靠提醒弹窗的检查（割草机各页都算设备页） |

## 5. 现状缺口

- **发现新版本慢 1～2 分钟**：云端 OTA 记录本身有滞后，加上 App 自己 1 分钟的节流。
- **设备重新上线、版本号 DP（花盆 148 / 割草机 112）变化，都不会触发重查新版本**。要缩短上面的延迟，App 侧可以从这里补。
- **App 重启后进度丢失**：状态只在内存里。重启时如果设备还在升级，云端返回的是 `upgradeStatus = 2`（升级中），App 只认 1，会当作「没有新版本」，界面也看不到正在升级。
- iOS 不转发阶段码，只有百分比和成败。
- 涂鸦 App SDK 有没有「新版本可用」的推送接口，还没解包核对。
- 固件方清单里的「订阅 DP112」：对**割草机**成立——DP112 `fw_version` 是它上报的当前版本，设备重新连上云端时会报一次，App 目前只拿它显示版本，还没用它触发重查新版本（即上面第二条）。花盆的 112 是空气温度，花盆对应的是 DP148。

## 附录 A：发起升级与进度——实现步骤

**通道**：方法通道 `com.common.yikaltd/tuya`（Dart 调原生），事件通道 `com.common.yikaltd/tuya_events`（原生推给 Dart）。

### A1. 入口（Dart，花盆和割草机共用）

`runFirmwareUpgrade(context, deviceId, {confirmed, log})`（`features/devices/presentation/firmware_upgrade_flow.dart`）：
- 花盆：「其他设置 → 固件版本更新」（`DeviceOtherSettingsPage._checkFirmware`）调它；
- 割草机：「设置 → 设备升级」经 `upgradeMowerFirmware` 调它，额外传入联调日志 `log`；
- 升级提醒弹窗（`FirmwareReminderHost`）点「立刻更新」：先跳到上面两个设置页，再调它。

入口里依次处理：
1. 正在升级、没卡住 → `showOtaProgressDialog`；卡住了 → `showAppConfirmDialog`（「升级似乎已中断」），确认后 `clearOtaProgress`；
2. `isDeviceOnline` 为 false → `showAppMessage`（「花盆 / 割草机已离线，无法检查固件」）；
3. `setCheckingFirmware(id, true)`，入口行开始转圈；
4. 取 `availableFirmwareFor(id)`，没有就 `checkFirmware(id)` 问云端；
5. `showFirmwareUpdateDialog`（当前版本 → 新版本）；
6. 用户点「立即更新」→ `FlowerpotState.upgradeFirmware(id, version)`；
7. 成功 → `showOtaProgressDialog`；失败 → `showDeviceActionResult`；
8. `finally` 里 `setCheckingFirmware(id, false)`。

### A2. 状态层发起（`state.dart`）

`upgradeFirmware` 包在 `_guard` 里：
1. `await _repository.startFirmwareUpgrade(id)`；
2. `_pendingOtaVersion[id] = version`，记下目标版本；
3. `_otaProgress[id] = OtaProgress(running, percent: 0)`；
4. `_otaUpdatedAt[id] = now`；
5. 返回 `ActionResult(true, …)`。

### A3. 仓库层（`tuya_repository.dart`）

`MethodChannelTuyaRepository.startFirmwareUpgrade(deviceId)` → `_invoke('startFirmwareUpgrade', {deviceId})`。

### A4. 原生发起

**Android**（`MainActivity.kt`，涂鸦类通过反射调用）：
1. `handle(call)` 收到 `"startFirmwareUpgrade"` → `startFirmwareUpgrade(call, result)`；
2. `otaInstance(deviceId)`：`ThingHomeSdk.newOTAInstance(devId)`，按 deviceId 缓存在 `otaInstances`，避免监听被回收；
3. `ota.setOtaListener(otaListenerProxy(...))`，这是 `IThingOtaListener` 的动态代理；
4. `ota.startOta()`，随即 `answerStarted()`，也就是 `result.success(null)`，只代表「已发起」；
5. 老版本 SDK 没有 `setOtaListener` 时，改用 `startOta(callback)`。

**iOS**（`AppDelegate.swift`）：
1. `startFirmwareUpgrade(args, result)`；
2. `otaDevice(id)`：设备已在监听中就复用那个实例，否则新建 `ThingSmartDevice`，设 `delegate = self`，放进 `upgrading` 留住引用；
3. `device.getFirmwareUpgradeInfo` 取 `upgradeStatus == 1` 那条记录；没有就回错误 `firmware_up_to_date`；
4. `device.upgradeFirmware(pending.type, success: result(nil), failure: releaseOta + 回错误)`。

### A5. 原生回调 → 事件

事件格式统一为 `{deviceId, ota: {status, percent?, stage?, message?}}`：Android 经 `emitOta` → `emit` → `events.success`，iOS 经 `emitOta` → `emit` → `eventSink`。

| Android 回调（代理） | iOS 回调（delegate） | 发出的事件 |
| --- | --- | --- |
| `onProgress(type, percent)` | `device(_:firmwareUpgradeProgress:progress:)` | `running` + `percent`（iOS 为 `progress × 100`） |
| `onStatusChanged(code, type)`，只转 2/5/6/13/14/100 | 无 | `running` + `stage` |
| `onSuccess` | `deviceFirmwareUpgradeSuccess` | `success`，然后 `releaseOta` |
| `onFailure` / `onError` | `deviceFirmwareUpgradeFailure` | `failed` + `message`，然后 `releaseOta` |

`releaseOta`：Android 移出缓存并调 `onDestroy`；iOS 移出 `upgrading` 并把 `delegate` 置空。退出登录时，`releaseDeviceListeners` 会把所有 OTA 实例一起释放。

### A6. Dart 接收（`tuya_repository.dart` → `state.dart`）

1. `otaUpdates = _rawEvents.map(_otaUpdate)`：把事件解析成 `OtaProgress`，阶段码经 `OtaStage.fromTuya` 转换；
2. `_listenForDeviceUpdates()` 里订阅：`_repository.otaUpdates.listen(_applyOtaProgress)`；
3. `_applyOtaProgress(incoming)`：
   - 已经有了结论（成功或失败），迟到的 `running` 事件直接丢弃；
   - 百分比和阶段码缺哪个，就沿用上一次的值；
   - 更新 `_otaProgress[id]`、`_otaUpdatedAt[id]`；
   - `success`：`_availableFirmware.remove(id)` 熄灭红点，`_replaceDevice(... firmwareVersion: 目标版本)`；
   - `failed`：保留 `_pendingOtaVersion`，供版本号兜底继续比对；
   - 最后 `notifyListeners()`。

### A7. 界面（`ota_progress_dialog.dart`）

- `showOtaProgressDialog`：`showDialog` 贴底、满宽，`PopScope(canPop: !running)`，升级结束前关不掉；
- `_OtaProgressDialog` 读 `state.otaProgressFor(id)`，由 `OtaProgress.displayStage` 决定显示哪个阶段，文案由 `otaRunningLabel` 生成：0% 准备中 / 1–97% 升级中 N% / ≥98% 或阶段码 6 安装中；
- `_holding`：进度走到 98% 时先停留 0.9 秒（`_holdAt98`），再切到安装中。

### A8. 兜底

- 版本号 DP 兜底：`_listenForDeviceUpdates` → `_applyDeviceUpdate(update)` → `_confirmOtaByReportedVersion(device, changedDps)`：
  1. 取版本号 DP 号：割草机 `MowerDp.fwVersion`（112），花盆 `TuyaConfig.dp['firmware_version']`（148）；这条上报的 `changedDps` 里没有它就直接返回；
  2. 目标版本取 `_pendingOtaVersion[id]`，没有（App 里没发起过升级）就返回；已经是 `success` 也返回；
  3. `device.firmwareVersion` 与目标版本比较（去掉前面的 `V`），相等就 `_applyOtaProgress(OtaProgress(success))`。之后的处理和涂鸦成功回调完全一样（A6 第 3 步）。
- `otaStalled(id)`：状态还是 `running`，但超过 10 分钟（`otaStallTimeout`）没有任何事件，就判定为卡住；再点入口时走 A1 的第 1 步；
- 割草机另有 DP116：`MowerDevice` 处理上报时，看到 `changed` 里有 116，`"7"` 或 `"20"` 就经 `_failures` 发给 `MowerHomePage`，弹提示。
