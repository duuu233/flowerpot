# 固件升级状态监控（花盆 / 割草机）

> 文档类型：实现说明
> 状态：Active
> 最后核验：2026-10-12（当前源码、Android SDK 7.5.1 AAR 与涂鸦官方文档；未真机）

| 日期 | 更新内容 | 落点 |
| --- | --- | --- |
| 2026-10-12 | 核实移动端与设备 TuyaOS 的接口边界、差分 OTA 条件及耗时排查；补齐 DP168 当前行为与回调缺口 | §2.2、§2.5、§4、§5、§6 |
| 2026-09-24 | 兜底改为只在「固件安装中」（≥98% 或阶段 6）时判断；去掉「失败后改判成功」 | §2.3、§2.5、附录 A6/A8 |
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

| Android（`IOtaListener`，7.5.1） | iOS（设备 delegate） | 转成 |
| --- | --- | --- |
| `onProgress(type, percent)` | `firmwareUpgradeProgress` | `running` + 百分比 |
| `onStatusChanged(code, type)` | 无 | `running` + 阶段码（只转下表中的码） |
| `onSuccess` | `deviceFirmwareUpgradeSuccess` | `success` |
| `onFailure` / `onError` | `deviceFirmwareUpgradeFailure` | `failed` + 失败原因 |
| `onTimeout(type)` / `onFailureWithText(type, code, bean)` | 不适用 | 当前桥接未处理，不能据此宣称完整覆盖失败回调 |

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
- **成功**：熄灭小红点，版本号显示为目标版本。**失败**：清掉目标版本号，弹层显示失败原因。

### 2.4 界面怎么读

- 百分比显示：0% → 准备中；1–97% → 升级中 N%；≥98% 或阶段码 6 → 安装中，进度条改成来回走的动画。进度自己走到 98% 时，先停留 0.9 秒再切换。
- 进度弹层在升级结束前关不掉；「其他设置」里的功能行、割草机设置页的红点也读同一份状态（升级中不显示红点）。

### 2.5 兜底

- **成功判定兜底（版本号 DP）**：设备上报的版本号等于这次升级的**目标版本**（涂鸦检测升级返回的新版本号，不是设备当前版本号），就按升级完成处理，进度弹层换成「升级完成」。花盆看 DP148，割草机看 DP112。
  - **只在「固件安装中」这一段判断**：仍在升级中，且进度 ≥98% 或涂鸦报了阶段码 6。准备中、下载中（<98%）、已失败、已成功都不判断。
  - 和涂鸦成功回调**并存**：任何一方先满足就跳到成功页，后到的一方不再改变结论。
  - 条件：这条上报里真的带了版本号 DP（`changedDps`），并且 App 里发起过这次升级（`_pendingOtaVersion` 有值）；比较时忽略版本号前面的 `V`。
  - 实现：`FlowerpotState._confirmOtaByReportedVersion`，在 `_applyDeviceUpdate` 里调用。
- **花盆 DP168 `ota_result`**：进行中的升级收到本条报文中的 2 / success 时判成功，3 / failed 时判失败；0 / 1 只记录。不要求安装阶段，不适用于割草机。实现为 `_confirmOtaByResultDp`。
- **卡住**：`otaStallTimeout` 是最后一次 OTA 事件后 10 分钟的停滞判定阈值，重新打开入口或提醒流程时允许清理、重新检查；没有设置“必须等 10 分钟”的成功延迟，也没有弹层内自动失败计时器。
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
| 设备侧升级状态上报 | DP168 `ota_result`（仅本条实时上报可收尾） | DP116 `ota_status`（当前只提示，不收尾） |
| 进设置页静默查新版本 | 设置页、「其他设置」页各查一次 | 只靠提醒弹窗的检查（割草机各页都算设备页） |

## 5. 现状缺口

