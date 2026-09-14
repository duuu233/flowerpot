# AI 项目上下文

> **产品口径与硬性要求看 [`docs/PRODUCT_RULES.md`](docs/PRODUCT_RULES.md)**（必须怎样 / 绝对不要怎样）。本文件只放**技术事实**，试错过程在 `docs/history/`。三者不重复。

> 文档类型：当前项目上下文
> 状态：Active
> 最后核验：2026-09-10
> 适用范围：`flowerpot` 当前工作树
> 事实来源：源码与 CodeGraph、`pubspec.yaml`、平台配置和 `docs/` 中的当前文档

## 1. 项目定位

`flowerpot` 是 YSplanter 智能花盆的 Flutter iOS/Android 客户端，覆盖账号、设备配网、设备与植物状态、报表、设备设置、固件升级、动画资源和个人中心。PC 管理后台与服务端是独立项目，不应把管理端页面或部署规则写进本仓库。

项目可在没有涂鸦密钥和安全组件时以 Mock/静态预览方式运行；真实设备能力通过原生 Smart Life App SDK 与 Flutter `MethodChannel` 桥接。

Git 是办公室电脑、家庭电脑和远程 SSH 环境之间唯一共享的事实来源。本机 SDK、构建缓存、签名材料、`.codegraph/` 和未提交工作区不属于跨机器共享状态。

## 2. 技术栈与常用命令

- Flutter / Dart，Dart SDK 约束为 `^3.11.5`。
- Material 3、feature-first 页面组织、命名路由。
- `ChangeNotifier` 的 `FlowerpotState` 管理应用状态，`FlowerpotScope` 通过 `InheritedNotifier` 向页面提供状态。
- `http` 提供 REST 客户端，`crypto` 负责后端密码接口要求的 MD5，`shared_preferences` 保存会话和本地偏好，`image_picker` 选择图片。
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
| `lib/src/design_system/` | Design Token、资源索引和公共视觉组件。 |
| `lib/src/shared/` | 跨 Feature 复用组件。 |
| `lib/src/core/network/` | REST 请求、会话、异常和重试。 |
| `lib/src/core/backend/` | APP 后端账号、用户设备、植物、设备图片模型与接口封装。 |
| `lib/src/tuya/` | 涂鸦 DP 表与配置、模型、raw 历史解码、Mock 与 MethodChannel Repository。 |
| `android/`、`ios/` | 平台工程、SDK 配置和桥接实现。 |
| `test/` | 网络、配置、页面和公共组件测试。 |
| `docs/` | 架构、UI、平台接入和冻结历史记录。 |

## 5. 当前核心模块

