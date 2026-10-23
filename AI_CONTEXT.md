# AI 项目上下文

OTA分段诊断：调试构建新增 `[ota-timing]` 首次里程碑与累计/间隔时间；不改变SDK传输、重试及等待。用户包关闭调试不采集。实际差分和提速仍待设备及平台联合取证，取证步骤与边界见 [OTA实现说明](docs/OTA_实现说明.md)。


当前用户版构建与兼容规则见 [docs/USER_RELEASE_BUILD.md](docs/USER_RELEASE_BUILD.md)：APP_DEBUG_TOOLS=false 统一关闭调试功能，省略保持现有联调；当前真实涂鸦仓库默认启用，旧 TUYA_ENABLED 参数不再控制模式。

> **产品口径与硬性要求看 [`docs/PRODUCT_RULES.md`](docs/PRODUCT_RULES.md)**（必须怎样 / 绝对不要怎样）。本文件只放**技术事实**，试错过程在 `docs/history/`。三者不重复。

> 文档类型：当前项目上下文
> 状态：Active
> 最后核验：2026-10-23（OTA 接回窗口改 120 分钟、前台每台最多 10 秒问一次 SDK，产品口径）；2026-10-23（OTA 中断后接回：关 App 重开、息屏、断网恢复；iOS 识别升级中任务；未运行测试、未编译 iOS）；2026-10-23（花盆历史曲线：负温纵轴、未采集断线灰显、日视图按时刻标刻度、过去日帧须满96点、月曲线不截96，未运行测试）；2026-10-22（割草机倒计时与抬起/陷坑提醒、协议V3.0与拒绝码V1.0对接，未运行测试；此前 2026-10-21：OTA报错后核验扩展与SDK版本现读、SDK值去缓存；读取数据去缓存/去延时第二轮含后端数据；未真机、本机未运行测试）
> 适用范围：`flowerpot` 当前工作树
> 事实来源：源码与 CodeGraph、`pubspec.yaml`、平台配置和 `docs/` 中的当前文档

Android OTA 当前优先 Service API，回调与每3秒SDK状态查询共用映射，支持接回已有任务。已有升级进度（升级中/安装中）后SDK失败/超时先保留目标核验，显示「正在确认升级结果」；成功证据为SDK成功、本次DP148/112，或现读SDK当前设备模型的版本DP/verSw等于目标（发起前已等于目标的来源不算）；准备阶段零进度失败及明确拒绝码仍失败；2分钟无确认仅提示结果未知、可关闭，晚到目标版本仍可成功。明确DP116/预检失败保持失败；核验期间不弹新升级提醒，离线可重开进度，不取消设备升级或自动重试。普通准备2分钟/其它阶段10分钟停滞保护保留。**中断后接回（2026-10-23）**：两端 `checkFirmware` 都识别 SDK 升级中（2/5）为 `inProgress`（iOS 此前只认 1，升级中被当成「已是最新」）；`FlowerpotState.checkFirmware`（设备页提醒、「其他设置」静默检查、升级入口共用）查到即 `_reattachOta` 只挂监听不重新下发；回前台立即、前台在线轮询每台最多10秒一次，对 SDK 非明确失败120分钟内 / 核验中 / 停滞（iOS 回前台另含所有进行中）重新问 SDK，仍在升级就接回、同目标保留百分比，SDK 已无任务则转核验现读版本。当前契约见 [OTA 实现说明](docs/OTA_实现说明.md)，真实升级耗时仍需设备时间线核验。

自定义纪念日使用文字/图片圆形单选按钮。2026-10-21改为按进入编辑页的接口contentType/content回填，切到另一类型为空；切换丢弃未保存内容，切回原类型恢复接口值。单组保存、DP154及固定日期不变，当前规则见PRODUCT_RULES.md §4.24。

读取数据去缓存/去延时（2026-10-21，PRODUCT_RULES §4.26）：升级入口每次现问固件，设备页提醒按进页/重新上线/版本变化重查（无1分钟缓存）；设备清单查询期间的推送逐个DP/在线值叠到新清单，不整台退回旧快照；前台在线轮询3秒；设备型号每次进页现问。同日第二轮扩到后端数据：消息推送立即重拉+2秒补拉；OTA弹层去掉98%停0.9秒；植物资料每次进首页/换报116现拉，换报未知116不显示上一株；纪念日接后端时只显示本次拉取结果，失败显示重试；基础数据每次现拉。写入回显保护按用户确认保留。简明说明见 [docs/reports/2026-10-21-读取数据不缓存不延时.md](docs/reports/2026-10-21-读取数据不缓存不延时.md)。

割草机协议V3.0（2026-10-22）：DP号不变，新增DP120 alarm_event（事件码，只记日志），DP117/DP119日志标识符改为charging/operating_time，DP110默认计划注释改为08:30–12:00+14:00–18:00。首页状态胶囊只显示DP5本身（9在桩等待充电、10在桩等待雨停、2为关机），本机日志不再由DP5推断「作业结束」「已回到充电桩」，低电量不预告回充；DP117未充电仍不显示。拒绝文案逐码照拒绝理由V1.0，35有雨、54电量<70%已进入充电等待、49其余在桩等待各自独立，3内部失败提示重试，255带码。在桩等待充电/雨停（DP5=9/10或DP3=6/7）时停止/继续置灰。旧文档已移入docs/history/other/（同名），导航docs/README.md已重建；倒计时、雨滴回充、陷坑脱困、抬起/落地提醒的检查与定稿见docs/reports/2026-10-22-割草机倒计时与雨滴陷坑抬起检查.md。同日已实施：DP119下发成功即由`MowerWorkCountdown`按「此刻+小时数」在本机记终点（按设备ID存SharedPreferences），状态胶囊显示计时图标+剩余分钟（向上取整），不暂停不隐藏、到0停「0分」、重设重跑、继续不重计，本机无终点不显示；`MowerLiveNotice`给黄条实时提醒——DP111 circularize 0x1000或DP120 44/144→设备已抬起/已落地（3秒收起，双来源去重），41/141→正在脱困（31或DP18陷坑位收起，2分钟超时），只认实时上报、快照只同步是否抬着；黄条优先级已关机>DP18故障>实时提醒。回桩途中区分雨滴/正常待SDK与固件确认，未实施。记录见 [docs/history/2026-10/2026-10-22-mower-countdown-lift-trap-notice.md](docs/history/2026-10/2026-10-22-mower-countdown-lift-trap-notice.md)。记录见 [docs/history/2026-10/2026-10-22-mower-dp-v3-reject-codes.md](docs/history/2026-10/2026-10-22-mower-dp-v3-reject-codes.md)。

割草机原始DP读取通过双端deviceSnapshot通道读取SDK当前设备模型，不再拿APP旧清单回填；实际报告直接更新，逐DP拒绝迟到快照覆盖，清单刷新也驱动原页更新。电量未返回显示占位，不显示默认0%。SDK未上报的物理值不能由APP强制变新；当前约束见PRODUCT_RULES.md §4.25。OTA新版Service及防重复逻辑已具备，工单建议的适用性和进一步取证方案见OTA实现说明的2026-10-21章节。

## 1. 项目定位

`flowerpot` 是 YSplanter 智能花盆的 Flutter iOS/Android 客户端（2026-10-23 起应用名与页面文案中的品牌为「东方金穗」，YSplanter 字标图片未换，见 `docs/history/other/PRODUCT_RULES.md` §4.27），覆盖账号、设备配网、设备与植物状态、报表、设备设置、固件升级、动画资源和个人中心。PC 管理后台与服务端是独立项目，不应把管理端页面或部署规则写进本仓库。

项目可在没有涂鸦密钥和安全组件时以 Mock/静态预览方式运行；真实设备能力通过原生 Smart Life App SDK 与 Flutter `MethodChannel` 桥接。

Git 是办公室电脑、家庭电脑和远程 SSH 环境之间唯一共享的事实来源。本机 SDK、构建缓存、签名材料、`.codegraph/` 和未提交工作区不属于跨机器共享状态。

## 2. 技术栈与常用命令

- Flutter / Dart，Dart SDK 约束为 `^3.11.5`。
- Material 3、feature-first 页面组织、命名路由。
- `ChangeNotifier` 的 `FlowerpotState` 管理应用状态，`FlowerpotScope` 通过 `InheritedNotifier` 向页面提供状态。
- `http` 提供 REST 客户端，`crypto` 负责后端密码接口要求的 MD5，`shared_preferences` 保存会话和本地偏好，`image_picker` 选择图片，`image`（2026-09-16 新增，纯 Dart）只用它的 JPEG 编码器——上传前压缩那一步的解码和缩放走 `dart:ui`，`dart:ui` 只能编 PNG、也给不了 4:2:0（设备要 Baseline + 4:2:0，`encodeJpg` 的 `chroma` 默认是 `yuv444`，必须显式传 `yuv420`）。
- Android Kotlin、iOS Swift 负责涂鸦 SDK 原生桥接。

```bash
flutter pub get
dart format lib test
dart analyze lib test
flutter test
flutter run
```

真实 SDK 模式按平台配置完成后使用：

```bash
flutter run --dart-define=TUYA_ENABLED=true
```

`TUYA_ENABLED=true` 会选择真实 Repository。真实设备流程仍必须准备好平台密钥、安全组件和签名。REST 源站由 `--dart-define=API_BASE_URL=https://...` 注入，**默认值就是正式源站 `https://api.yikaltd.com`**；`ApiConfig.validateBaseUrl` 只接受 HTTPS 源站（带路径、查询、用户信息或非 https 一律构建期抛错），2026-09-09 起不再有明文回落。**体验模式与涂鸦 SDK 联调台已整体移除**（`lib/src/core/config/`、`lib/src/features/preview/`、`devtools/` 与 `AppRoutes.tuyaDebug` 一并删除），Mock 仓库搬到 `test/support/mock_tuya_repository.dart`，产品包里只有真实数据通路。各环境应使用 PATH 中的 Flutter/Dart；README 中的绝对路径只可视为单机示例。

## 3. 架构与数据流

```text
lib/main.dart
  → FlowerpotApp
  → FlowerpotState.initialize()
  → FlowerpotScope / AnimatedBuilder
  → AppRoutes.onGenerateRoute()
  → features/*/presentation
```

设备与账号链：

```text
页面
  → FlowerpotScope.of(context)
  → FlowerpotState
      ├─ AppBackendRepository（显式地址或当前临时回落；none 禁用）
      │   → ApiClient / ApiSession
      │   → 国内短信、登录/注册、用户设备、植物、设备图片
      └─ TuyaRepository
          ├─ TUYA_ENABLED=false：MockTuyaRepository
          └─ TUYA_ENABLED=true：MethodChannelTuyaRepository
                                  → Android/iOS Smart Life SDK
```

国内账号在 APP 后端登录/注册成功后，由后端返回 `userNo` 与 `tuYaPwd`，`FlowerpotState` 再用这组映射凭据建立涂鸦会话；任一步失败都会清理 APP Token，避免半登录状态。手机验证码登录是登录注册一体的：`userLoginVerifyCode` 以 `retCode` 403 + 「不存在/未注册」文案回绝时，`HttpAppBackendRepository` 用同一条验证码调 `userRegisterMobile` 补注册（密码随机生成占位），注册接口返回的会话字段与登录接口一致，因此不再登录第二次。海外邮箱和未配置 `API_BASE_URL` 的开发模式保留原涂鸦账号链。

设备主动上报是反方向的一条单向链，不经过方法通道：