- **发现新版本慢 1～2 分钟**：云端 OTA 记录本身有滞后，加上 App 自己 1 分钟的节流。
- **设备重新上线、版本号 DP（花盆 148 / 割草机 112）变化，都不会触发重查新版本**。要缩短上面的延迟，App 侧可以从这里补。
- **App 重启后进度丢失**：状态只在内存里。重启时如果设备还在升级，云端返回的是 `upgradeStatus = 2`（升级中），App 只认 1，会当作「没有新版本」，界面也看不到正在升级。
- **Android 失败回调缺口**：实际 7.5.1 `IOtaListener` 有 `onTimeout` 和 `onFailureWithText`，当前 `otaListenerProxy` 均落入默认分支。设备已超时或失败时可能仍显示升级中；是否发生在本次 4–5 分钟现象中须用真机时间线证明。
- **版本上报时序**：新 DP112 若在 App 仍处下载阶段时到达，版本兜底不接受；后来进入安装阶段不会重验这条上报。维持产品现有阶段限制，需先观测再调整，避免缓存或错误组件的版本误判。
- **割草机 DP116**：`MowerDevice._readSnapshot` 对实时 7 / 20 仅发提示流，没有把共享 OTA 状态置为失败。
- iOS 不转发阶段码，只有百分比和成败。
- 涂鸦 App SDK 有没有「新版本可用」的推送接口，还没解包核对。
- 固件方清单里的「订阅 DP112」：对**割草机**成立——DP112 `fw_version` 是它上报的当前版本，设备重新连上云端时会报一次，App 目前只拿它显示版本，还没用它触发重查新版本（即上面第二条）。花盆的 112 是空气温度，花盆对应的是 DP148。

## 6. 差分 OTA 与升级耗时排查

### 6.1 手机 App 与设备固件的职责

Android 当前使用 Home SDK 7.5.1，Expansion SDK 7.8.0；实际 OTA 经 `newOTAInstance → getOtaInfo → setOtaListener → startOta`，由 SDK 负责发起和监听。App 没有自写升级包下载、Flash 擦写或传输分片逻辑，`onProgress(type, progress)` 取最后一个数字作为进度，符合当前 AAR 签名。

`tuya_iot_dev_upgd_progress_rept`、`tuya_iot_upgrade_gw_notify`、`FW_UG_S.diff_ota`、`download_buf_size` 属于设备 TuyaOS/联网模块固件接口，不是 Android Home SDK 的配置。本仓库没有割草机固件源码；在 App 源码中找不到它们，不能证明设备未启用差分或未上报进度。