- 账号：配置 `API_BASE_URL` 后，国内手机号短信、验证码/密码登录与注册走 APP 后端，再用返回的映射凭据登录涂鸦；验证码登录未注册即自动建号；海外邮箱及找回密码等原有能力保留涂鸦链路。
- 设备实时性：DP 上报、上下线和解绑由原生监听推给 Dart，页面自动刷新；温标（146）与时间格式（147）下发后 App 自身展示跟随。
- 状态文案：需水（107）、光照（108）、空气温度（113）、空气湿度（115）四条枚举的文案集中在 `lib/src/tuya/tuya_status_copy.dart`，状态页顶部与首页状态卡片同源，设备没上报时按同一套阈值兜底（113 的兜底舒适区间 18–28℃ 也放在这里，温度状态页与首页共用）。2026-09-08 起每条状态都备了中英两份，取用走 `waterNeedsCopy` 这类按 `FlowerpotState.languageCode` 查表的方法，非英文一律回落简体中文；首页「今日养护」卡片改为轮播这四条状态的建议（5 秒一条，`HomeCareBanner`），文案与卡片、状态页同源。**注意：App 至今没有引入 `flutter_localizations`/arb，其余界面文案仍是硬编码中文**，这张表只覆盖这批状态文案。
- 多语言：`lib/src/shared/l10n/` 是界面文案框架——`AppLanguage` 枚举（现有 zh / en，加语种就加枚举值，缺译文按 `fallbacks` 回落到简中）、`AppLocalizationsScope`（挂在 `MaterialApp.builder`，切语言整树重译）、`AppL10n` 文案目录（`t({语言: 文案})`）。设置页的语言列表由枚举生成。**只有 2026-09-08 改动涉及的页面接入了目录，其余页面仍是硬编码中文**；`flutter_localizations` 尚未引入，Material 内建文案恒为英文。做法对齐相册 APP，区别是文案用 Map 而不是位置参数。
- 首页与设备：无底部菜单，设备列表即首页、左上角头像进入「我的」（顶栏正中显示当前设备名称，未绑定设备时是品牌标识）、配网（搜索 → 选择 → Wi-Fi → 成功）、选择植物、状态详情、报表和设备信息。设备详情页入口只剩离线一道门禁（「请打开设备并保持在线」）。**2026-09-09 植物 DP 契约改版**：DP 116 变成植物 id（`-1` = 盆里没有植物，`0..N` = 管理后台的「涂鸦标识 ID」，0 是通用植物），DP 162 变成两态且只上报（0 不弹窗 / 1 弹引导窗，App 不再写它——下发 116 后固件自己改回 0 并立即上报，116 = -1 或关掉自动检测时同样报 0）。进详情页先补植物资料再看 162：报 1 弹「发现新植物」引导窗：**id = 1..N** 时正文按 116 从后端目录取名字、按钮「确认」（原样回写当前上报的 id）与「选择植物」（跳选择流程）；**id = 0（通用植物，后台不建数据）** 时正文换成「已检测到通用植物，请选择并确认植物。」且只留「选择植物」一个按钮。返回键关掉则不发、下次再弹。116 = -1 时首页画不带植物的设备图、「今日养护」整行换成惊叹号 + 「未检测到植物，请将植物种入花盆。」、设备设置页的「植物」入口点了只提示同一句。标识匹配用 `FlowerpotState._plantKey`：能解析成整数按整数比，否则退回字符串，老固件的 `tuYaRemark` 仍可匹配。设备设置页有「自动检测植物」纯开关（DP 163，平台尚未导出）。设备清单只来自涂鸦：`getDevices` 先查家庭再取家庭详情，**家庭选择两端都已改为稳定规则**（Android 先挑带设备的家庭、再按 `homeId` 最小；iOS 按 `homeId` 升序取第一个），不再取列表返回的第一个——账号下有多个家庭时那会让同一账号不同登录看到不同设备；拉取失败不再被吞成空列表，`FlowerpotState.deviceLoadError` 会带上来源与错误码，设备列表页在「列表为空且有错误」时画错误态与「重试」，下拉刷新与错误态「重试」共用 `reloadDevices()`（该方法原名 `probeDevices`，调试台删除后只服务产品页面）；错误态与「暂无设备」空态底部都画一行 `sessionDiagnostics`（`uid · 家庭 · 设备 N 台 · 失败原因`，可长按复制），每次读列表还会打一行 `[devices] …` 日志，定位「读不到设备」看这一行即可。家庭属于涂鸦账号、由云端按 uid 返回，手机连哪个 Wi-Fi 不影响选哪个家庭；**2026-09-09 起家庭固定下来，优先级 后端 > 本地缓存 > 涂鸦列表现挑**：登录 / 注册响应里的 `tuYaHomeId`（后端待补该字段）一拿到就钉给涂鸦并写进本地；本地缓存记在 `SharedPreferences`（`tuyaHome:<uid>`），之后每次会话开始由 `_startSession` 先 `useHome`（桥接 `setHomeId`）钉给原生再拉设备列表，不再每次登录重挑。`prepareForPairing()`（确认家庭 + 取令牌）现在由**搜索页**进页面时预取，不再挂在「开始配网」上；空家庭列表在绑着设备热点时直接报 `home_offline` 不建家，正常网络下也先重查一次再建。钉住的家庭若读出 0 台设备，立刻作废缓存（`useHome('')`）并重读一次——缓存只是缓存，以涂鸦返回的为准。但 AP 配网期间手机在设备热点上没有外网，此时查家庭可能失败或拿到空列表进而自动建家，这是账号多出一个空家庭的主要来路。后端设备行按涂鸦 `deviceId` 关联；植物目录、详情、绑定/删除与设备图片使用 APP 后端。**分工要点**：涂鸦只回答「这盆里是哪一株」——设备通过 DP 116 `plant_variety` 上报后台配好的标识符（`tuYaRemark` 字符串，不是数字 ID），App 选植物时也是把标识符写回 116（分类另写 161）；植物的内容本身全部来自 APP 后端 `Client/Product/getProductPlantList` 的目录行——`plantImg`（列表与详情的图片）、别名、简介、最适温湿度、光照 / 浇水 / 温湿度建议、养护难度、`categoryType`，由 `_plantForIdentifier` / `ensurePlantProfile` 按 116 的标识符匹配，匹配不上就补拉一次目录再解析，仍失败则回落本地目录且不打断详情页；详情页上的实时数值（光照 107、需水 108、温度 113、湿度 115 等）来自设备 DP 上报，与这条后端链路无关。 2026-09-09 起**已绑定设备首页正中那张图也走这条链路**：`HomeDashboardModel.plantImageUrl` 取 `device.plant.imageUrl`，`HomePlantOverview` 优先画后台配的图，字段为空或图片加载失败才回落本地 `AppAssets.smartPlanterWithPlant`；植物详情页 `_PlantDetailArtwork` 早就是同一口径，回落的是 `AppAssets.plantImage(plant.id)`（未知 id 再退到通用图标）。**设备只支持涂鸦标准 AP 热点配网（AP-cfg），不支持 EZ/SmartConfig**（2026-09-10 设备开发口径）。未激活设备开机即自动开热点（`smartlife_xxx` / `tuya_mdev_xxx`，都在 `isDeviceHotspotName` 白名单内）；固件 **TuyaOS > 3.6.1（设备团队已确认）**，所以走涂鸦「热点配网新流程」。

  **铁律：配网全程不用 `WifiNetworkSpecifier`。** 它 + `requestNetwork` 在 Android 10+ **必弹**系统入网授权框，没有任何公开 API 能抑制它或代替用户点「连接」（2026-09-10 向涂鸦求证并实测确认；对方给的 `ThingSmartHotspotCredentialKit` 在官方 Maven 与其自己给的文档里都不存在，已改口「未公开发布」）。⚠️ **2026-09-10 实测推翻了「SDK 会替我们连热点」这条假设**：完整官方序列下单独调 `queryDeviceConfigState`，跑满 45 秒报 `207220`（配网任务整体超时），**全程没有弹出任何系统框**、手机始终在路由器上 ⇒ SDK 根本没去连。涂鸦 SDK 只是跑在我们进程里的库、没有额外特权；文档里「SDK 会在指定时间内自动去连接 AP 热点」那句写在**「恢复配网」**一节，讲的是中途掉线后重连**它已经连过的**热点，同一页开篇写的才是通用前提——「将手机连接到配网设备 Wi-Fi 热点后……**但用户需要手动切换手机的 Wi-Fi 设置**」。**所以①连热点必须由我们做**，用 `_joinHotspotForPairing`（`WifiNetworkSpecifier`，Android 必须给**确切 SSID**、iOS 只能给前缀）。产品口径：做不到零确认，但**自动选中**——框里只有搜索页扫到的那一台、已经选好，用户点一下「连接」，已连在该热点上时连框都不弹（见 `docs/PRODUCT_RULES.md` 1.2）。`openWifiPanel`（拉系统 Wi-Fi 面板）代码保留但**不在主流程上**。

  **配网主路径是蓝牙双模（2026-09-11 晚定稿，固件方已确认支持蓝牙配网）**，AP 热点那条完整保留作回落。改前先读 `FlowerpotState.pairViaBle` 与 `pairViaHotspot` 的文档注释。

  **双模动线**：① 搜索页进页面就开 BLE 扫描（`getBleOperator().startLeScan`，**不受 Wi-Fi 扫描配额约束**，双模设备一上电就在广播、通常一两秒出现）→ ② 扫到的设备直接进「已发现设备」列表（**扫到 BLE 就只列 BLE**，一台都没有才回落 Wi-Fi 热点那份——两条通道没有可靠的共同标识，混列就是同一台花盆出现两行）→ ③ **抢答窗口**：BLE 还在扫的头 4 秒（`_bleGrace`）**先不画 Wi-Fi 热点**——Wi-Fi 那条会先答（进页面读缓存不占配额、几乎不耗时，而缓存里往往已经有热点了），不压住的话用户会抢在 BLE 答出来之前点走更差的那条路；蓝牙用不了时一秒都不压，窗口到点由 `_bleGraceTimer` 主动重画。**Wi-Fi 扫描节奏没动**，它现在是回落路径但必须随时可用 → ④ 用户点「连接」：先 await 令牌预取，停扫（一边扫一边连是在抢同一个射频），`supportWifiList` 为真就调 `IMultiModeActivator.queryDeviceConfigState(MultiModeQueryBuilder)`——builder 直接吃 BLE 扫到的 `ScanDeviceBean`，**建本地蓝牙连接**问设备要它自己扫到的 Wi-Fi 列表，**不走系统 Wi-Fi scan** ⇒ 与「2 分钟 4 次 `startScan`」无关 → ⑤ 带着列表进「连接 Wi-Fi」页（「切换」弹层列的就是这份，比手机扫到的准）→ ⑥ `pairViaBle` → `IMultiModeActivator.startActivator(MultiModeActivatorBean{ssid,pwd,token,homeId,scanDeviceBean})`，凭据经蓝牙下发。**全程没有系统入网授权框，手机也从没离开路由器。**

  ⚠️ **`ScanDeviceBean` 必须留在原生侧**（`bleScanned` 按 uuid 缓存）：双模那两个 API 吃的是对象本身，它过不了方法通道；停扫时**不清**这张表（点完设备就停扫，紧接着还要用它）。
  ⚠️ **每次 `startBleDiscovery` 都是全新一轮**（2026-09-14）：还在扫就先停、清空 Dart 侧 `_bleDevices` 再开，扫描时长跟搜索窗口（3 分钟）对齐；原生到时 / SDK 自停发 `bleScanStopped`，经 `TuyaRepository.bleScanStops` 把 `bleScanning` 置回 false（原生只替**当前**回调代理报，重开时旧一轮迟到的结束不上报）。之前这条事件没人接，`bleScanning` 永远是 true，「重新扫描」被 `if (_bleScanning) return true` 挡成空操作，扫到过的设备也一直留在列表里。搜索页进页面 / 重新扫描 / 回前台（没在扫时）/ 从上层页面退回（`AppRoutes.routeObserver` 的 `didPopNext`）都走 `_scan()` 重开；停扫带 `owner`，叠两层搜索页时上层的迟到 `dispose` 掐不掉下层刚开的这一轮。**名字未定的设备整行不画**（`productInfoPending`，云端名最多等 5 秒），`uuid → 产品名` 表跨轮保留。
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
- 设备控制：显示、LED、听觉、触觉、振动、行为时段、温标、时钟、校准与系统修复。LED 设置页是单开关，与显示页共用 `disp_brightness_switch`（117）——2026-09-03 的功能点表没有独立的 LED 开关。
- 我的与关于：「我的」进页即 `refreshUserInfo()` + `loadBasicData()`（昵称此前只有个人信息页会刷、意见反馈邮箱此前写死）；意见反馈读后台平台邮箱并复制到剪贴板；关于页去掉「版本说明」，「检查更新」与 App 启动检测共用一套升级弹窗——`compulsory==1` 强制升级不可取消，其余有新版本时在「关于YSplanter」点红点。`getLastVersion` 按 swagger 的 `AppVersionConApiOutput` 解析（`isUpdate`/`compulsory`/`downloadPath`/`upgradeTips`）。**版本号仍是 `AboutPageModel.current()` 里写死的 1.0.0，没有 package_info；「立即更新」只复制下载链接，没有 url_launcher。**
- 状态详情的养护建议 2026-09-08 起写在 `TuyaStatusCopy` 的第三段 `advice` 里（中英各 12 条），四个状态页按界面语言取，不再各写一段。
- 设置与行为：「自动检测植物」（DP 163）和 LED 设置一样是独立页面里的单开关，设置页那一行只显示状态；帮助中心 2026-09-08 从「我的」搬到设备设置页；设备设置右上角的分享入口按产品要求先隐藏（`_shareEntryEnabled`）；「行为」页除午休 / 夜间两个时段外，第三张卡就是「休眠模式」本身（2026-09-09 由二级页面改为页内展开，`StandbySettingsCard`，原 `standby_settings_page.dart` 与 `AppRoutes.standbySettings` 已删除）——版式与交互跟午休 / 夜间一致：开关 DP 151 即时下发，「延迟时间」一行点开滚轮弹窗（`showStandbyDelayDialog`），按弹窗里的「保存」才写 DP 152（1–180 分钟），取值没变就不发。「其他设置」已删除只弹「暂未开放」的「系统文件更新」「修复系统文件」两行。
- 后端「产品ID」口径（2026-09-14 产品明确，详见 `docs/PRODUCT_RULES.md` §4.4）：**＝ 产品表的 `broadcastId` 字段**（后台产品列表 `/ZoneAdmin/Product/getProductList` 出参 `ProductApiOut.broadcastId`，界面叫「涂鸦产品ID」，swagger 描述残留「广播id」/「平台设备id」），当前存涂鸦平台产品 ID `yciq4kssu1fv8umn`。客户端要传产品 ID 的入参目前只有 `getProductFaqList.broadcastId`，App 由 `FlowerpotState.faqBroadcastId` 取设备的涂鸦 `productId`、兜底 `TuyaConfig.productId`。与 `ProductApiOut.productId`（后台自增整数主键）、`TuyaConfig.broadcastId`（BLE 广播标识 `ehbx83xdh9jkmxvz`）都不是一回事。⚠️ App 的 `refreshProductCatalog` 调的 `/Client/Product/getProductList` 在 2026-09-14 拉取的 swagger 里已不存在（匿名调用回 500），它只用于搜索页兜底认产品、失败被静默忽略，认设备实际靠本地 `TuyaConfig` 常量。
- 内容与维护：定制动画（图库多选、上传、删除、置顶。**上传 = 后端 `setUserProductUpload` + DP 142 `dl_url`**（帧 `url_len(1B)+url+name_len(1B)+name`，`TuyaGalleryCodec`；2026-09-14 前只传后端、一条 DP 都没发）；删除一张 155 `del_photo`、全删 156、置顶 157 `pin_photo`，三处与 142 的文件名统一取 `BackendImage.fileNameOf(url)`（URL 最后一段）；143 `dl_show` / 144 `dl_cancel` 尚无入口。每一步在联调日志里有明文行；**2026-09-10 起版式分两态**——图库空着画虚线上传位（`docs/UI/定制动画.png`），有图只画三列缩略图网格（`docs/UI/v2/智能花盆ysplanter/定制动画-已上传图片（图库管理）.png`，虚线位让位），那排圆按钮不在卡里而是页面底部的悬浮条：上传常驻，「删除选中」「取消选择」有图才画。顶部「文件同步」按钮与「仅支持屏幕录制或本地文件」权限提示条 2026-09-08 已下线，不要按老设计稿加回来）、纪念日（固定生日/结婚走 158/159，自定义条目走 154 的 upsert 帧，列表满员 12 条 = 10 自定义 + 2 固定）、设备分享、解绑、恢复出厂和 OTA。OTA 没有对应功能点，走 SDK 的 OTA 接口：`checkFirmware` 查版本、`startFirmwareUpgrade` 只发起，进度与成败从事件通道回来，版本号只在 success 时更新。App 不直接和设备说话——进「设置」和「其他设置」页时静默查一次版本，查到新版本就在这两页各点一个小红点，用户点一下才通知涂鸦给设备下发升级。
- 个人中心：资料、账号安全、帮助、协议、隐私、关于与偏好。
- 设计系统：统一色彩、间距、资源、页面骨架和公共 Widget。所有提示/确认弹窗走 `AppDialog`（`design_system/widgets/dialogs/app_dialog.dart`），版式取自兄弟项目 `flutter` 的同名组件、配色换成 YSplanter 的品牌青；页面里不再出现 Material `AlertDialog`。
- OTA：设备固件版本取涂鸦 `DeviceBean.verSw` / `ThingSmartDeviceModel.verSw`（Android 曾误取协议版本 `pv`，2026-09-09 修正）；`checkFirmware` 两端都返回 `{version, currentVersion}`，成对来自同一条 OTA 记录（`upgradeStatus == 1` 那条），Dart 侧是 `FirmwareUpdate`，弹窗「当前版本」优先用 `currentVersion`、取不到才退回设备字段——设备可能有 MCU / Wi-Fi 模块多个可升级组件，混着取会让两行版本号对不上。
- 会话：APP 后端 token 无客户端 TTL（`ApiSession` 持久化、不过期）。后端回 401/406 时**只清后端会话**（`_handleBackendSessionExpired`），涂鸦会话与设备列表保留——设备、DP、配网、固件全走涂鸦，与后端 token 无关；失效原因进 `sessionDiagnostics` 的「后端会话：…」，`ApiClient` 另打一行 `[session] 后端会话失效：<METHOD> <path> → HTTP/retCode`（只记路径，不记 token）。2026-09-09 之前这里是 `_clearLocalSession()`，一次 406 就把用户整个踢回登录页。
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
- 温度、湿度、电量、PPFD、DLI 没有历史功能点，真机上这几条曲线是空态而不是曲线；设备图片已可在 APP 后端上传/列出/删除——2026-09-08 起列表 `getUserProductImgList` 与上传 `setUserProductUpload` 都按涂鸦 `deviceId` 传参，不再先用 `getUserProductList` 换后端 `userProductId`（设备档案由涂鸦提供）——但 142/143/144 从云端 URL 下发到硬件的协议仍待确认。
- 2026-09-09 已回滚明文回落：`ApiConfig` 默认就是 `https://api.yikaltd.com` 且只接受 HTTPS 源站，Android 的 `network_security_config.xml` 与 Manifest 引用、iOS 的 ATS 例外一并删除。**仍未使用真实账号执行写接口，真机端到端联调未完成**，release 包的 Manifest / Info.plist 与抓包结果也还没核对过。
- 验证码登录的自动注册复用的是同一条验证码：登录接口先判验证码（未注册手机号配错误验证码回的是「验证码错误」，说明验证码在账号查找之前判），失败后再调注册接口。若后端在验证码判过之后即作废，补注册会以「验证码错误」失败——这条只在 mock 上验证过，真机需要用真实短信确认。
- 配网三页已改为真实 `scanWifi` / `pairViaHotspot`（取令牌 → 连热点 → `pairWifiDevice`）链路。热点识别前缀已放宽到忽略分隔符的 `smartlif`（含量产件上见到的 `SmartLift-…`）、`tuya`、`ysplanter` 与 `ty_`/`ty-`，并且不再是门禁；2026-09-08 起搜索页在窗口内反复扫描、扫到设备热点就直接进选择页，且不再显示扫描台数、手机当前连接和「从附近网络中手动选择设备」；**2026-09-10 二次重做扫描节奏**：`scanWifi` 加 `refresh` 参数——`refresh: false` 只读系统扫描缓存，**不调 `startScan`、不等广播、不占配额**（受配额限制的只有 `startScan`，而系统自己也在扫、缓存会被它刷新）。搜索页因此改成两条线并行：**进页面先免费读一次缓存（权限框就挡在这一步）、等权限落定再开窗口与节奏，然后主动扫描 32 秒一次、均匀铺满 + 1 秒一次读缓存**。⚠️ 那次预热读缓存是 2026-09-10 加的，解决两件事：① 首次进入要授权（`scanWifi` 在原生侧要 `NEARBY_WIFI_DEVICES`/`ACCESS_FINE_LOCATION`，原生把调用挂起等用户答完），**让挡在权限框前面的是「读缓存」而不是「真扫」** —— 读缓存不占配额，用户点「允许」之前一次真扫都不会被浪费，3 分钟窗口与 32 秒节奏也都从授权之后才起算；② 非首次进入时系统/别的应用一直在扫，缓存里往往已经有设备热点，设备会在进页面瞬间就出现、一次 `startScan` 都不用发。**不要为了快在开头塞两次真扫**，那是 0/6/46/86s 那版的错。其余节奏：，设备热点被任何一次扫描看到后最多 1 秒就出现在列表里。⚠️ **2026-09-10 第三次调整，不要再 front-load。** 上一版排 0/6/46/86s，把 4 次配额里的 2 次押在头 6 秒，赌「用户进页面时设备早就开着」——「先给设备上电、再进 App」这条赌赢了，但「**先进 App 点搜索、再给设备上电**」这条头两次全扫在设备还没广播热点的时刻、白扔，有用的第一次要等 46s、错过就是 86s，测试反馈的「很慢很慢才搜到」就是它（**配额并没有被打满，是分布错了**）。均匀排之后设备无论何时上电最多 32 秒被扫到（4 次/2 分钟 ⇒ 平均 30 秒是上限，取 32 秒留余量；第 5 次落在 128s，滚动窗口 [8s,128s] 内只有 3 次）。读缓存是本页唯一能无代价拉高的频率（受配额约束的只有 `startScan`）。「连接 Wi-Fi」页填 SSID 也改走 `refresh: false`——名字来自 `connectionInfo` 根本不需要扫描，改前却要等最多 5 秒的广播。SSID 带出规则：**连着就直接带出来、没连就留空**（挂在设备热点上按「没连」处理；频段不再过滤，5G 由页面提示说明）。**2026-09-10 重做了扫描节奏**——09-08 那版是「45 秒窗口 + 每 2 秒重扫」，而 **Android 9 起前台应用每 2 分钟只允许 4 次 `startScan`**，配额在头 20 秒就被烧光，之后整个窗口拿回的都是被拒后的旧缓存，「先进搜索页、再给设备上电」于是永远搜不到。现在是「开头 2 次快扫（间隔 3 秒）→ 之后 30 秒一次」，窗口拉长到 3 分钟，两条出路（「重新扫描」「设备已在配网状态，继续」）全程都在；Android 桥接的 `scanWifi` 多回 `throttled`（`startScan` 被拒）与 `ageMs`（缓存年龄），页面据此在被限流时明说「系统限制了 Wi-Fi 扫描频率，正在等待下一次扫描」，**一次都没真扫成过时给「无法确认附近设备」而不是「未发现配网中的设备」**，选择页也去掉了「显示附近全部网络」和「设备已在配网状态，继续」；Android 桥接的 `scanWifi` 现在等一轮 `SCAN_RESULTS_AVAILABLE` 广播（最多 5 秒）再回，避免返回设备进入配网状态之前的缓存。iOS 不返回附近网络列表，搜索与选择页在 iOS 上只能走「手动继续」。 2026-09-09 起「连接Wi-Fi」页的 Wi-Fi 名称不再吃 `FlowerpotState.wifiScan` 的旧快照：进页面强制重扫，回到前台（`resumed`）再刷新一次，只在输入框为空或内容仍是上次自动填入值时才覆盖，用户自己输入 / 从「切换」选过的名称与重试带入的值都保持不动；配网进行中不刷新。
- raw 功能点（131–139 历史、154/155/157/158/159 纪念日与动画）**在 App 侧上报和下发都是十六进制串**：2026-09-13 解包 SDK 7.5.1 确认 `DevUtil.decodeRaw` 把云端的 base64 先转成十六进制再交给 `onDpUpdate` / `DeviceBean.getDps()`，`encodeRaw` 下发时反向转回 base64。上报统一走 `TuyaRaw.bytes`（先认 hex、再兜底 base64），下发走 `TuyaMemorialCodec.encodeRaw`；此前按 base64 解上报，历史报表因此「日志有数据、页面暂无」，158/159 读回也是乱码。仍未真机验证。设备不回报整份自定义纪念日列表；当前已接后端纪念日接口，**整组按涂鸦 `deviceId` 传参**（2026-09-13 起，swagger `ClientProductAnniversaryAddApiIn.deviceId`；`getUserProductList` / `getUserProductDetail` / `getProductList` / `addUserProduct` / `editUserProduct` / `delUserProduct` 已从 swagger 下线），后端会话可用时分配 id、保存并刷新列表，本地 `deviceMemorials` 是缓存，后端不可用时保留本地路径。退出登录暂不清此缓存，账号隔离及迟到响应仍需加固。
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
