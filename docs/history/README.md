# 本地操作更新记录

> 文档类型：历史记录规范与索引
> 状态：Active
> 最后核验：2026-08-25
> 事实来源：`AGENTS.md` 与项目文档治理约定

本目录补充 Git 提交，记录集中修改的背景、外部操作、验证和未完成项，但不替代源码、提交历史或 Active 文档。文件使用 `YYYY-MM/YYYY-MM-DD-topic.md`，任务完成后冻结。

## 模板

```markdown
# 主题

> 文档类型：Historical Change Record
> 日期：YYYY-MM-DD
> 环境：办公室 / 家庭 / SSH / 其他
> 分支与起始版本：branch / short-sha
> 范围：模块或仓库
> 当前权威文档：相关 Active 文档

## 背景与目标
## 变更内容
## 关键决策
## 外部操作
## 验证结果
## 未完成项与风险
## 回滚或恢复
```

只写实际完成的动作与验证。跨项目同步还要写上游来源、新契约、已同步内容、有意差异和未同步事项。禁止记录任何密钥、Token、签名材料、真实 Wi-Fi 信息、用户数据或完整环境文件。

## 索引

- [`2026-09/2026-09-18-割草机静态页面.md`](2026-09/2026-09-18-割草机静态页面.md)：新设备类型「割草机」的**静态页面**：新增 `lib/src/features/mower/`（首页 / 割草计划 / 设置三个一级页 + 设备参数、区域设置、雨淋设置、时间同步、语言切换、消息通知六个二级页），数据全部写死在 `mower_demo.dart`，不连 SDK、不发 DP、不读后端。入口按产品口径放在**搜索设备页**：已发现设备列表**下面**单独一行固定数据（`device-search-mower-demo`，门禁 `MowerDemo.enabled`），**刻意不混进 `_found`**——那份列表的语义是「这一刻真的扫到了什么」，塞假数据进去会让标题常年「发现 1 台设备」、「重新扫描」永不出现；行上写明「静态演示数据」；**同日追加**：设备列表末尾也加一张写死的卡片（`device-list-mower-demo`，同样不经过 `state.devices`，花盆那条线一点没动；列表为空时不画）。静态页不等于死页：勾选、拖滑块、点电量环轮看四种电量态、编辑时段、长按删除、恢复默认都改页面自己的 `State`，一次能把四张控制图、四张计划图走完。另记两条口径差：编辑弹窗分钟按 **1 分一格**（稿子画的是 10 分，但稿子自己的图表里有 16:23）；割草机取色单独放 `MowerColors`，不并进 `AppColors`。⚠️ 本机无 Flutter 工具链：未 pub get、未 analyze、未跑 flutter test、未编译、未真机；只做了括号配平、常量引用对表、与既有用例断言的冲突核对。两个入口都归 `MowerDemo.enabled` 一处开关。
- [`2026-09/2026-09-17-升级98%起显示固件安装中.md`](2026-09/2026-09-17-升级98%起显示固件安装中.md)：OTA 进度到 98% 之后涂鸦要停一大段等设备写固件、重启，停在「固件升级中 98%」像卡死。把已有的「固件安装中」档门槛从 100 降到 98（新增常量 `OtaProgress.installingPercent`），弹层自动换成与「固件准备中」同一套不定进度动效、不写数字；成功 / 失败收尾不变。顺手把同一用例里 09-15 写的 `find.text('固件准备中')` 断言改成按 key 取标题——那句和「其他设置」功能行是同一个字符串，本轮之前就是红的。⚠️ 本机无 Flutter 工具链：未 analyze、未跑 flutter test、未编译、未真机；四个 Dart 静态自检全绿。
- [`2026-09/2026-09-17-上传图片改设备口径-DP165两字节.md`](2026-09/2026-09-17-上传图片改设备口径-DP165两字节.md)：跟固件 1.0.12 同步两件事。①上传图片改成设备口径：**JPG Baseline（不能 Progressive）／4:2:0／≤ 320×240 的框（任意宽高比，小图不放大）／≤ 500 KB**，覆盖 09-16 的「总像素 ≤ 480,000、≤ 1 MB」——320×240 是设备屏幕，按总像素算出来的竖图高度会超出屏幕；`encodeJpg` 显式传 `chroma: yuv420`（默认 `yuv444`），Baseline 由 `package:image` 只写 `SOF0` 保证；去掉「原图够小就原样返回」的快路径，Skia 给大的尺寸在 isolate 里用 `copyResize` 再收一次；**做不出合格的图返回 null、两处调用中止上传并提示**（推翻 09-16 的「压不动也要传原图」）。②DP165 湿度日历史点宽从 1B 整数% 改为与 164 对称的 2B 大端 ×10——App 09-16 推的就是 2B，代码无行为改动，注释 / 文档从「推断」改成「1.0.12 确认」，帧头仍按帧长自动判；旧固件（< 1.0.12）的湿度日曲线会错位，已知并接受。⚠️ 本机无 Flutter 工具链：未 `pub get`（`pubspec.lock` 仍未更新）、未 analyze、未跑 flutter test、未编译、未真机；只跑了四个 Dart 静态自检（全绿）。
- [`2026-09/2026-09-16-状态文案改版-温湿度日历史164-165-光照图-上传压缩.md`](2026-09/2026-09-16-状态文案改版-温湿度日历史164-165-光照图-上传压缩.md)：四条状态功能点（107/108/113/115）文案按产品新稿整体重写（中英同步，108 的 `very_good` 从「晒太阳中」改口成「太晒了」，判据未动）；`09_16` 功能点表新加的 164 `temp_daily_hist` / 165 `humi_daily_hist` 接进温度、湿度状态页（**只有日**，点宽按实时 DP 量程当 uint16 BE 解再 ÷10，两行帧头在导出里写得不一样、App 按帧长自动判）；光照状态页默认范围周 → 日、日视图柱状改折线（周/月仍柱状）；定制动画与纪念日图片上传前压到总像素 ≤ 480,000、≤ 1MB（新增 `UploadImage`，解码缩放走 `dart:ui`、JPEG 编码走新依赖 `package:image`，失败传原图）。⚠️ 本机无 Flutter 工具链：未 `pub get`（`pubspec.lock` 未更新）、未 analyze、未跑 flutter test、未真机。
- [`2026-09/2026-09-15-固件升级进度文案按阶段动态显示.md`](2026-09/2026-09-15-固件升级进度文案按阶段动态显示.md)：产品反馈升级一直卡在 0% 像出问题。涂鸦仍无三段状态，改为按阶段动态换文案：0% 固件准备中（动画条）→ 有进度固件升级中 xx% → 100% 未成功或码 6 固件安装中，码 5 等待设备唤醒；Android 转发 `onStatusChanged` 进行中码，结论后迟到事件不回退。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-15-固件升级提醒-无网络缺省页-电池状态挪进设置.md`](2026-09/2026-09-15-固件升级提醒-无网络缺省页-电池状态挪进设置.md)：涂鸦升级状态只有排队 / 准备 → 升级中(%) → 已下载到设备 → 成功 / 失败 / 超时，没有下载 / 传输 / 安装三段，按口径不做；按 `upgradeType`（0 提醒 / 2 强制 / 3 检测，解包核对）在设备页弹提醒 / 强制升级框，立刻更新跳其他设置直接发起升级，设备列表与「我的」不监控；没网读不到设备进设备列表无网络缺省页；电池状态挪进设置页、删历史报表、图标对齐、描述固定两行高。⚠️ 未跑 flutter test，未编译，未真机。
- [`2026-09/2026-09-15-光照湿度温度状态页图标对齐需水.md`](2026-09/2026-09-15-光照湿度温度状态页图标对齐需水.md)：光照 / 湿度 / 温度三页摘要卡片底部图标太小、位置不对（光照 32 且在半边里居中、湿度 32、温度 48 但左收 28，且 `status_*_icon` 自带透明边），按需水卡统一为可见圆底 40、左沿 26、间距 8，新增 `StatusMetricIcon`。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-15-全局网络异常弹窗.md`](2026-09/2026-09-15-全局网络异常弹窗.md)：产品要求全局加「网络异常」弹窗（取消 / 重试，重试 = 刷新当前页）。不加插件、不动原生：闪屏结束 / 回前台 / 请求因网络失败后解析一次后端域名，解析不了才弹；配网动线不弹，盖着别的弹框时等它关掉；重试调当前页登记的 `reloadForNetworkRetry`，未登记页重读设备列表。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-15-设置页LED字重与其他设置行高.md`](2026-09/2026-09-15-设置页LED字重与其他设置行高.md)：设置页「LED设置」显粗的根因是没打包字体：Android 上中文走思源黑体（w500 画成常规）、英文走 Roboto（w500 画成中粗）；功能设置列表标题统一 w400。其他设置页 7 行行高 42 → 56，375×812 仍一屏。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-15-打包失败-三元分支里的空安全下标.md`](2026-09/2026-09-15-打包失败-三元分支里的空安全下标.md)：`3691d35` release 打包报 `Expected ':' before this`：`chartSeries` 在三元分支里写了 `map[a]?[b]`，`?[` 被当成嵌套三元。改为先取局部变量判空；新增 `tools/dart_ternary_null_index_check.py` 并写进自检清单（对坏版本报出同一行）。⚠️ 本机仍未编译，需重新打包确认。
- [`2026-09/2026-09-15-状态页曲线改为推送即往前移动.md`](2026-09/2026-09-15-状态页曲线改为推送即往前移动.md)：产品：「不需要特殊处理，只要涂鸦推送了报表就要实时动，往前移动那种效果」。撤掉 `1f5cfb4` 的比对重取，四个状态页曲线改为 build 里现读 `chartSeries`：日视图 = 历史日包 + 每次推送的 105/106/109/112/114 实时值，满 96 点挤掉最左边往前移，新日包以包为准；周 / 月只画包。温度、湿度日曲线由推送攒出来。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-15-状态页曲线跟随涂鸦推送实时刷新.md`](2026-09/2026-09-15-状态页曲线跟随涂鸦推送实时刷新.md)：核对「报表数据会不会跟着涂鸦推送实时变」：原生→仓库合并快照并重解 131–139→状态层换设备这条链路是通的，顶部实时值 / 状态本来就实时；**但四个状态页的曲线只在进页面 / 切范围时取一次，推来的历史 DP 不上图**。改为页面记下快照里本页那一段，`didChangeDependencies` 用 `historyReportedSince` 比对，变了重取并记日志；无关上报不重取。温度、湿度无历史 DP，不拿实时值拼曲线。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-15-四个状态页按DP读取核对与光照历史改读137-139.md`](2026-09/2026-09-15-四个状态页按DP读取核对与光照历史改读137-139.md)：首页四个状态子页按 `09_12` 功能点表逐条核：实时 / 状态 DP（105–115、146）解析都对；**光照历史图一直读 `SensorMetric.dli`，而 137–139 解在 `light` 名下，真机永远空态**，改读 137–139 并按 lux 画（纵轴不再写死 0–1）；四页进页面都在联调日志记本页 DP 号 + 原始值（`logStatusDps` / `reportedDps`），需水 / 光照页只打本页那组历史 DP；温度、湿度功能点表无历史 DP。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-14-取消配网确认与首页帮助中心调整.md`](2026-09/2026-09-14-取消配网确认与首页帮助中心调整.md)：取消配网二次确认（框画在进度页内，避免 `pushReplacement` 替换掉路由式弹框）；帮助中心挪到首页快捷列表电池状态下方并生成同风格图标，设置页移除；首页帮助卡改纯文本；今日养护改上下滚动轮播；帮助中心不显示的排查结论（后台表单语种默认英语、所属产品默认全部）。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-14-配网失败页一屏平铺与配网进度转圈和第三步停留.md`](2026-09/2026-09-14-配网失败页一屏平铺与配网进度转圈和第三步停留.md)：失败页去掉滚动视图，插图随失败原因高度在 200–96 间缩放、小提示卡贴按钮上方、极端情况整块等比缩，不截断文字；配网进度进行中那步画转圈，第二步文案改「正在把Wi-Fi信息同步给设备，请勿离开本页面」，恢复 `a0aa3bf` 删掉的第三步 1–2 秒随机停留（`cloudStageDelay`，测试配置置零）。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-14-帮助中心产品ID核对与定制动画上传下发DP142.md`](2026-09/2026-09-14-帮助中心产品ID核对与定制动画上传下发DP142.md)：帮助中心 `getProductFaqList` **已在传**涂鸦平台产品 ID（swagger 客户端唯一的产品筛选参数 `broadcastId`「平台设备id」），只是请求日志不进联调日志，补一行明文；**定制动画上传此前一条 DP 都没发**，按 09_12 功能点表补 DP 142 `dl_url`（`url_len+url+name_len+name`，新增 `TuyaGalleryCodec`），文件名与 155/157 统一取 URL 最后一段；上传区去掉「或拖拽」。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-14-搜索页不缓存与重新扫描.md`](2026-09/2026-09-14-搜索页不缓存与重新扫描.md)：搜索页三条——**「关了设备还能搜出来」与「重新扫描扫不到」同一根因**：`startBleDiscovery` 开头 `if (_bleScanning) return true`，扫到的设备挂在全局状态上从不清，原生 60 秒到时发的 `bleScanStopped` 没人接、`bleScanning` 恒为 true，重新扫描被挡成空操作；改为每次全新一轮（停旧、清列表、真开扫，接上结束事件，停扫认主人，从上层页面退回也重开）。**设备名闪**：名字未定整行不画（撤掉 09-12 的「正在识别设备…」），云端名 5 秒超时。「还没搜索到设备」改一句话 + 失败插图。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-13-需水状态指标行与纪念日输入框样式.md`](2026-09/2026-09-13-需水状态指标行与纪念日输入框样式.md)：需水状态「水仓水位 / 土壤湿度」两组改为等分靠左、竖线显式留白 9（原 `VerticalDivider` 宽度取主题 `space`=1，右组贴线），字号图标按稿量；纪念日编辑页输入框关掉全局主题漏进来的白底胶囊（`filled` 与 `enabledBorder`/`focusedBorder` 会从 `inputDecorationTheme` 补回）。⚠️ 未跑 flutter test，未真机。
- [`2026-09/2026-09-13-纪念日接口改deviceId与raw上报按十六进制解.md`](2026-09/2026-09-13-纪念日接口改deviceId与raw上报按十六进制解.md)：**纪念日 404** 卡在保存前换 `userProductId` 那一步——`getUserProductList` 等 6 个用户产品接口已从 swagger 下线，纪念日整组改按涂鸦 `deviceId` 传参；**需水状态报表「日志有数据、页面暂无」**——解包 SDK 7.5.1 确认 `DevUtil.decodeRaw` 交给 App 的 raw 上报是十六进制串，App 却按 base64 解，新增 `TuyaRaw` 统一解码（158/159 读回同一根因），水位曲线纵轴改为 0–200 mL。⚠️ 未跑 flutter test，未真机验证。
- [`2026-09/2026-09-11-pairing-stuck-fix-and-ble-discovery.md`](2026-09/2026-09-11-pairing-stuck-fix-and-ble-discovery.md)：**「输完 Wi-Fi 密码点下一步卡住」的修复 + 配网改走蓝牙（双模）**。卡住那条——`aef6ccd` 那次大删除把 `_pair()` 里的 `_pairingState = state` 与 `setState(() => _pairing = true)` 一起删了，进度页再也不出现、「取消配网」够不到、切后台还会把正在下发凭据的热点通道掐断；按 `223bdae^` 原样恢复并补回归断言。同轮按官方 4 步梳理配网并删掉多余代码（`pairDevice`、`PairingRequest.mode`、`PairingArguments.deviceName`、`_PairingHintCard`、三段悬空注释），另**把配网主路径换成蓝牙双模**（固件已确认支持）：`getBleOperator().startLeScan` 发现 → `CombosFlagCapability.SCAN_WIFI` 判 `supportWifiList` → `IMultiModeActivator.queryDeviceConfigState(MultiModeQueryBuilder)` 走**本地蓝牙连接**拿设备扫到的 Wi-Fi 列表（绕开系统 scan 频次限制）→ `IMultiModeActivator.startActivator(MultiModeActivatorBean)` 凭据经蓝牙下发，**全程没有系统入网授权框**；AP 那条完整保留作回落。反射目标用新工具 `tools/aar_class_dump.py`（不依赖 JDK）解包逐个核对过，并**证伪**了一段示例代码里的 `ActivatorService` / `BLEActivator` / `IDiscovery` / `ActivatorMode` / `DiscoveryMode`（7.5.1 全模块 0 命中，那是设备固件侧 TuyaOS 的命名）。⚠️ 双模整条未真机验证。
- [`2026-09/2026-09-10-toast-drop-source-prefix.md`](2026-09/2026-09-10-toast-drop-source-prefix.md)：toast 去掉 `接口-` / `涂鸦-` / `APP-` 来源前缀直接给内容；`_tagged` 改名 `_diagnostic` 只服务诊断行（`sessionDiagnostics` 与后端会话失效原因），来源信息仍在 `ActionResult.code` 里。
- [`2026-09/2026-09-10-ap-new-flow-implemented.md`](2026-09/2026-09-10-ap-new-flow-implemented.md)：配网整体切到涂鸦「热点配网新流程」——桥接新增 `apQueryDeviceWifi`/`apStartPairing`/`apStopPairing`，**连热点交给 SDK**，`WifiNetworkSpecifier` 与手动引导整套退出动线；「切换 Wi-Fi」改列设备自己扫到的网络。⚠️ 反射签名与固件版本（TuyaOS ≥ 3.6.1）均未真机验证。
- [`2026-09/2026-09-10-tuya-ap-new-flow-found.md`](2026-09/2026-09-10-tuya-ap-new-flow-found.md)：**找到官方「热点配网新流程」——SDK 自己会连热点**，不必再用 `WifiNetworkSpecifier`、也就没有系统授权框；`ThingApActivatorBuilder` / `IThingOptimizedActivator` / `queryDeviceConfigState` 等接口在 7.5.1 里已实测存在，无需升级 SDK。前置条件：设备固件 TuyaOS ≥ 3.6.1（待设备开发确认）。官方文档已存档到 `docs/reference/`。
- [`2026-09/2026-09-10-ap-only-and-system-consent-checklist.md`](2026-09/2026-09-10-ap-only-and-system-consent-checklist.md)：设备开发确认**只支持 AP（AP-cfg）、不支持 EZ/SmartConfig**，桥接里的 EZ 分支就此确认为死代码；并给出「昨天的包不需要授权」的排查清单——EZ 假设已排除，剩下「点按钮那一刻手机是不是已经连在设备热点上」与「系统记住了授权」两个待核实解释。仅文档，无代码改动。
- [`2026-09/2026-09-10-login-toast-only-and-toast-width.md`](2026-09/2026-09-10-login-toast-only-and-toast-width.md)：登录页去掉输入框下面那行校验提示（只留 toast，校验本身没松）；toast 宽度由写死 300 改成跟屏宽走，「请先阅读并同意用户协议与隐私政策」不再折行（原来留给文字只有 236，这句要 224，只差 12px）。
- [`2026-09/2026-09-10-pairing-flow-batch.md`](2026-09/2026-09-10-pairing-flow-batch.md)：配网动线七项——表单页键盘避让、配网期弹框收敛（含不再用通配前缀触发系统「查找设备」框）、第三步「连接云端」给 1–2 秒随机停留、失败页版式重排（小提示重叠 + 多余滚动条）、搜索页改内联列表并删除「选择设备」页、去掉「设备已在配网状态，继续」、启动页先只留背景图；另把 09-09 加的 `home_unresolved` 门禁降级为诊断（疑似「配网又不行了」的成因）。
- [`2026-09/2026-09-10-device-search-scan-throttle.md`](2026-09/2026-09-10-device-search-scan-throttle.md)：搜索不到设备——09-08 改成的「45 秒窗口每 2 秒重扫」把 Android「每 2 分钟 4 次 `startScan`」的配额在头 20 秒烧光，之后整窗口都在读上电之前的旧缓存。改成「2 次快扫 + 30 秒节奏 / 3 分钟窗口 / 出路全程可见」，桥接补 `throttled` 与 `ageMs`，被限流时明说而不是谎报「未发现设备」。
- [`2026-09/2026-09-10-auth-phone-format-feedback.md`](2026-09/2026-09-10-auth-phone-format-feedback.md)：手机号格式校验补上反馈——「获取验证码」不再按格式置灰（灰按钮点不动也不说话），改为照常可点、在发送前挡下并同时给 toast 与输入框下面那行常驻提示；登录/注册/重置提交也补上账号格式校验。
- [`2026-09/2026-09-10-animations-floating-action-bar.md`](2026-09/2026-09-10-animations-floating-action-bar.md)：定制动画的一排圆按钮从图库卡里搬到页面底部悬浮条——上传常驻、删除选中与取消选择有图才画；虚线上传位按 v2 设计稿改成只在空态出现。

- [`2026-09/2026-09-09-plant-dp-contract-v2.md`](2026-09/2026-09-09-plant-dp-contract-v2.md)：植物 DP 契约改版——116 变植物 id（-1 无植物 / 0..N 涂鸦标识 ID），162 变「弹不弹引导窗」两态且只上报；配套改设备列表门禁、详情页引导窗与无植物界面。

- [`2026-09/2026-09-09-code-review-cleanup.md`](2026-09/2026-09-09-code-review-cleanup.md)：代码审核轮次——移除调试台与体验模式、关闭 S1 明文回落、写请求不再重试、会话 revision 防迟到、搜索页销毁保护；ssh 端补静态自检与 Active 文档口径修复，S2/S3 仍未关闭。

- [`2026-09/2026-09-09-backend-session-expiry.md`](2026-09/2026-09-09-backend-session-expiry.md)：「用一个小时就掉登录」——后端 401/406 以前会 `_clearLocalSession()` 把涂鸦会话一起清掉，改为只清后端会话并留下失效原因与接口日志。

- [`2026-09/2026-09-09-verification-code-phone-format.md`](2026-09/2026-09-09-verification-code-phone-format.md)：发验证码前校验手机号格式——输入框只收 11 位数字，号码不合法时「获取验证码」禁用，三页都补了发送前的兜底校验。

- [`2026-09/2026-09-09-home-pinned-and-pairing-preflight.md`](2026-09/2026-09-09-home-pinned-and-pairing-preflight.md)：家庭 id 按涂鸦 uid 记在本地、每次会话开始钉给原生；配网前先确认家庭再取令牌并加遮罩 loading；空家庭列表在热点上不建家、正常网络下先重查一次。

- [`2026-09/2026-09-09-ota-version-pair.md`](2026-09/2026-09-09-ota-version-pair.md)：OTA 弹窗两个版本号都不对——不是进度弹层改坏的，Android 的 `firmwareVersion` 一直取的是协议版本 `pv`，且两行版本号来源不同；改取 `verSw` 并让 `checkFirmware` 成对返回同一条 OTA 记录的当前/新版本。

- [`2026-09/2026-09-09-relogin-device-list-empty.md`](2026-09/2026-09-09-relogin-device-list-empty.md)：重新登录读不到已绑定设备——设备列表拉取失败不再被吞成「暂无设备」（新增 `deviceLoadError` 与错误态重试），两端桥接的家庭选择从「取第一个」改成稳定规则。

- [`2026-09/2026-09-09-home-plant-image-from-backend.md`](2026-09/2026-09-09-home-plant-image-from-backend.md)：已绑定设备首页正中的图改取后台给该植物配的 `plantImg`，为空或加载失败才回落本地静态图；植物详情页本来就是这个口径。

- [`2026-09/2026-09-09-animation-tips-illustration-clip.md`](2026-09/2026-09-09-animation-tips-illustration-clip.md)：定制动画「提示」卡右下角背景图被 Stack 默认裁剪切掉下沿，改为卡片零内边距 + 文案自带 padding，图按设计稿右边出血、底部齐平。

- [`2026-09/2026-09-09-pairing-ssid-and-standby-inline.md`](2026-09/2026-09-09-pairing-ssid-and-standby-inline.md)：配网页 Wi-Fi 名称改为进页面强制重扫 + 回到前台刷新（不覆盖用户输入），休眠模式由二级页面改为「行为」页内第三张卡。

- [`2026-09/2026-09-08-settings-profile-and-update-batch.md`](2026-09/2026-09-08-settings-profile-and-update-batch.md)：设置/我的/关于十项——分享隐藏、帮助中心搬到设备设置、OTA 进度弹层、App 强制/提示升级链路、昵称与头像修复、列表行高下划线、养护建议改本地中英文案。

- [`2026-09/2026-09-08-i18n-scaffold-and-device-settings-batch.md`](2026-09/2026-09-08-i18n-scaffold-and-device-settings-batch.md)：落地可扩展的多语言框架（简中 + 英文），并完成首页顶栏设备名、自动检测植物独立页、其他设置清理、纪念日校验与样式、休眠模式（DP 151/152）七项。

- [`2026-09/2026-09-08-home-care-advice-carousel.md`](2026-09/2026-09-08-home-care-advice-carousel.md)：首页「今日养护」改为轮播四条状态（107/108/113/115）的养护建议，5 秒一条，并给这批状态文案补中英双语表。

- [`2026-09/2026-09-08-gallery-device-id-and-pairing-cleanup.md`](2026-09/2026-09-08-gallery-device-id-and-pairing-cleanup.md)：设备图库改按涂鸦 `deviceId` 调 `getUserProductImgList`（删掉换 `userProductId` 的前置链路），并清理配网搜索/选择页文案、加 45 秒搜索窗口、修首页指标卡对齐。

- [`2026-09/2026-09-05-release-readiness-review.md`](2026-09/2026-09-05-release-readiness-review.md)：核对客户端安全、会话竞态、配网取消、测试与双端发布准备度，记录性能建议及未验证边界。

- [`2026-08/2026-08-12-ai-context-codegraph-maintenance.md`](2026-08/2026-08-12-ai-context-codegraph-maintenance.md)：建立项目专属 AI 上下文、文档入口与 CodeGraph/历史记录规则。
- [`2026-08/2026-08-12-ui-reference-reaudit-continuation.md`](2026-08/2026-08-12-ui-reference-reaudit-continuation.md)：续作 UI 参考图复核，统一普通页面背景并清理品牌与选中态的复杂手绘图形。
- [`2026-08/2026-08-13-ui-runtime-visual-alignment.md`](2026-08/2026-08-13-ui-runtime-visual-alignment.md)：在 Android 12 模拟器中复核当前构建，校准主要页面位置、状态摘要卡与资源失败占位。
- [`2026-08/2026-08-14-android-split-release-build.md`](2026-08/2026-08-14-android-split-release-build.md)：解除 Flutter ABI 拆分与应用层 ABI 过滤冲突，生成并校验三个 release APK。
- [`2026-08/2026-08-15-demo-navigation-and-app-icons.md`](2026-08/2026-08-15-demo-navigation-and-app-icons.md)：为 UI 演示改造导航（底部菜单、去目录、配网顺序、设备与植物动线），并生成 iOS/Android 全套应用图标。
- [`2026-08/2026-08-17-android-tuya-sdk-integration.md`](2026-08/2026-08-17-android-tuya-sdk-integration.md)：接入 Android Home SDK 7.5.1、Expansion SDK 7.8.0 与安全组件，记录真实模式初始化阻塞及无密钥环境的条件构建。
- [`2026-08/2026-08-17-tuya-android-runnable-config.md`](2026-08/2026-08-17-tuya-android-runnable-config.md)：复核 Android 涂鸦接入配置，放开 debug 签名门禁、把 SDK 初始化移入 Application，并修复桥接回调解析与 OTA、注销调用。
- [`2026-08/2026-08-17-tuya-android-initialization-validation.md`](2026-08/2026-08-17-tuya-android-initialization-validation.md)：修正本地凭据后验证安全组件解密，修复 Expansion SDK 初始化反射签名，并记录 x86_64 模拟器显式 arm64 安装要求。
- [`2026-08/2026-08-17-tuya-android-release-signing-validation.md`](2026-08/2026-08-17-tuya-android-release-signing-validation.md)：恢复本机受控签名材料，构建真实 Tuya 分 ABI Release APK，并核对 APK 实际签名证书与平台登记值一致。
- [`2026-08/2026-08-17-tuya-sdk-debug-console.md`](2026-08/2026-08-17-tuya-sdk-debug-console.md)：在登录页增加涂鸦 SDK 联调入口，直接调用注册与登录并暴露原始失败码，为配网联调准备起点。
- [`2026-08/2026-08-18-tuya-debug-arm64-apk-rebuild.md`](2026-08/2026-08-18-tuya-debug-arm64-apk-rebuild.md)：清理 Flutter 构建产物后重新生成真实涂鸦 arm64 Debug APK，并验证 ABI、签名与 SDK 联调页。
- [`2026-08/2026-08-18-android-local-config-handoff.md`](2026-08/2026-08-18-android-local-config-handoff.md)：区分可进入 Git 的 Android 固定配置与必须本机输入的涂鸦、签名材料，并补充新电脑配置清单和模板。
- [`2026-08/2026-08-18-mock-data-markers.md`](2026-08/2026-08-18-mock-data-markers.md)：核查配网动线只有 Wi-Fi 一步是真实调用，清掉预填的假 Wi-Fi 凭据与配网前置的蓝牙权限，透传配网失败码，并收敛登录页入口。
- [`2026-08/2026-08-18-demo-flow-polish.md`](2026-08/2026-08-18-demo-flow-polish.md)：统一植物目录并接入植物图片，去掉底部 Tab 导航改为头像进入「我的」，并补齐演示数据。
- [`2026-08/2026-08-20-dp-live-updates-and-ios-bridge.md`](2026-08/2026-08-20-dp-live-updates-and-ios-bridge.md)：接入设备 DP 实时上报（Android/iOS 监听 + 事件通道）、报表空态、温标与时间格式跟随、恢复出厂下发 141，并补齐 iOS 桥接与安全组件接入。
- [`2026-08/2026-08-25-app-backend-plant-dp116-calibration.md`](2026-08/2026-08-25-app-backend-plant-dp116-calibration.md)：接入 APP 后端国内账号、用户设备、植物与设备图片，并落实 DP 116 双向同步和水位校准 0–3/取消 5 契约。
- [`2026-08/2026-08-26-pairing-real-sdk-flow.md`](2026-08/2026-08-26-pairing-real-sdk-flow.md)：把联调页验证过的 `scanWifi`、`prepareActivatorToken`、`pairWifiDevice` 接进配网三页，去掉搜索/选择/Wi-Fi 切换里的模拟数据，并把 AP 拆成取令牌与开始配网两步。
- [`2026-09/2026-09-03-pairing-resource-release.md`](2026-09/2026-09-03-pairing-resource-release.md)：复核一键 AP 配网链路，补齐失败/退出/超时时的热点连接与网络绑定释放、`cancelPairing`、令牌复用与 iOS/Android 9 的手动回落路径，并修正过期的测试与文档。
- [`2026-09/2026-09-03-verify-code-login-auto-register.md`](2026-09/2026-09-03-verify-code-login-auto-register.md)：定位「接口-403 邮箱不存在」为手机号未注册，把手机验证码登录补成登录注册一体（同一条验证码补注册），并区分「验证码错误」与「账号不存在」。
- [`2026-09/2026-09-03-pairing-device-discovery-from-raw-scan.md`](2026-09/2026-09-03-pairing-device-discovery-from-raw-scan.md)：把联调页「看到什么就列什么」的扫描逻辑搬进搜索与选择页，放宽热点前缀识别并让 Android `scanWifi` 等一轮新扫描结果。
- [`2026-09/2026-09-04-dialogs-dp-09-03-v2-pages.md`](2026-09/2026-09-04-dialogs-dp-09-03-v2-pages.md)：统一全项目弹窗样式，并入 09-03 功能点表的 151–160，落地纪念日/图库管理/配网进度/时段编辑等 v2 页面并新增 LED 设置页。
- [`2026-09/2026-09-07-device-entry-plant-confirm.md`](2026-09/2026-09-07-device-entry-plant-confirm.md)：并入 09-07 功能点表的 161/162 与占位的 163，落地设备详情页入口的「离线拦截 → 无植物直接添加 → DP 162 植物确认握手」，以及 116+161 同批下发和设置页的自动检测植物开关。