```text
Android IDevListener / iOS ThingSmartDeviceDelegate
  → EventChannel com.common.yikaltd/tuya_events
  → MethodChannelTuyaRepository（并入最近一次设备快照）
  → TuyaRepository.deviceUpdates
  → FlowerpotState → notifyListeners()
```

`ActionResult` 同时带回 `message` 与 `code`：页面展示 `message`，`code` 用来区分平台配置错误（`sdk_unavailable`、`credentials_missing`、`security_component_mismatch`）与账号错误，也是日志和排查时的抓手。

REST 公共能力位于 `lib/src/core/network/`，业务契约位于 `lib/src/core/backend/`：`ApiClient` 从 `API_BASE_URL` 读取服务地址，`ApiSession` 用 `SharedPreferences` 持久化 `userToken` 并统一处理鉴权失效，`HttpAppBackendRepository` 封装账号、用户设备、植物与图片接口。业务页面不直接发 HTTP 请求，由 `FlowerpotState` 编排 APP 后端与涂鸦设备会话。

## 4. 关键目录

| 路径 | 职责 |
| --- | --- |
| `lib/main.dart` | Flutter 入口与系统 UI 初始化。 |
| `lib/src/app/` | 根应用、主题和 `FlowerpotScope`。 |
| `lib/src/state.dart` | 当前集中式应用状态与业务编排。 |
| `lib/src/routes/` | 命名路由、鉴权分流和页面参数。 |
| `lib/src/features/` | auth、home、devices、profile 等业务页面；调试台与体验模式目录已删除。 |
| `lib/src/core/config/debug_log_gate.dart` | 联调日志总闸（2026-09-19 关闭，**2026-09-23 割草机联调重新打开**，生产默认 `true`）。关着时 `_logInteraction` 不记录、浮层也不挂；翻回 `true` 整套回来。⚠️ 割草机的 DP 下发/上报走的就是这个日志框，联调割草机要先翻开它；用例里由 `flutter_test_config` 统一开着。 |
| `lib/src/features/mower/` | 割草机（产品 ID `mz7g3yzaufvoh4ls` = `MowerDp.productId`）。页面：首页 / 割草计划 / 设置三个一级页 + 设备参数、区域设置、雨淋设置、时间同步、语言切换、消息通知。`mower_dp.dart` 是 DP 表与 DP101/DP103 的编解码（2026-09-21 补了 DP103 解码、DP107 `UTCA/UTCB` 解析、`MowerDp.enumOf`），`mower_device.dart` 是当前 DP 值与**唯一下发出口**。**2026-09-21 接真机**：① 配网走花盆同一条 BLE 双模动线，搜索页 `_isOurProduct` 认花盆两个 ID + `MowerDp.productId` + 后台 `getBasicData.deviceIdList`（开扫时顺手拉）；② 设备列表按 `state.isMowerDevice`（设备 `productId == MowerDp.productId`）分流，点进 `AppRoutes.mowerHome` 并带 `MowerHomeArguments(deviceId)`；③ `MowerHomePage` 进来 `MowerDevice.instance.bind(state, deviceId:)`、退出 `release`——真机时下发走 `FlowerpotState.publishMowerDps`（同花盆的离线门禁，不占忙锁，`MowerDevice` 内部排队保证顺序；raw 发十六进制串），上报经 `FlowerpotState.mowerReports` + `mowerDps`（仓库 `rawDps`，按 DP 号取原始值，不走花盆解析），下发后 `MowerDevice.echoTimeout`（5 秒）没回显就按设备快照回弹（V2.2 §1），失败经 `MowerDevice.failures` 由外壳弹提示；④ 割草机的上报在 `_listenForDeviceUpdates` / `_applyDeviceUpdate` 里**跳过花盆处理**（植物、引导窗、历史曲线）。**2026-09-23 去掉全部假数据**：静态演示模式整个删掉（`MowerDemo` 入口、`MowerDemoDevice`、稿子上的计划 / 消息、长按电量环的模拟面板、`MowerDevice.defaultSchedule`），`MowerHomePage.deviceId` 必填；`mower_demo.dart` 改名 `mower_ui.dart`，只剩界面常量（`MowerPowerState` / `MowerPlanAxis` / `MowerColors` / `MowerAssets`）。标题 / 设备参数名称读 `state.deviceById(id).name`，型号 / SN 空着；消息通知三栏均从当前设备的涂鸦MSG_REPORT历史按等级分档，日期默认全部；「恢复默认」发 DP110 `schedule_reset=true`（协议 **V2.3** 新增，动作型自复位，结果看设备上报的 DP101）；改名走 `state.renameDevice`（涂鸦 + 后端 `editUserProduct`，与花盆共用 `RenameDeviceDialog`）；计划页底部有 DP101 逐字节解析临时窗口（`MowerScheduleCodec.describe`，联调完删）；左三只在 DP5=paused 时禁用。**2026-09-28 接 DP113 `shutdown_report`**（V2.5 关机上报）：「已关机」只在状态层判一次（`FlowerpotState.isMowerShutdown`，DP113 上报置位 / 清除、在线态变化时对账、拉清单时按快照预置），控制页使用该状态，设备列表胶囊只读涂鸦 online，`MowerDevice.shutdown` 只转发；关机期间左三和开关都禁用、离线不降级蓝牙。**当前协议文档是 `docs/Grass_Master_Automower_DP协议对接_V3.0.md` 与 `docs/Grass_Master_Automower_拒绝理由与文案_V1.0.md`**（2026-10-22 起；V2.6 及更早版本已移入 `docs/history/other/`）。割草机消息通知当前恢复为 `DeviceMessagesView`：按当前账号/设备分页读取涂鸦MSG_REPORT，按显示标题设备通知/设备异常/其它分别进入日志/告警/提醒，等级字段不覆盖，收到推送立即刷新、2秒后再补拉一次（2026-10-21）。三栏复用品牌分段控件，独立日期筛选；云端调试、当前等级和底部导航不显示。本机 `MowerMachineLog` 仍独立采集5/111/117/118/113/13及可选115并保存200条，但不再充当该页面历史数据源；DP18保留控制黄条。完整口径见 `docs/MOWER_MACHINE_LOGS.md`；花盆页是 `DeviceMessagesPage`（路由 `AppRoutes.deviceMessages`，设置页「消息通知」进）。**2026-10-08 计划页**：星期下面那排勾改成修边（翻 DP101 沿边位），色块不再画修边描边；DP101 编码时停用的时段写起止、有效位 0，解码把「有效位 0 + 起止合法」解成 `enabled: false` 的时段（图表 / 合计 / 今日计划都不算，编辑框里可原样再启用），见 §4.18。**2026-10-09 长按删除**：复用公共确认框，提示「计划时间是否要删除？」，确认后才清空目标时段并整周下发 DP101；取消 / 返回 / 遮罩关闭不改变计划，见 §4.19。**2026-10-09 首页 UI**：四颗控制按钮共用 40×40 图标槽位，控制按钮转圈显式固定 24×24、居中且 padding=0；Wi-Fi 通道断开时恢复原图 30% 透明度淡显，在线显示完整原图，不附加灰色滤镜（2026-10-12 产品口径）。Android Wi-Fi 读 MQTT / LAN / Cloud 任一在线，与蓝牙独立；iOS 尚无 deviceLinkState 桥接，通道状态缺口见 MOWER_DP_GAP_REPORT.md 的 M01。四颗按钮 loading 保持公共槽位。**2026-10-10 启动流程**：自动/定点/继续每次安全确认→按当天18点前完整小时选择→DP119成功后启动；回归/停止跳过。按钮蓝牙预检及开关已移除，通信通道与后台重连保留。18点后或不足1小时给出提示且不启动。DP115接入当前DP2/DP3回执：安全与时间窗结束后，code≥16弹设备异常，已定义16–70用协议建议，255为“操作未生效”；26等新鲜DP111按优先级指出残留故障；旧快照、重复和错配回执不弹。见 `docs/PRODUCT_RULES.md` §4.10。 |
| 消息中心（涂鸦） | 取设备消息**只能按设备取**：安卓 `IThingMessage#getMessageListByMsgSrcId(offset, limit, MessageType, msgSrcId, cb)`（桥接 `deviceMessages` → `TuyaRepository.deviceMessages(deviceId:…)`）。⚠️ **别用 `getMessageList`**：它是聚合口径，按它分页拿不到某台设备的全量消息（2026-09-18 那版就是这么打出一堆看着不对的东西）。⚠️ **iOS 是另一个方法**：`ThingSmartMessage` 的 `fetchEncryptMessageDetailListWithListRequestModel:success:failure:`，iOS 桥接**尚未接**。`MessageType` 只有三个常量，就是消息中心的三档：**`MSG_REPORT`=1（告警，设备消息推送落这一档，默认取它）**、`MSG_FAMILY`=2、`MSG_NOTIFY`=3（传 `ALL` 则三档依次各取一次，结果里 `perType` 写明每档几条；三档都空时自动探 `getMessageMaxTime` / `requestMessageNew` 判断是设备没有还是消息中心本来就空）；`MessageBean` 有 `msgType`（含常量 `MSG_TYPE_PRD_WARN`）、`msgTypeContent`、`msgCode`、`alarmType`、`extendParams`——**后台配的「推送等级」落在哪个字段还没确认，要真机拉一次**。签名与字段表见 `docs/TUYA_CAPABILITY_AUDIT.md` 第五节（解包核对，非文档口径；含真机第一次跑出来的结果）。`requestMessageNew` 回的 `MessageHasNew` 就三个 boolean（`alarm`/`family`/`notification`），`getMessageMaxTime` 的时间**单位是秒**。⚠️ 2026-09-21 结案：一路查到**告警档整个账号 0 条**是对的——后台监控列表那几条是**别人账号的设备**（`6c26…cadl`）触发的，设备消息只投给触发设备的主人/被分享者；App 查法没问题。「推送等级」落在哪个字段仍待本账号设备真触发一次再看；`getMessageListByMsgSrcId` **只对告警档有意义**，家庭/通知用它会报 `101001 JSON PARSE EXCEPTION`（通知档本来就没有 `msgSrcId`），那两档要用 `getMessageListByMsgType`；**按设备/按类型这两条都没有时间参数**（带时间的只有聚合的 `getMessageList(offset, limit, long start, long end, cb)`，**时间单位是秒**（真机实测），桥接 `messagesByTime` 只当诊断用）；`msgTypeContent` 会随接口变（同一条登录提醒按类型取叫「通知」、按时间取叫「系统提醒」），分档别靠它；设备日志 `queryDeviceOperateLogs` **已真机跑通**：参数 `(设备ID, "103,105,106", offset, limit, "开始毫秒", "结束毫秒", "false")`，**dpIds 必填**，回 `{"dpc":[],"dps":[{dpId,timeStamp(秒),timeStr,value}],"hasNext","total"}`（传 "false" 时按时间升序），查**不属于本账号**的设备回 `PERMISSION_DENIED 没权限`；分档文案用 `msgTypeContent`、细分用 **`msgCode`**（`ADD_DEVICE_FOR_LOCATION_MSG_V2` / `LOGIN_MSG_CENTER` 这种，比 `msgType` 有用，家庭档的 `msgType` 是 `-1`）。另：**「日志」不在消息中心、也不在 `IThingDevice` 上**——安卓是 `ThingHomeSdk.getRequestInstance().queryDeviceOperateLogs(String, String, int, int, String, String, String, cb)`（回调泛型 `String`，原样一段 JSON；桥接 `deviceOperateLogs`），iOS 是 `ThingSmartDevice#queryDeviceOperateLogWithDpIds:offset:limit:startTime:endTime:isASC:`，**七参顺序官方没给、按真机报文校准**，而且只覆盖「DP 上报」这一类；上线/下线/激活/重置/指令下发/固件升级/信号量/重启/定时这些类型只有**云端 API** `GET /v1.0/devices/{id}/logs?type=1..10` 有，要后端签名代理。`IThingDevice#getDataPointStat` 是 DP 统计，不是日志。**实时推送**（2026-09-23）：`ThingHomeSdk.getPushInstance()` 的 `registerPushAlarmListener`（MQTT 802，`{type, msg}`）/ `registerMQPushListener`（MQTT 52，`{type, link, timeStamp}`），桥接 `startPushListen` + 事件 `pushMessage`，SDK 无注销方法、进程内只注册一次，只在前台收得到；见能力核对 5.5。 |
| `lib/src/design_system/` | Design Token、资源索引和公共视觉组件。 |
| `lib/src/shared/` | 跨 Feature 复用组件；`media/upload_image.dart` 是上传前的图片压缩（2026-09-17 随固件 1.0.12 改成设备口径：JPG Baseline + 4:2:0、≤ 320 × 240 的框、≤ 500 KB，小图不放大；做不出合格的图返回 null，两处调用中止上传）。 |
| `lib/src/core/network/` | REST 请求、会话、异常和重试。 |
| `lib/src/core/backend/` | APP 后端账号、用户设备、植物、设备图片模型与接口封装。 |
| `lib/src/tuya/` | 涂鸦 DP 表与配置、模型、raw 历史解码、Mock 与 MethodChannel Repository。 |
| `android/`、`ios/` | 平台工程、SDK 配置和桥接实现。 |
| `test/` | 网络、配置、页面和公共组件测试。 |
| `docs/` | 架构、UI、平台接入和冻结历史记录。 |