设备侧 `notify=TRUE` 表示 SDK 自动上报进度，`FALSE` 表示应用层负责上报。“应用层”在这些文档里指设备上的应用程序。不能仅为提速关闭自动上报；切换后必须由设备代码完整、可靠地上报。详见[官方 Wi-Fi SDK 指南](https://developer.tuya.com/en/docs/iot-device-dev/tuya-common-wifi-sdk?id=K9glcmvw4u9ml)。

差分升级要求固件具备能力、平台生成适用于起始和目标版本的差分包，并在部署中启用差分。`fw->diff_ota` 是升级信息中的标识，不能在手机端赋值 TRUE 就把全量包变成差分包。未找到“智能生活对所有设备默认差分，SDK App 默认全量”的通用依据，见[官方差分升级流程](https://developer.tuya.com/en/docs/iot/firmware-upgrade-operation-guide?id=K93ixsft1w3to)。

### 6.2 60 秒与现有等待逻辑

[官方网关联网 SDK 文档](https://developer.tuya.com/en/docs/iot-device-dev/tuya-gateway-link-sdk-development-manual?id=K9ducoah42rl2)的子设备升级章节描述了 App 收到进度会重置 60 秒计时器；[机器人设备 OTA 文档](https://developer.tuya.com/en/docs/iot-device-dev/robot_ota_upgrade?id=Kd93o3vid2fkk)也提到默认超时及平台配置。这些是特定方案的行为说明，不能代替本割草机的模组、SDK 与 PID 配置核实，也不能证明存在自动重试。

本 App 源码没有 OTA 超时后自动重新 `startOta` 的循环。10 分钟停滞阈值与 98% 处 900ms 的显示停留不会强制让升级持续 4–5 分钟。安全完成判定、失败回调漏接与真实下载/烧录耗时必须分开核查。

### 6.3 比较两款 App 的最小实测

测试应对齐同一设备、起始/目标版本、固件组件、平台部署、包类型/大小及网络条件。重复对比需要有受控恢复起始版本的测试方式，不能拿连续两次不同升级任务直接作速度结论。

| 时间点 | 需记录的证据 |
| --- | --- |
| 点击/发起 | App 构建、Home SDK 版本、起始和目标版本；发起次数 |
| SDK 接受启动 | `startOta` 返回、错误回调、组件类型 |
| 首次及后续进度 | 时间戳、`onProgress` 原始参数、`onStatusChanged` 原始参数 |
| 下载/安装 | 设备日志中的包大小/差分标识、下载完成、校验和擦写耗时 |
| 重启/重新连云 | SDK 在线变化、本条 DP112 内容/时间、DP116 错误值 |
| 完成/失败 | SDK 成败/超时回调、Dart OTA 事件与界面终态时间 |

优先补齐 Android 终态回调并记录时间线；若设备约 1 分钟已安装并上报目标版本，而弹层到 4–5 分钟才收尾，排查 App 桥接和 DP112 时序。若设备本身下载较慢，核对平台实际下发全量/差分包、模组传输路径及两款 App 的 SDK；若下载相同而安装慢，由固件团队核对校验/Flash/重启连云。升级 SDK 或增大设备下载缓存都应有兼容性和实测依据。

2026-10-12 检查时没有 adb 真机连接，尚未取得上述时间线；不能认定 4–5 分钟根因，也不能宣称已经提速。本轮仅更新文档。检查与回归边界见[本轮记录](history/2026-10/2026-10-12-mower-ota-audit.md)。

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
   - `failed`：`_pendingOtaVersion.remove(id)`；
   - 最后 `notifyListeners()`。

### A7. 界面（`ota_progress_dialog.dart`）

- `showOtaProgressDialog`：`showDialog` 贴底、满宽，`PopScope(canPop: !running)`，升级结束前关不掉；
- `_OtaProgressDialog` 读 `state.otaProgressFor(id)`，由 `OtaProgress.displayStage` 决定显示哪个阶段，文案由 `otaRunningLabel` 生成：0% 准备中 / 1–97% 升级中 N% / ≥98% 或阶段码 6 安装中；
- `_holding`：进度走到 98% 时先停留 0.9 秒（`_holdAt98`），再切到安装中。

### A8. 兜底

- 版本号 DP 兜底：`_listenForDeviceUpdates` → `_applyDeviceUpdate(update)` → `_confirmOtaByReportedVersion(device, changedDps)`：
  1. 取版本号 DP 号：割草机 `MowerDp.fwVersion`（112），花盆 `TuyaConfig.dp['firmware_version']`（148）；这条上报的 `changedDps` 里没有它就直接返回；
  2. 当前进度必须是 `running` 且 `displayStage == OtaStage.installing`（≥98% 或阶段 6），否则返回；
  3. 目标版本取 `_pendingOtaVersion[id]`，没有（App 里没发起过升级）就返回；
  4. `device.firmwareVersion` 与目标版本比较（去掉前面的 `V`），相等就 `_applyOtaProgress(OtaProgress(success))`。之后的处理和涂鸦成功回调完全一样（A6 第 3 步）。
- `otaStalled(id)`：状态还是 `running`，但超过 10 分钟（`otaStallTimeout`）没有任何事件，就判定为卡住；再点入口时走 A1 的第 1 步；
- 割草机另有 DP116：`MowerDevice` 处理上报时，看到 `changed` 里有 116，`"7"` 或 `"20"` 就经 `_failures` 发给 `MowerHomePage`，弹提示。