## 5. 当前核心模块

- 账号：配置 `API_BASE_URL` 后，国内手机号短信、验证码/密码登录与注册走 APP 后端，再用返回的映射凭据登录涂鸦；验证码登录未注册即自动建号；海外邮箱及找回密码等原有能力保留涂鸦链路。
- 设备实时性：DP 上报、上下线和解绑由原生监听推给 Dart，页面自动刷新；在线字段完全依赖 SDK，取消本地信号探测超时覆盖与 Android 网络状态混用，iOS 补齐 online delegate/缓存查询；查询快照与 DP 合并缓存同步，迟到查询不盖新 SDK 事件。当前契约见 `docs/DEVICE_ONLINE_STATUS.md`；温标（146）与时间格式（147）下发后 App 自身展示跟随。
- 状态文案：需水（107）、光照（108）、空气温度（113）、空气湿度（115）四条枚举的文案集中在 `lib/src/tuya/tuya_status_copy.dart`，状态页顶部与首页状态卡片同源，设备没上报时按同一套阈值兜底（113 的兜底舒适区间 18–28℃ 也放在这里，温度状态页与首页共用）。2026-09-08 起每条状态都备了中英两份，取用走 `waterNeedsCopy` 这类按 `FlowerpotState.languageCode` 查表的方法，非英文一律回落简体中文；**2026-09-16 产品把这 12 条全部重写**（植物第一人称，说明一句、建议一句，中英同步换），改的是措辞不是判据，枚举到档位的对应和兜底阈值都没动——唯一要注意的是 108 的 `very_good` 从「晒太阳中」改口成「太晒了」，所以代码里不要按档位写死哪一档算警告；首页「今日养护」卡片改为轮播这四条状态的建议（8 秒一条、900ms 上下滚动切换，2026-09-14 起不再淡入淡出，`HomeCareBanner`），文案与卡片、状态页同源。**注意：App 至今没有引入 `flutter_localizations`/arb，其余界面文案仍是硬编码中文**，这张表只覆盖这批状态文案。
- 2026-10-16：割草计划复制整周只复制两个时段，修边按天独立，目标日保留最新DP101沿边值；自定义纪念日切换文字/图片保留草稿，保存只提交所选`contentType + content`覆盖旧值。当前口径见`docs/PRODUCT_RULES.md` §4.22/4.24。
- 2026-10-16：割草机面板不按离线锁住或淡显，允许导航与本地编辑；提交时统一提示框「设备已离线」，留在当前页面，发送和OTA底层条件维持。DP117=not_charging不显示状态词，保留电量与告警。见`docs/PRODUCT_RULES.md` §4.13/4.21。
- 多语言：`lib/src/shared/l10n/` 是界面文案框架——`AppLanguage` 枚举（现有 zh / en，加语种就加枚举值，缺译文按 `fallbacks` 回落到简中）、`AppLocalizationsScope`（挂在 `MaterialApp.builder`，切语言整树重译）、`AppL10n` 文案目录（`t({语言: 文案})`）。设置页的语言列表由枚举生成。**只有 2026-09-08 改动涉及的页面接入了目录，其余页面仍是硬编码中文**；`flutter_localizations` 尚未引入，Material 内建文案恒为英文。做法对齐相册 APP，区别是文案用 Map 而不是位置参数。
- 首页与设备：无底部菜单，设备列表即首页、左上角头像进入「我的」（顶栏正中显示当前设备名称，未绑定设备时是品牌标识）、配网（搜索 → 选择 → Wi-Fi → 成功）、选择植物、状态详情、报表和设备信息。设备详情页入口只剩离线一道门禁（「请打开设备并保持在线」）。**2026-09-09 植物 DP 契约改版**：DP 116 变成植物 id（`-1` = 盆里没有植物，`0..N` = 管理后台的「涂鸦标识 ID」，0 是通用植物），DP 162 变成两态且只上报（0 不弹窗 / 1 弹引导窗，App 不再写它——下发 116 后固件自己改回 0 并立即上报，116 = -1 或关掉自动检测时同样报 0）。进详情页先补植物资料再看 162：报 1 弹「发现新植物」引导窗：**id = 1..N** 时正文按 116 从后端目录取名字、按钮「确认」（原样回写当前上报的 id）与「选择植物」（跳选择流程）；**id = 0（通用植物，后台不建数据）** 时正文换成「已检测到通用植物，请选择并确认植物。」且只留「选择植物」一个按钮。返回键关掉则不发、下次再弹。116 = -1 时首页画不带植物的设备图、「今日养护」整行换成惊叹号 + 「未检测到植物，请将植物种入花盆。」、设备设置页的「植物」入口点了只提示同一句。标识匹配用 `FlowerpotState._plantKey`：能解析成整数按整数比，否则退回字符串，老固件的 `tuYaRemark` 仍可匹配。设备设置页有「自动检测植物」纯开关（DP 163，平台尚未导出）。设备清单只来自涂鸦：`getDevices` 先查家庭再取家庭详情，**家庭选择两端都已改为稳定规则**（Android 先挑带设备的家庭、再按 `homeId` 最小；iOS 按 `homeId` 升序取第一个），不再取列表返回的第一个——账号下有多个家庭时那会让同一账号不同登录看到不同设备；拉取失败不再被吞成空列表，`FlowerpotState.deviceLoadError` 会带上来源与错误码，设备列表页在「列表为空且有错误」时画错误态与「重试」，下拉刷新与错误态「重试」共用 `reloadDevices()`（该方法原名 `probeDevices`，调试台删除后只服务产品页面）；错误态与「暂无设备」空态底部都画一行 `sessionDiagnostics`（`uid · 家庭 · 设备 N 台 · 失败原因`，可长按复制），每次读列表还会打一行 `[devices] …` 日志，定位「读不到设备」看这一行即可。家庭属于涂鸦账号、由云端按 uid 返回，手机连哪个 Wi-Fi 不影响选哪个家庭；**2026-09-09 起家庭固定下来，优先级 后端 > 本地缓存 > 涂鸦列表现挑**：登录 / 注册响应里的 `tuYaHomeId`（后端待补该字段）一拿到就钉给涂鸦并写进本地；本地缓存记在 `SharedPreferences`（`tuyaHome:<uid>`），之后每次会话开始由 `_startSession` 先 `useHome`（桥接 `setHomeId`）钉给原生再拉设备列表，不再每次登录重挑。`prepareForPairing()`（确认家庭 + 取令牌）现在由**搜索页**进页面时预取，不再挂在「开始配网」上；空家庭列表在绑着设备热点时直接报 `home_offline` 不建家，正常网络下也先重查一次再建。钉住的家庭若读出 0 台设备，立刻作废缓存（`useHome('')`）并重读一次——缓存只是缓存，以涂鸦返回的为准。但 AP 配网期间手机在设备热点上没有外网，此时查家庭可能失败或拿到空列表进而自动建家，这是账号多出一个空家庭的主要来路。后端设备行按涂鸦 `deviceId` 关联；植物目录、详情、绑定/删除与设备图片使用 APP 后端。**分工要点**：涂鸦只回答「这盆里是哪一株」——设备通过 DP 116 `plant_variety` 上报后台配好的标识符（`tuYaRemark` 字符串，不是数字 ID），App 选植物时也是把标识符写回 116（分类另写 161）；植物的内容本身全部来自 APP 后端 `Client/Product/getProductPlantList` 的目录行——`plantImg`（列表与详情的图片）、别名、简介、最适温湿度、光照 / 浇水 / 温湿度建议、养护难度、`categoryType`，由 `_plantForIdentifier` / `ensurePlantProfile` 按 116 的标识符匹配；2026-10-21 起进首页、设备换报 116、弹引导窗都现拉目录（不再按已有/查不到跳过），换报目录里没有的 116 时显示「植物资料暂未获取」、不拿上一株顶替，拉取失败不打断详情页；详情页上的实时数值（需水 105/106/107、光照 108/109/110、温度 112/113、湿度 114/115，四个状态子页的完整对照见 `docs/PRODUCT_RULES.md` §4.5）来自设备 DP 上报，与这条后端链路无关。 2026-09-09 起**已绑定设备首页正中那张图也走这条链路**：`HomeDashboardModel.plantImageUrl` 取 `device.plant.imageUrl`，`HomePlantOverview` 优先画后台配的图，字段为空或图片加载失败才回落本地 `AppAssets.smartPlanterWithPlant`；植物详情页 `_PlantDetailArtwork` 早就是同一口径，回落的是 `AppAssets.plantImage(plant.id)`（未知 id 再退到通用图标）。**设备只支持涂鸦标准 AP 热点配网（AP-cfg），不支持 EZ/SmartConfig**（2026-09-10 设备开发口径）。未激活设备开机即自动开热点（`smartlife_xxx` / `tuya_mdev_xxx`，都在 `isDeviceHotspotName` 白名单内）；固件 **TuyaOS > 3.6.1（设备团队已确认）**，所以走涂鸦「热点配网新流程」。

  **铁律：配网全程不用 `WifiNetworkSpecifier`。** 它 + `requestNetwork` 在 Android 10+ **必弹**系统入网授权框，没有任何公开 API 能抑制它或代替用户点「连接」（2026-09-10 向涂鸦求证并实测确认；对方给的 `ThingSmartHotspotCredentialKit` 在官方 Maven 与其自己给的文档里都不存在，已改口「未公开发布」）。⚠️ **2026-09-10 实测推翻了「SDK 会替我们连热点」这条假设**：完整官方序列下单独调 `queryDeviceConfigState`，跑满 45 秒报 `207220`（配网任务整体超时），**全程没有弹出任何系统框**、手机始终在路由器上 ⇒ SDK 根本没去连。涂鸦 SDK 只是跑在我们进程里的库、没有额外特权；文档里「SDK 会在指定时间内自动去连接 AP 热点」那句写在**「恢复配网」**一节，讲的是中途掉线后重连**它已经连过的**热点，同一页开篇写的才是通用前提——「将手机连接到配网设备 Wi-Fi 热点后……**但用户需要手动切换手机的 Wi-Fi 设置**」。**所以①连热点必须由我们做**，用 `_joinHotspotForPairing`（`WifiNetworkSpecifier`，Android 必须给**确切 SSID**、iOS 只能给前缀）。产品口径：做不到零确认，但**自动选中**——框里只有搜索页扫到的那一台、已经选好，用户点一下「连接」，已连在该热点上时连框都不弹（见 `docs/PRODUCT_RULES.md` 1.2）。`openWifiPanel`（拉系统 Wi-Fi 面板）代码保留但**不在主流程上**。

  **配网主路径是蓝牙双模（2026-09-11 晚定稿，固件方已确认支持蓝牙配网）**，AP 热点那条完整保留作回落。改前先读 `FlowerpotState.pairViaBle` 与 `pairViaHotspot` 的文档注释。

  **双模动线**：① 搜索页进页面就开 BLE 扫描（`getBleOperator().startLeScan`，**不受 Wi-Fi 扫描配额约束**，双模设备一上电就在广播、通常一两秒出现）→ ② 扫到的设备直接进「已发现设备」列表（**扫到 BLE 就只列 BLE**，一台都没有才回落 Wi-Fi 热点那份——两条通道没有可靠的共同标识，混列就是同一台花盆出现两行）→ ③ **抢答窗口**：BLE 还在扫的头 4 秒（`_bleGrace`）**先不画 Wi-Fi 热点**——Wi-Fi 那条可能先答（本轮里系统或我们任何一次扫描看见热点，1 秒内就列出；2026-09-21 起本轮开始之前的缓存旧条目不算），不压住的话用户会抢在 BLE 答出来之前点走更差的那条路；⚠️ 这个窗口按**墙上时钟**算（`DateTime.now()`），用例的假时钟推不动它；蓝牙用不了时一秒都不压，窗口到点由 `_bleGraceTimer` 主动重画。**Wi-Fi 扫描节奏没动**，它现在是回落路径但必须随时可用 → ④ 用户点「连接」：先 await 令牌预取，停扫（一边扫一边连是在抢同一个射频），`supportWifiList` 为真就调 `IMultiModeActivator.queryDeviceConfigState(MultiModeQueryBuilder)`——builder 直接吃 BLE 扫到的 `ScanDeviceBean`，**建本地蓝牙连接**问设备要它自己扫到的 Wi-Fi 列表，**不走系统 Wi-Fi scan** ⇒ 与「2 分钟 4 次 `startScan`」无关 → ⑤ 带着列表进「连接 Wi-Fi」页（「切换」弹层列的就是这份，比手机扫到的准）→ ⑥ `pairViaBle` → `IMultiModeActivator.startActivator(MultiModeActivatorBean{ssid,pwd,token,homeId,scanDeviceBean})`，凭据经蓝牙下发。**全程没有系统入网授权框，手机也从没离开路由器。**

  ⚠️ **`ScanDeviceBean` 必须留在原生侧**（`bleScanned` 按 uuid 缓存）：双模那两个 API 吃的是对象本身，它过不了方法通道；停扫时**不清**这张表（点完设备就停扫，紧接着还要用它），**每轮开扫时整张清空**（2026-09-21，之前从来不清）。
  ⚠️ **每次 `startBleDiscovery` 都是全新一轮**（2026-09-14）：还在扫就先停、清空 Dart 侧 `_bleDevices` 再开，扫描时长跟搜索窗口（3 分钟）对齐；原生到时 / SDK 自停发 `bleScanStopped`，经 `TuyaRepository.bleScanStops` 把 `bleScanning` 置回 false（原生只替**当前**回调代理报，重开时旧一轮迟到的结束不上报）。之前这条事件没人接，`bleScanning` 永远是 true，「重新扫描」被 `if (_bleScanning) return true` 挡成空操作，扫到过的设备也一直留在列表里。搜索页进页面 / 重新扫描 / 回前台（没在扫时）/ 从上层页面退回（`AppRoutes.routeObserver` 的 `didPopNext`）都走 `_scan()` 重开；停扫带 `owner`，叠两层搜索页时上层的迟到 `dispose` 掐不掉下层刚开的这一轮。**名字未定的设备整行不画**（`productInfoPending`，云端名最多等 5 秒）。**2026-09-21 起不留任何跨轮缓存**（产品：「不要缓存，根据实际搜索的情况展示」）：`uuid → 产品名` 表每轮清（`_bleRound` 丢掉上一轮晚到的查询结果），`deviceWifiNetworks` 每轮清；**轮内过期**——被上报过 ≥ 2 次的设备连续 `FlowerpotState.bleGoneAfter`（10 秒）没再上报就移出列表（按 1 秒一拍的定时器数拍子，不读墙上时钟；只报过一次的不动，防 SDK 不重复上报时误删；扫描结束后停在结束那一刻）；Wi-Fi 热点按原生报的每条 `ageMs` 换成 `WifiNetwork.seenAt`，搜索页只列 `seenAt ≥ 本轮开始` 的（`WifiScan.deviceHotspotsSeenSince`）。
  ⚠️ **`supportWifiList` 为 false 不要调查询**：老固件（TuyaOS < 3.6.1）不认，只会干等一次超时。
  ⚠️ **两个同名的 `queryDeviceConfigState` 别搞混**：`IThingOptimizedActivator` + `ApQueryBuilder` 那个是已判死的 AP 「新流程」（指望 SDK 自己连 Wi-Fi 热点）；双模这个是 `IMultiModeActivator` + `MultiModeQueryBuilder`，走蓝牙。
  ⚠️ **`ActivatorService` / `BLEActivator` / `IDiscovery` / `ActivatorMode` / `DiscoveryMode` 在 7.5.1 里不存在**（全模块 0 命中，已解包核对）——那是设备固件侧 TuyaOS/TKL 的命名。App 侧 BLE 只有 `IBleActivator`（纯蓝牙，bean 无 ssid/pwd）与 `IMultiModeActivator`（双模，bean 带 ssid/pwd/token），花盆是后者。

  **自动优选覆盖到失败之后，不只是发现阶段**：失败页的「重新配网」会带着 `bleUuid` / `hotspotSsid` / `deviceNetworks` **照原样重走刚才那条**（不带的话走蓝牙失败的那次会掉进 AP 分支、又没有热点名，用户得到的是另一个失败）；蓝牙失败时另给一颗「改用热点方式配网」，回搜索页并带 `preferHotspot: true`，那一轮不开 BLE、直接走 AP。**不做自动回落**：要再等一轮超时，而且 AP 必然弹系统框，在用户以为结束时冒出来更糟。EZ 不进优选池（真机实测设备不支持、整条已删），所以本产品的自动优选是 BLE ⇄ AP 两选一。

  **AP 回落动线**（没有 BLE 设备时）：对照涂鸦官方 AP 四步：**① 设备置 AP 模式**（产品口径：开机就一定可配网，App 不参与）→ **② 手机连设备热点** → **③ 取 Token + 收 SSID/密码** → **④ `ApActivatorBuilder` 发起配网**。⚠️ 我们的 ③ **排在 ② 之前，而且必须相反**：取令牌要走云端，一连上设备热点手机就没有外网了。

  1. **搜索页**：`scanWifi` 找热点并展示（节奏见下文），进页面就 `prepareForPairing()` 预取「确认家庭 + 取令牌」= 官方③。**2026-09-11 起并行开一条 BLE 发现通道**（见下）。
  2. **点某一行的「连接」** = 官方②：`connectDeviceHotspot` → `_joinHotspotForPairing`（`WifiNetworkSpecifier`，Android 必须给**确切 SSID**、iOS 给前缀；已连在该热点上时原地跳过、不弹框）。产品口径：**Android 10+ 那一次系统入网授权框绕不开，就把它收在这一颗按钮上**，之后的页面一个框都没有。
  3. **「连接 Wi-Fi」页**：只管选网络 + 输密码（设备是在搜索页确认的，这里不再画「已选择设备 xxx」）。路由器名在**连热点之前**就抓好带过来（`PairingArguments.routerSsid`）——连上热点之后读到的是热点名，填它等于让设备去连它自己。
  4. **「开始配网」** = 官方④：`pairViaHotspot`（令牌复用 → 连热点（已连则跳过）→ `_pairInternal` → 原生 `startActivator`：`setSsid`/`setPassword`/`setToken`/`setActivatorModel(THING_AP)`/`setTimeOut(120L)`/`setListener` → `start()`）。⚠️ **点下按钮必须同时置 `_pairing = true` 与 `_pairingState = state`**——`aef6ccd` 把这两行删了，症状就是「填完密码点下一步卡住」：进度页不出现、「取消配网」够不到、切后台还会去放热点把正在下发凭据的通道掐断。

  **网络还原**：`releaseDeviceHotspot()`（不走 `_guard`、不抛错、可重复调）是「把手机 Wi-Fi 还回原来那个网络」的统一入口。**每条离开动线的路径都要调**：搜索页 / 配网页的 `dispose`、两页的 `paused`（配网进行中与系统确认框显示时除外）、配网失败、以及**配网成功**。每步耗时写进失败消息（`｜令牌 812ms · 连热点 1.2s · 配网 120s`）并在失败页单独一行显示：失败码只说「哪一类」，它才说「死在哪一步」。

  **只有 AP 一条路**（`aef6ccd` 净删 1388 行）。删掉的四条不要再接回来：EZ（真机实测设备不支持）、涂鸦「热点配网新流程」`queryDeviceConfigState + startActivator`（前提是 SDK 自己连 Wi-Fi 热点，实测它不连）、扩展 SDK `ThingActivatorCoreKit`（同上）、`WifiManager#connect()` 静默连接与 `WifiNetworkSuggestion`（真机判死）。`PairingRequest` 也不再带 `mode`：只剩一个取值，留着只会让人以为还能切（2026-09-11 删）。

  **涂鸦不提供 AP 待配网设备的「发现」能力**（`getScanDeviceManager` 只覆盖蓝牙 / 有线网关 / Zigbee 子设备 / Matter），所以「搜索设备」页是本项目自加的、只能自己扫，Android 的 4 次/2 分钟配额绕不过去；⚠️ **但 BLE 那条是有的**（2026-09-11 解包核对）：`ThingHomeSdk.getBleOperator().startLeScan(LeScanSetting, BleScanResponse)` 一直都在，双模设备一上电就在广播 BLE、**不受 Wi-Fi 扫描配额约束**，通常一两秒就能扫到；`ScanDeviceBean.getFlag()` 里的 `CombosFlagCapability.SCAN_WIFI` 位（固件 TuyaOS ≥ 3.6.1）为真时，还能用 `getBleManager().queryWifiListForDeviceScan(QueryWifiSetting, IThingResultCallback)` 直接问设备要**它自己扫到的** Wi-Fi 列表，连手机的 Wi-Fi 扫描都省掉。这条目前是**并行加上去的发现通道**（搜索页 `_BleFindingsCard`），**配网本身没有改**，真机验完才谈要不要收掉其中一条；智能生活对 AP 设备根本不给雷达页，它那个「打开就发现」走的是蓝牙/局域网/Pegasus。逐条核对见 `docs/TUYA_CAPABILITY_AUDIT.md`。

  **失败码**：表已补到官方全量——中文页原表只到 207218，`207219`（连云端 iot-dns 失败）/ `207220`（配网任务整体超时）/ `207222`（读设备 Wi-Fi 列表失败）三条从英文页补，存档 `docs/reference/tuya-ap-mode-android.md` 已同步。**2026-09-14 起失败页只画一句「设备未能成功连接到当前Wi-Fi网络」**，原因 / 失败码 / 各步耗时由 `PairingFailurePage.diagnosticFor` 生成、配网页跳失败页前经 `FlowerpotState.logPairingFailure` 记进联调日志（`配网失败 ✗ …`）；其中失败码无论认不认得都带上，未登记的 `207*` 由 `_hintForUnknownTuyaCode` 给族级提示（不编具体含义），涂鸦那句没翻译的 `out of time` 由 `_hintForMessage` 换成能照着做的话。实测拿到过 **207220**。

  **产品事实：设备只要开机就一定处于可配网状态**，不需要长按、复位或任何确认动作——端上文案一律只说「请确认设备已开机」，搜索页不承担任何「确认设备状态」的交互；「设备已在配网状态，继续」与 `device_selection_page.dart` / `AppRoutes.deviceSelection` 均已删除，失败页按钮是「返回搜索设备」。**iOS**：没有任何公开 API 能枚举附近 Wi-Fi（`NEHotspotHelper` 要 Apple 特批），搜索页在 iOS 上列不出设备，给一个无条件的「下一步」。

  ⚠️ 以上反射签名与整条链路**均未真机验证**（本机无 Flutter/Kotlin 工具链）。三次试错的过程细节在 `docs/history/2026-09/` 里，**不在本文件重复**。

  键盘避让**一律用框架默认**（`resizeToAvoidBottomInset` 不覆写）：body 按键盘缩高 ⇒ 滚动视口变矮 ⇒ 光标自动滚进视口 ⇒ 输入框停在键盘上方。⚠️ **但这只是一半。** 页面底部浮着按钮（`Stack` + `Positioned`，如「连接 Wi-Fi」的「开始配网」、「纪念日编辑」的保存）时，框架的自动滚动默认只留 `EdgeInsets.all(20)`——也就是光标离视口底部 20px 就算可见，而**视口底部就是键盘顶部**，那 20px 正好被这颗浮动按钮占着，获焦的输入框于是停在按钮后面，用户看到的就是「还是被键盘挡住」。**解法：给 `TextField` 设 `scrollPadding`，把浮动按钮的占位算进 bottom**（`pairing_page.dart` 的 `_startButtonInset = 92`，与滚动区的 `padding.bottom` 同一个数；`memorial_edit_page.dart` 用 96）。2026-09-10 补上。⚠️ 不要再写「关掉 resize + 底部加 `viewInsets.bottom` padding」那一套——在 Scaffold body 里它错两次：视口不缩所以 `ensureVisible` 不会滚，且开着 resize 时 body 里的 `viewInsets.bottom` 恒为 0（已被 Scaffold 消费）。「设备配网」进度页（`PairingProgressView`；进行中那一步画转圈；成功后 `_pairInternal` 在第三步按 `FlowerpotState.cloudStageDelay` 停 1–2 秒随机——产品要的流程感，测试配置里置零）用 `LayoutBuilder` 收紧插图上下留白（矮屏 `maxHeight < 700` 再收一档，插图 190→150），让三步进度完整进首屏——正在配网时滚走的正是用户要盯的那几步。配网失败页不再用滚动视图：`_FailureSummary` 量出标题与失败原因的高度后把剩余高度给插图（200→96），小提示卡贴按钮上方，极端情况整块 `FittedBox` 等比缩。启动页 `SplashPage` 先只留背景图，品牌那一组内容由 `_showBranding` 开关关掉。配网三页全部走真实桥接调用，没有任何 mock：`lib/` 对 mock/fake/demo 的引用为 0，产品固定用 `MethodChannelTuyaRepository`（`MockTuyaRepository` 只在 `test/support/`）。涂鸦平台与 SDK 的接入要求见 `docs/TUYA_SDK_SETUP.md` 5.3 与 6.3。
- 设备控制：显示、LED、听觉、触觉、振动、行为时段、温标、时钟、校准与系统修复。LED 设置页是单开关，2026-09-28 起走独立的 `led_switch`（166，双色 LED 灯效总开关，默认关，`DeviceControlSettings.ledEnabled`），不再和显示页共用 117（现为自动亮度开关）。DP168为手动亮度0–100（0灭屏），不参与OTA收尾；显示页拖动120ms限频串行下发并补发最终值；松手草稿与设备快照稳定一致500ms后释放，最长5秒回到设备值，失败即恢复。亮度忙态不反复禁用自动开关；切自动取消排队亮度并等待在途请求完成。167 关机 / 169 文件分片下载按产品暂不对接。行为时段（中午小憩 / 夜间睡眠）的编辑弹层 2026-10-08 起和割草计划「编辑周X」共用 `features/mower/presentation/widgets/time_edit_sheet.dart`（`showTimeEditSheet` / `TimeEditSheet` 外壳、`TimeRangeWheels` 开始结束滚轮、`TimeDurationBar`），`schedule_slot_dialog.dart` 只剩花盆自己的时长算法（跨夜绕过午夜）。
- 我的与关于：「我的」进页即 `refreshUserInfo()` + `loadBasicData()`（昵称此前只有个人信息页会刷、意见反馈邮箱此前写死；2026-10-21 起基础数据每次调用都现拉，不再一次会话只拉一次）；意见反馈读后台平台邮箱 `BackendBasicData.platformEmail`（接口字段 `platformEmail`，2026-09-21 以前键名猜错、一直为空）并复制到剪贴板；菜单六项，2026-09-21 去掉「设备设置」；关于页标语「您的智能设备贴心伴侣」（2026-09-21 由「智能花盆」改，Logo 保留）；关于页去掉「版本说明」，「检查更新」与 App 启动检测共用一套升级弹窗——`compulsory==1` 强制升级不可取消，其余有新版本时在「关于YSplanter」点红点。`getLastVersion` 按 swagger 的 `AppVersionConApiOutput` 解析（`isUpdate`/`compulsory`/`downloadPath`/`upgradeTips`）。**版本号仍是 `AboutPageModel.current()` 里写死的 1.0.0，没有 package_info；「立即更新」只复制下载链接，没有 url_launcher。**
- 状态页摘要卡片底部指标图标（2026-09-15）：`widgets/status_metric_icon.dart` 的 `StatusMetricIcon`，尺寸与位置常量量自需水卡（可见圆底 40、行左收 8、右收 4、间距 8）。资源分两类：`water_level_icon` / `water_status_icon` / `metric_light_icon` / `metric_temperature_icon` / `plant_selection_badge_icon` 满幅；`status_*_icon.png` 80×80 里圆底只占 7–72，传 `transparentInset: statusIconInset` 放大到约 48.5 画，排版仍按 40。光照卡用 `metric_light_icon` + 叶子徽标、温度卡用 `metric_temperature_icon`、湿度卡没有满幅资源用 `status_humidity_icon`。需水卡本身未改。
- 状态详情的养护建议 2026-09-08 起写在 `TuyaStatusCopy` 的第三段 `advice` 里（中英各 12 条），四个状态页按界面语言取，不再各写一段。
- 设置与行为：「自动检测植物」（DP 163）和 LED 设置一样是独立页面里的单开关，设置页那一行只显示状态；帮助中心 2026-09-08 从「我的」搬到设备设置页、2026-09-14 再挪到首页快捷列表（`HomeActionKind.help`，不过在线门禁；2026-09-15 电池状态从首页快捷列表挪进设备设置页 `DeviceSettingsMenuKind.battery`，行首图标是 `_BatteryLinePainter` 画的品牌青描边电池，电池状态页删掉历史报表与 `BatteryTrendChartCard`，描述 `_TwoLineDescription` 固定两行高；首页底部帮助卡 `HomeHelpCard` 改为纯文本）；设备设置右上角的分享入口按产品要求先隐藏（`_shareEntryEnabled`）；「行为」页除午休 / 夜间两个时段外，第三张卡就是「休眠模式」本身（2026-09-09 由二级页面改为页内展开，`StandbySettingsCard`，原 `standby_settings_page.dart` 与 `AppRoutes.standbySettings` 已删除）——版式与交互跟午休 / 夜间一致：开关 DP 151 即时下发，「延迟时间」一行点开滚轮弹窗（`showStandbyDelayDialog`），按弹窗里的「保存」才写 DP 152（1–180 分钟），取值没变就不发。「其他设置」已删除只弹「暂未开放」的「系统文件更新」「修复系统文件」两行。
- 后端「产品ID」口径（2026-09-14 产品明确，详见 `docs/PRODUCT_RULES.md` §4.4）：**＝ 产品表的 `broadcastId` 字段**（后台产品列表 `/ZoneAdmin/Product/getProductList` 出参 `ProductApiOut.broadcastId`，界面叫「涂鸦产品ID」，swagger 描述残留「广播id」/「平台设备id」），当前存涂鸦平台产品 ID `yciq4kssu1fv8umn`。客户端要传产品 ID 的入参目前只有 `getProductFaqList.broadcastId`，App 由 `FlowerpotState.faqBroadcastId` 取 `/Client/Basic/getBasicData` 的 `deviceIdList` 第一个（`BackendBasicData.deviceIdList`，拍平解析会丢字符串数组所以单独取），**不写死兜底**，拿不到就不带；**不取设备的 `productId`**（`DeviceBean.getProductId()` 对这台花盆报 `ehbx83xdh9jkmxvz`）。与 `ProductApiOut.productId`（后台自增整数主键）、`TuyaConfig.broadcastId`（BLE 广播标识 `ehbx83xdh9jkmxvz`）都不是一回事。⚠️ 客户端没有产品列表接口：`/Client/Product/getProductList` 线上不存在（与乱写路径同样 500），原先搜索页调用它的 `refreshProductCatalog` 已于 2026-09-14 删除，搜索页认花盆只靠 `TuyaConfig` 的两个 ID。
- 内容与维护：定制动画（图库**单选**、上传、删除、置顶。**上传 = 后端 `setUserProductUpload` + DP 142 `dl_url`**（帧 `url_len(1B)+url+name_len(1B)+name`，`TuyaGalleryCodec`；2026-09-14 前只传后端、一条 DP 都没发）；删除一张 155 `del_photo`、全删 156、置顶 157 `pin_photo`，三处与 142 的文件名统一取 `BackendImage.fileNameOf(url)`（URL 最后一段）；143 `dl_show` / 144 `dl_cancel` 尚无入口。每一步在联调日志里有明文行；**2026-09-10 起版式分两态**——图库空着画虚线上传位（`docs/UI/定制动画.png`），有图只画三列缩略图网格（`docs/UI/v2/智能花盆ysplanter/定制动画-已上传图片（图库管理）.png`，虚线位让位），那排圆按钮不在卡里而是页面底部的悬浮条：上传常驻，「删除选中」「取消选择」有图才画。
  **2026-09-17 改单选**：选中态是 `_AnimationsPageState._selectedId`（可空文件 id，不是 `Set`），
  点另一张＝换选中、再点当前这张＝取消；没选中的格子不画勾选圈（选中那张的圈挂
  `Key('animation-tile-selected-<index>')`），说明文字去掉了「支持多选」。顶部「文件同步」按钮与「仅支持屏幕录制或本地文件」权限提示条 2026-09-08 已下线，不要按老设计稿加回来）、纪念日（固定生日/结婚走 158/159，自定义条目走 154 的 upsert 帧，列表满员 12 条 = 10 自定义 + 2 固定）、设备分享、解绑、恢复出厂和 OTA。**恢复出厂**（2026-09-21）走 `FlowerpotState.factoryResetDevice`：先 `_publishFactoryReset(strict: true)` 下发 DP 141，成功才进 `_unbindDevice(resetFactory: true)`（SDK `resetFactory` → 删后台 → 清本地）；141 发不出去就抛错、不解绑（离线沿用 `device_offline`）。页面在弹确认框前先过 `ensureDeviceOnline`。「重新配网」仍走 `removeDevice(resetFactory: true)`：尽力发 141、失败照样解绑；「移除设备」是 `removeDevice(resetFactory: false)` = SDK `removeDevice`，不发 141。OTA 没有对应功能点，走 SDK 的 OTA 接口：`checkFirmware` 查版本、`startFirmwareUpgrade` 只发起，进度与成败从事件通道回来，版本号只在 success 时更新。App 不直接和设备说话——进「设置」和「其他设置」页时静默查一次版本，查到新版本就在这两页各点一个小红点，用户点一下才通知涂鸦给设备下发升级。
- 个人中心：资料、账号安全、帮助、协议、隐私、关于与偏好。
- 设计系统：统一色彩、间距、资源、页面骨架和公共 Widget。公共提示/确认/输入框走 `AppDialog`；更新说明与 DP 诊断保留专用 `AlertDialog`。`AppDialogScrollView` / `AppDialogScrollbar` 为各弹框提供独立受限滚动区和可交互滚动条，操作区固定；长正文不溢出、短正文按内容收缩。专用固件、校准、时间、计划与 Wi-Fi 弹层也已覆盖；滚动条统一品牌青色4px圆角细条及浅色轨道，长内容首次显示且不淡出，编辑周X右侧留8px间距，当前入口与验收见 `docs/UI/DIALOG_SCROLLING.md`。
- 字体：`AppTypography.fontFamily` 是 `Source Han Sans CN VF`，但 `pubspec.yaml` **没有打包任何字体**，真机一律走系统回落——Android 上中文是思源黑体（只有常规 / 粗体，w500 画成常规）、英文是 Roboto（w500 画成中粗），**中英混排的 w500 标题会一粗一细**（2026-09-15 设置页「LED设置」即此，功能设置列表标题已改 w400）。其他设置页行高 56。
- OTA：设备固件版本取涂鸦 `DeviceBean.verSw` / `ThingSmartDeviceModel.verSw`（Android 曾误取协议版本 `pv`，2026-09-09 修正）；`checkFirmware` 两端都返回 `{version, currentVersion}`，成对来自同一条 OTA 记录（`upgradeStatus == 1` 那条），Dart 侧是 `FirmwareUpdate`，弹窗「当前版本」优先用 `currentVersion`、取不到才退回设备字段——设备可能有 MCU / Wi-Fi 模块多个可升级组件，混着取会让两行版本号对不上。 Android 超时和文本失败回调由 `TuyaOtaListenerBridge` 转成失败终态；本次实时版本上报（花盆148 / 割草机112）保留到安装阶段重验，割草机实时DP116=7/20可结束进行中升级。首个终态生效，细节以 `docs/OTA_实现说明.md` 和产品规则 §4.14 为准。
- 固件升级提醒（2026-09-15）：`checkFirmware` 两端多回 `upgradeType`（Android `UpgradeInfoBean.getUpgradeType`，常量 `UPGRADE_TYPE_REMIND=0 / FORCED=2 / CHECKING=3` 已解包核对；iOS `ThingSmartFirmwareUpgradeModel.upgradeType`），Dart `FirmwareUpgradeType.fromTuya`，认不出按检测升级（只红点）。`lib/src/app/firmware_reminder.dart` 的 `FirmwareReminderHost` 挂在 `MaterialApp.builder`，靠 `AppRouteTracker` 判断当前页：`/devices/` 下除设备列表、搜索、配网三页之外算设备页，进页、设备重新上线、固件版本变化时对该设备 `refreshFirmwareUpdate`（2026-10-21 起无 1 分钟缓存，同页普通刷新不重复问），提醒升级弹可取消的 `showAppDialog`、强制升级弹 `PopScope(canPop:false)` 的 `AppDialog`；「立刻更新」`pushNamed(deviceOtherSettings, DeviceOtherSettingsArguments(startFirmwareUpgrade: true))`，其他设置页进页即 `_checkFirmware(confirmed: true)` 跳过确认框。其他设置页、正在升级（未卡住）、盖着别的弹框时不弹。设备 id 由 `AppRoutes.deviceIdOf(RouteSettings)` 从各种路由参数里解出，植物详情这类不带设备的退回 `selectedDevice`。升级过程状态：涂鸦只有 13/14/100 准备 → 2 升级中(%) → 6 已下载到设备 → 3/4/7，没有下载 / 传输 / 安装三段；文案按 `OtaProgress.displayStage` 动态换（0% 准备中 → 1–97% 升级中 → **≥`OtaProgress.installingPercent`（98，2026-09-17 产品）或码 6 安装中** → 码 5 等待唤醒，`otaRunningLabel` 功能行与进度弹层共用，非升级中时进度条为不定进度动画、不写数字；98 那一段是设备写固件 + 重启的等待期，停在「98%」像卡死）。Android 监听器的 `onStatusChanged(otaStatus, otaType)` 只转 2/5/6/13/14/100 为 `stage`；iOS 没接状态回调，只靠进度推阶段。`_applyOtaProgress` 合并阶段与百分比，结论之后的进行中事件丢弃（见 PRODUCT_RULES §4.2.1）。
- 割草机 OTA 充电条件（2026-10-20修订）：主动提醒/强制提醒允许 DP117=charging（1）或 full（2，已充满）；手动检查可看版本，确认框完全退出后按目标设备最新原始 DP117 使用同一判据，未充电或未知提示「请回桩进行ota升级」。共用 `FlowerpotState.canStartFirmwareUpgrade`，花盆保持原规则；已运行 OTA 的进度可重开。DP115 code26 保留新鲜 DP111 分层定位，附加现场处理后等待1～2秒手动重试与保留位反馈建议。详见 PRODUCT_RULES §4.2.1/4.10/4.14、OTA_实现说明、MOWER_MACHINE_LOGS。
- 网络异常弹窗（2026-09-15）：`lib/src/app/network_alert.dart` 的 `NetworkAlertHost` 挂在 `MaterialApp.builder`，弹窗画在根 Navigator 的 Overlay 里。**不常驻监听系统网络**（没加 `connectivity_plus`、没动原生），而是在三个时机调 `NetworkStatus.probe`（`core/network/network_status.dart`，默认 3 秒内解析 APP 后端域名）：闪屏结束、回前台 2 秒后、以及 `NetworkStatus.reportFailure()` 之后——`ApiClient` 重试用尽抛 `NETWORK_UNREACHABLE` / `NETWORK_TIMEOUT` 前、`FlowerpotState._run` 收到 `TuyaException` 时各报一次（涂鸦码分不出是不是网络问题，一律交给探测判断）。不弹的情况：配网四个路由（`NetworkAlertHost.quietRoutes`）、最上面盖着别的弹框或进度圈（等它关掉再查，否则 `withBlockingProgress` 收尾会 pop 掉这个弹窗）、点「取消」后 3 秒内。「重试」：进度圈至少 600ms 再探测，通了就调**当前页**（`AppRouteTracker.currentPage`）上混入 `NetworkRetryAware` 的 `reloadForNetworkRetry()`，没登记的页面走 `reloadDevices()`。已登记：首页、我的、个人信息、关于、协议、帮助中心、定制动画、纪念日、选择植物、植物详情、报表、设置、其他设置。用例在 `test/flutter_test_config.dart` 把探测固定为有网。路由栈跟踪 `AppRouteTracker`（`app/app_route_tracker.dart`）与固件升级提醒共用。设备列表读失败时 `FlowerpotState` 也探测一次记进 `deviceLoadOffline`：为真时 `AppShell` 不进「添加设备」的 `HomePage`，进 `DeviceListPage` 画 `_DeviceListOffline`（「当前网络不可用，请检查网络后重试」+ 重试）。
- 会话：APP 后端 token 无客户端 TTL（`ApiSession` 持久化、不过期）。仅后端业务字段 `retCode=406` 时**只清后端会话**（2026-10-13 产品确认，`_handleBackendSessionExpired`）；HTTP 401、HTTP 406 及业务 401/403 等其它错误不清 Token，也不触发失效回调；涂鸦会话与设备列表保留——设备、DP、配网、固件全走涂鸦，与后端 token 无关；失效原因进 `sessionDiagnostics` 的「后端会话：…」，`ApiClient` 另打一行 `[session] 后端会话失效：<METHOD> <path> → HTTP/retCode`（只记路径，不记 token）。2026-09-09 之前这里是 `_clearLocalSession()`，一次 406 就把用户整个踢回登录页。
- 联调工具：**已删除**。2026-09-09 的代码审核把涂鸦 SDK 联调台（`/devtools/tuya`）、体验模式与静态预览开关整体移出产品包，登录页和「我的」页的入口一并去掉。现在排查靠三样：设备列表页底部的 `sessionDiagnostics` 一行、`[devices]` / `[session]` / `[pair]` 日志、以及 `ActionResult.code`。**2026-09-10 起 toast 文案不带来源前缀**（`接口-` / `涂鸦-` / `APP-` 已从用户可见文案中去掉，产品要求直接给内容）——来源标签只保留在**诊断行**上（`FlowerpotState._diagnostic`，用于 `sessionDiagnostics` 与 `_backendSessionError`），排查时的来源信息仍可从 `ActionResult.code` 拿到。

功能完成度以 [`docs/PRD_IMPLEMENTATION.md`](docs/PRD_IMPLEMENTATION.md) 为跟踪入口，UI 实施要求以 [`docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`](docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md) 为准。

## 6. 重要设计约束

1. 页面通过 `FlowerpotState` 和 Repository 使用业务能力，不直接依赖 MethodChannel 或散落 HTTP 调用。
2. `TuyaConfig.dp` 是 UI 读写与产品 PID 功能点之间的契约；变更必须与固件、涂鸦平台和测试一起核对。当前表来自 `assets/智能花盆test(yciq4kssu1fv8umn)_09_03.xlsx`，PID `yciq4kssu1fv8umn`，覆盖 101–160。
3. `TUYA_ENABLED` 只是选择真实 Repository 的编译期开关；平台安全组件、AppKey/AppSecret、包名和签名仍必须匹配，且运行环境必须真正按 `arm64-v8a` 或 `armeabi-v7a` 启动应用（涂鸦原生库不提供 x86/x86_64）。部分 x86_64 模拟器即使 ABI 列表包含 ARM，通用 APK 仍会优先以 x86_64 运行；显式 arm64 构建与安装方法见 `docs/TUYA_SDK_SETUP.md`。本机已有安全 AAR 时 Application 仍会尽力初始化 SDK，失败不阻止 App 启动，但产品页面此时读不到任何设备（Mock 仓库已移出产品包）。
4. 产品包内没有体验模式与静态预览开关（2026-09-09 删除），启动入口、鉴权分流和页面导航只有正式流程一条（登录页 → `AppShell`）。Mock 仓库只存在于 `test/support/`，真机链路仍需单独验证会话恢复和真实设备流程。
5. 新 UI 优先复用 `design_system` 和 `shared` 组件，遵循项目自己的 YSplanter 视觉规范，不复制参考项目的产品 UI。界面不标注占位数据，真假以源码和运行日志为准。
6. 命名路由与参数类型集中在 `AppRoutes`；修改路由前用 CodeGraph 检查页面和测试调用方。
7. CodeGraph 描述当前源码结构；Markdown 负责产品契约、平台配置、操作方法、设计决策和历史。

## 7. 环境与秘密管理

- `TUYA_ENABLED`、`API_BASE_URL`、`TUYA_DEBUG_TOOLS` 通过 `--dart-define` 注入。
- `API_BASE_URL` 必须是服务源站（例如 `https://api.example.com`），不能填写 `/swagger-ui.html#/` 页面地址；当前空值回落临时 HTTP，显式 `none` 才使用禁用型 Repository。Mock 测试应同时注入 Fake/禁用型后端。
- Android 涂鸦密钥放在未提交的 `android/local.properties`；安全组件按接入文档放置，不得写入普通 Markdown。
- iOS 安全组件、Bundle ID、Universal Link/App Link 和签名资料按平台受控管理。
- 文档、源码、历史记录和提交信息不得包含 Token、AppSecret、密码、签名材料、真实 Wi-Fi 凭据或用户数据。

## 8. 开发与维护流程

开始任务时按以下顺序读取：

1. `AGENTS.md`
2. 本文件
3. `docs/README.md`
4. 与任务相关的 Active 文档
5. CodeGraph 中的源码符号、调用链和影响范围
6. 仅在追查原因时读取相关 Historical 记录

执行约定：

1. 先运行 `git status --short`，保护正在进行的 UI、平台或资源改动。
2. `.codegraph/` 存在时，结构分析先运行 `codegraph status .` 和 `codegraph explore 问题或符号`。
3. 拉取代码后运行 `codegraph sync .`；完成有意义的源码修改后再次同步并检查状态。
4. Dart 代码至少运行格式化、`flutter analyze` 和相关测试；平台改动再执行相应 Android/iOS 构建或明确写出未验证项。
5. 架构、DP、平台配置、命令或产品行为变化时更新负责该事实的 Active 文档。
6. 一次集中修改建立一份 `docs/history/YYYY-MM/YYYY-MM-DD-主题.md`，不在 AI_CONTEXT 追加流水账。

## 9. 已知风险与未确认项

- Android Home SDK 7.5.1 与 Expansion SDK 7.8.0 已在本机 arm64 强制安装模式下完成初始化验证；账号、家庭、配网、设备控制和真机链路仍未完成联调，Mock 或 SDK 初始化通过不等于真实业务链通过。
- 静态演示构建使用 Mock 后端与空设备列表，接口错误、超时和真实鉴权行为都不会在其中出现。
- `FlowerpotState` 被大量页面调用，继续膨胀会扩大变更影响面；拆分前必须先分析调用链并保留行为。
- 除已确认的 DP 116 外，DP 101–115、117–123 的最终映射、倍率、枚举、统计服务、动画传输、分享和 OTA 回调仍需平台/固件确认。
- DP 116 `plant_variety` 已按可上报可下发处理：后端植物 `tuYaRemark` 是下发值，绑定成功后才下发，设备上报的已知标识符会反向更新当前植物；116 为空即「这台花盆还没有植物」。绑定时 116 与 161 `plant_type`（后台植物分类，enum 1/2/3）打包成同一条指令下发，后台没配分类时只发 116 并在结果里说明。162 `plant_confirm` 是数值：0 正常 / 1 异常 / 2 确认 / 3 忽略，0 和 1 由设备上报、2 和 3 由 App 下发，设备没上报过时按 0 处理；设备报 1 时不上报新植物标识，等 App 下发 2（改用盆里那株并重新上报 116）或 3（保持旧的 116）。163 自动检测植物开关**平台已于 2026-09-12 正式导出**，标识符是 `plant_confirm_switch`（此前本地占位写成 `plant_detect_switch`）；同批 162 由 `plant_confirm` 改名 `plant_present`，**DP 号与 bool 类型都没变**，行为不受影响。
- DP 140 校准固定依次发送 `step0`、`step1`、`step2`、`step3`，取消或在最终完成卡片尚未确认 `step3` 时关闭都发送 `step5`；`step4` 保留且不调用。
- 电量、PPFD、DLI 没有历史功能点，报表页上这几条是空态；**空气温度、空气湿度 2026-09-16 起有日历史**（DP 164 `temp_daily_hist` / 165 `humi_daily_hist`，`09_16` 那版功能点表新加），周 / 月仍然没有。这两条是**变长日帧**且导出里两行帧头写得不一样（164 三字节头、165 四字节头，而 165 那格说明整段是周 / 月口径，疑似抄串），现按产品《app_DP_问题修正说明》§4 统一为 3 字节头日帧（见下文「日历史」一条），点按 uint16 BE 解（164 有符号）、再按 `TuyaConfig.historyScale` ÷10 还原。**固件 1.0.12 把 165 改成与 164 对称的 2 字节大端 ×10**（此前是 1 字节整数 %），坐实了 09-16 按实时 DP 量程推的点宽；按对称口径 165 也该是 3 字节头，但导出没改、设备固件版本不由 App 定。⚠️ 1.0.12 以下的固件 165 仍报 1 字节点，App 按 2 字节解是错位曲线，帧长分不出 1B / 2B，只能设备先升级。**光照状态页的历史图读 137–139（`SensorMetric.light`，lux）**：2026-09-15 以前读的是 `SensorMetric.dli`，而 `MethodChannelTuyaRepository._historyMetric` 把 137–139 挂在 `light` 名下，所以真机上永远空；`LightDliBarChart` 纵轴原先写死 0–1，现在由页面按数据传 `maxValue`。四个状态页进页面都调 `FlowerpotState.logStatusDps`（读 `TuyaRepository.reportedDps`，即设备快照里的原始值，没报是 null），DP 清单在各页面 model 的 `reportedDps` 上；四页都另调 `logHistoryDiagnostics(metrics: …)` 只打本页那组历史 DP（温度 164、湿度 165 是 2026-09-16 加的）；**光照状态页默认范围改成日，日视图画折线（`WaterTrendLineChart`），周 / 月仍是柱状图**；**曲线跟随推送**：推送链路是原生 `onDpUpdate` / `dpsUpdate` → `_deviceUpdate` 合并快照并重新解码 131–139 → `_applyDeviceUpdate` 换设备并 `_recordLiveSamples`（按 `changedDps` 往 105/106/109/112/114 对应指标后面接点，同条推送带了该指标日包则清空）→ `notifyListeners`；四个状态页不再用 `historyFor` 的 Future，build 里直接读 `FlowerpotState.chartData`（`chartSeries` 是它的 `.values`；日视图 = 历史日包 + 实时点，取最后 `liveChartWindow`=96 个；周 / 月只画包、不截，月最多 180 点），同一份数据返回同一个列表（缓存）以免图表选中点被无关重建重置。`historyFor` 只剩报表页在用；设备图片已可在 APP 后端上传/列出/删除——2026-09-08 起列表 `getUserProductImgList` 与上传 `setUserProductUpload` 都按涂鸦 `deviceId` 传参，不再先用 `getUserProductList` 换后端 `userProductId`（设备档案由涂鸦提供）——但 142/143/144 从云端 URL 下发到硬件的协议仍待确认。
- 2026-09-09 已回滚明文回落：`ApiConfig` 默认就是 `https://api.yikaltd.com` 且只接受 HTTPS 源站，Android 的 `network_security_config.xml` 与 Manifest 引用、iOS 的 ATS 例外一并删除。**仍未使用真实账号执行写接口，真机端到端联调未完成**，release 包的 Manifest / Info.plist 与抓包结果也还没核对过。
- 验证码登录的自动注册复用的是同一条验证码：登录接口先判验证码（未注册手机号配错误验证码回的是「验证码错误」，说明验证码在账号查找之前判），失败后再调注册接口。若后端在验证码判过之后即作废，补注册会以「验证码错误」失败——这条只在 mock 上验证过，真机需要用真实短信确认。
- 配网三页已改为真实 `scanWifi` / `pairViaHotspot`（取令牌 → 连热点 → `pairWifiDevice`）链路。热点识别前缀已放宽到忽略分隔符的 `smartlif`（含量产件上见到的 `SmartLift-…`）、`tuya`、`ysplanter` 与 `ty_`/`ty-`，并且不再是门禁；2026-09-08 起搜索页在窗口内反复扫描、扫到设备热点就直接进选择页，且不再显示扫描台数、手机当前连接和「从附近网络中手动选择设备」；**2026-09-10 二次重做扫描节奏**：`scanWifi` 加 `refresh` 参数——`refresh: false` 只读系统扫描缓存，**不调 `startScan`、不等广播、不占配额**（受配额限制的只有 `startScan`，而系统自己也在扫、缓存会被它刷新）。搜索页因此改成两条线并行：**进页面先免费读一次缓存（权限框就挡在这一步）、等权限落定再开窗口与节奏，然后主动扫描 32 秒一次、均匀铺满 + 1 秒一次读缓存**。⚠️ 那次预热读缓存是 2026-09-10 加的，解决两件事：① 首次进入要授权（`scanWifi` 在原生侧要 `NEARBY_WIFI_DEVICES`/`ACCESS_FINE_LOCATION`，原生把调用挂起等用户答完），**让挡在权限框前面的是「读缓存」而不是「真扫」** —— 读缓存不占配额，用户点「允许」之前一次真扫都不会被浪费，3 分钟窗口与 32 秒节奏也都从授权之后才起算；② ~~非首次进入时缓存里往往已经有设备热点，设备会在进页面瞬间就出现~~——**2026-09-21 起取消**：那正是系统缓存里的旧条目（设备关了也照样出现），现在只列本轮开始之后看见过的热点（见上文双模动线那条），这次读缓存只剩挡权限框、带回当前路由器名两个用处。**不要为了快在开头塞两次真扫**，那是 0/6/46/86s 那版的错。其余节奏：，设备热点被任何一次扫描看到后最多 1 秒就出现在列表里。⚠️ **2026-09-10 第三次调整，不要再 front-load。** 上一版排 0/6/46/86s，把 4 次配额里的 2 次押在头 6 秒，赌「用户进页面时设备早就开着」——「先给设备上电、再进 App」这条赌赢了，但「**先进 App 点搜索、再给设备上电**」这条头两次全扫在设备还没广播热点的时刻、白扔，有用的第一次要等 46s、错过就是 86s，测试反馈的「很慢很慢才搜到」就是它（**配额并没有被打满，是分布错了**）。均匀排之后设备无论何时上电最多 32 秒被扫到（4 次/2 分钟 ⇒ 平均 30 秒是上限，取 32 秒留余量；第 5 次落在 128s，滚动窗口 [8s,128s] 内只有 3 次）。读缓存是本页唯一能无代价拉高的频率（受配额约束的只有 `startScan`）。「连接 Wi-Fi」页填 SSID 也改走 `refresh: false`——名字来自 `connectionInfo` 根本不需要扫描，改前却要等最多 5 秒的广播。SSID 带出规则：**连着就直接带出来、没连就留空**（挂在设备热点上按「没连」处理；频段不再过滤，5G 由页面提示说明）。**2026-09-10 重做了扫描节奏**——09-08 那版是「45 秒窗口 + 每 2 秒重扫」，而 **Android 9 起前台应用每 2 分钟只允许 4 次 `startScan`**，配额在头 20 秒就被烧光，之后整个窗口拿回的都是被拒后的旧缓存，「先进搜索页、再给设备上电」于是永远搜不到。现在是「开头 2 次快扫（间隔 3 秒）→ 之后 30 秒一次」，窗口拉长到 3 分钟，两条出路（「重新扫描」「设备已在配网状态，继续」）全程都在；Android 桥接的 `scanWifi` 多回 `throttled`（`startScan` 被拒）与 `ageMs`（缓存年龄），页面据此在被限流时明说「系统限制了 Wi-Fi 扫描频率，正在等待下一次扫描」，**一次都没真扫成过时给「无法确认附近设备」而不是「未发现配网中的设备」**，选择页也去掉了「显示附近全部网络」和「设备已在配网状态，继续」；Android 桥接的 `scanWifi` 现在等一轮 `SCAN_RESULTS_AVAILABLE` 广播（最多 5 秒）再回，避免返回设备进入配网状态之前的缓存。iOS 不返回附近网络列表，搜索与选择页在 iOS 上只能走「手动继续」。 2026-09-09 起「连接Wi-Fi」页的 Wi-Fi 名称不再吃 `FlowerpotState.wifiScan` 的旧快照：进页面强制重扫，回到前台（`resumed`）再刷新一次，只在输入框为空或内容仍是上次自动填入值时才覆盖，用户自己输入 / 从「切换」选过的名称与重试带入的值都保持不动；配网进- **日历史按单帧上报**（产品《app_DP_问题修正说明》§4，`docs/history/other/app_DP_问题修正说明.md`）：
  日 = 每指标 7 帧、每帧 `[年偏移][月][日] + N×点`（过去 6 天 N=96，今天 N=当前槽+1）；周 =
  `[年偏移][月][日][N] + N×点`（N≤28）；月 = `[年偏移][月][日][段号][总段数] + M×点`（1~2 段，每段≤90）。
  `TuyaHistoryCodec.decodeDayFrame / decodeWeekFrame / decodeMonthSegment` 只解单帧并做帧长自检；
  涂鸦快照每个 DP 只留最后一帧，所以 `HistoryFrameBuffer`（仓库里每台设备一份）跨推送攒帧：日按帧头
  日期归档、同日整块替换、只留最新往前 7 天，**早于昨天却不满 96 点的过去帧丢弃**；月按段号拼。
  `DeviceHistory`：`series(metric, day)` 是**最新日期那帧**（不是最后到的那帧），`_daily` 按 `MM-DD`
  存 7 天，`_latestDays` 记每个指标的最新那天。**没采到的槽设备以 0 补齐**：`dayGaps` /
  `latestDayGaps` 把「这天所有有数据的指标在同一槽都是 0（且至少两个指标到了）」判为没采到——单看
  一个指标分不出（夜里光照、空水箱都是真 0），空气湿度不会是真 0。
  状态页用 `FlowerpotState.chartData` 拿 `HistoryChart`（`values` + 日视图每点的 `minutes` + `gaps`）。
  过去某天走 `daySeries`、**不接实时推送点**。日视图横轴由 `HistoryPeriod.timeTicks(minutes)` 按点的
  真实时刻标整点（今天那条只到现在，不能写死 00:00–24:00）；周 / 月只标相对天数。
  `WaterTrendLineChart`：`gaps` 处断线 + 灰底「未采集」；有负值（零下温度）时纵轴按原格距往下延伸、
  0 线画实、零下段用 `AppColors.info`；`labelPositions` 让横轴标签落在对应点上。
  报表页（`ReportsPage`，`historyFor` → `getHistory`）目前没有入口，未接 `gaps` / 时刻刻度。
」的一整段。
- **日期切换窗口只有一处定义**：`features/devices/models/history_period.dart` 的
  `HistoryPeriod`（`maxBack`：日 6 / 周 0 / 月 0，跟着 `TuyaHistoryCodec.maxDailyWindow` 走）。
  用它的有五处控件：四个状态页顶部的 `DateRangeNavigator`（需水 / 光照 / 空气温度 / 相对湿度
  ——**用户日常点的就是这个**）+ 报表页日视图的 `_DayPicker`
  （`Key('report-day-prev'/'-next'/'-label')`）。⚠️ 2026-09-17 修过一个 BUG：四个状态页原来是
  裸的 `periodOffset--`，能无限往前翻；而且当时 `chartSeries` 压根不看 `periodOffset`，标签翻了、
  曲线还是今天那条。**页面里不要再自己算天数。**
- raw 功能点（131–139 与 164/165 历史、154/155/157/158/159 纪念日与动画）**在 App 侧上报和下发都是十六进制串**：2026-09-13 解包 SDK 7.5.1 确认 `DevUtil.decodeRaw` 把云端的 base64 先转成十六进制再交给 `onDpUpdate` / `DeviceBean.getDps()`，`encodeRaw` 下发时反向转回 base64。上报统一走 `TuyaRaw.bytes`（先认 hex、再兜底 base64），下发走 `TuyaMemorialCodec.encodeRaw`；此前按 base64 解上报，历史报表因此「日志有数据、页面暂无」，158/159 读回也是乱码。仍未真机验证。设备不回报整份自定义纪念日列表；当前已接后端纪念日接口，**整组按涂鸦 `deviceId` 传参**（2026-09-13 起，swagger `ClientProductAnniversaryAddApiIn.deviceId`；`getUserProductList` / `getUserProductDetail` / `getProductList` / `addUserProduct` / `editUserProduct` / `delUserProduct` 已从 swagger 下线），后端会话可用时分配 id、保存并刷新列表；2026-10-21 起接后端时纪念日页只显示本次拉到的列表，失败显示重试，本地 `deviceMemorials` 不再顶替显示，后端未配置或会话失效时仍走本地路径。退出登录暂不清此缓存，账号隔离及迟到响应仍需加固。
- 2026-09-03 的两轮配网改动都只做了静态复核，`flutter test` 与真机均未跑（本机没有 Flutter 工具链）：热点识别放宽、选择页原始扫描结果回退、Android `scanWifi` 等待新一轮扫描结果，以及同日更早补的失败释放（`PairingResult` 包装、`cancelPairing`、Dart 侧 `leaveDeviceHotspot`）与手动回落路径。
- iOS 桥接已补齐配网前置、`joinDeviceHotspot`（`NEHotspotConfigurationManager`，需要 Hotspot Configuration entitlement，未配置时回 `hotspot_join_unsupported` 走手动路径）、`cancelPairing`、DP 上报与 OTA，但 iOS 侧全部改动尚未经过 Xcode 编译或真机验证；`createShareLink` 在 iOS 上仍是明确错误码（Home SDK 只有按账号分享）。
- 不要根据旧历史文档恢复已删除的平台文件；每次任务以实时 Git 状态确认工作区所有权，不将某次“有未提交改动”的状态视为跨环境事实。
- 2026-09-05 源码评审列出的问题，2026-09-09 那轮已处理其中五项：明文回落（S1）、资料刷新会话竞态（`ApiSession.revision` + `ApiClient._ensureSession`）、写请求网络异常重试（`postJson` 默认 `retryTransportErrors: false`）、体验模式退出未恢复真实仓库（体验模式整体删除）、配网销毁通知异常（搜索页改用 `Timer` 截止 + `mounted` 保护）。**仍未关闭**：S2 安全组件副本仍被 Git 跟踪（`git ls-files` 可见 `assets/Android_SDK1/security-algorithm/*.aar`）、S3 `/Client/` 请求仍把 `userToken` 放进 URL 查询且令牌仍存 `SharedPreferences`。依据和整改优先级见 `docs/RELEASE_READINESS_REVIEW.md`，实际验证见对应历史记录。

## 10. 文档地图

- [`docs/README.md`](docs/README.md)：文档导航、状态和维护规则。
- [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md)：当前项目目录和分层。
- [`docs/COMMON_MODULES.md`](docs/COMMON_MODULES.md)：从参考项目复用的公共能力和保留边界。
- [`docs/PRD_IMPLEMENTATION.md`](docs/PRD_IMPLEMENTATION.md)：PRD 实现与待联调清单。
- [`docs/TUYA_SDK_SETUP.md`](docs/TUYA_SDK_SETUP.md)：涂鸦平台与原生 SDK 接入。
- [`docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`](docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md)：UI 页面实施规范。
- [`docs/history/README.md`](docs/history/README.md)：本地操作更新记录规范与模板。

## 11. 兄弟项目边界与同步触发

| 项目 | 主要职责 | 需要同步的变化 |
| --- | --- | --- |
| `flowerpot` | YSplanter Flutter 用户端 | 用户态接口模型、设备状态、DP、配网、OTA、协议和客户端口径。 |
| `flowerpot-web` | 花盆产品 PC 管理后台 | 产品、版本、用户设备、管理菜单、权限和运营字段。 |
| `web-ui-v2` | BoltFox PC 管理后台 | 仅在复用的管理端契约或公共前端方案变化时同步。 |

跨项目同步必须在各自历史记录中写明上游来源、新契约、已同步内容、有意差异和未完成项。不要把 Flutter 命令、涂鸦 SDK、DP 或移动签名规则复制到 Web 项目。

## 12. AI 工作备注

- 源码、CodeGraph 和当前工作树优先于旧截图、旧会话记录或绝对路径说明。
- 不覆盖与当前任务无关的未提交文件，不恢复用户已经删除或迁移的内容。
- 不把某台机器的 SDK 安装状态、缓存或签名能力写成跨环境事实。
- Historical 只用于追溯；与源码或 Active 文档冲突时，先核验当前实现并修正文档。

### 离线操作与继续（2026-10-14）

设备控制/参数正文由 `DeviceOnlineBody` 随SDK online淡显禁用；割草机setter与状态层下发、OTA均保留最新在线门禁。离线不提醒升级或显示缓存红点；停止/故障继续只发DP2=true、不重写119；待机继续置灰，新任务仍由自动/定点的安全+时长流程发起。当前产品契约见PRODUCT_RULES §4.21及DEVICE_ONLINE_STATUS。

### DP101 星期布局与割草机消息（2026-10-15）

按产品确认的DP101备注，88字节中的组0为全部设置、组1~7为周一到周日；此前V2.6正文的星期布局有误，已校正。单日修改及复制整周都显式写组1~7、组0全零；收到有效组0时展开为七天，之后编辑仍转逐日全量写回。复制整周只含两个时段、各天edge独立维护，关闭复制只改目标日。界面周日优先，换算集中在MowerScheduleCodec。首页文案取有效DP117：0/not_charging不显示充电文案、1/charging充电中、2/full已充满，兼容整数及数字字符串；100%不覆盖状态文字，未上报不编造，非法值保留最后有效状态。闪电仍仅电量<100且charging显示，full或100%不显示闪电；设备/电量环整体在剩余空间上下居中，紧凑屏滚动。消息页复用品牌分段控件，恢复按当前设备查询涂鸦历史，并按设备通知/设备异常/其它标题分到日志/告警/提醒，日期互不影响；移除当前等级、来源说明和云端调试区，时间取云端消息字段。消息为无底部导航的独立二级页，设置和消息显式传递设备ID。根MaterialApp接入flutter_localizations标准delegates并支持现有zh/en，花盆/割草机日期弹窗指定APP语言，中文模式含日历与取消/确定全部中文。

### DP101显示来源（2026-10-14核查）

`MowerDevice.schedule`只由有效88字节涂鸦返回更新；setSchedule不再乐观改计划，独立保留下发草稿和设备返回。计划页等待回读时禁止重复编辑；DP115仅受理/拒绝，不能替代DP101。默认停用时间通过来源标记保留，非法时段/非七天在SDK前拦截。具体字节、初始快照与真机诊断见docs/MOWER_SCHEDULE_DP.md。
