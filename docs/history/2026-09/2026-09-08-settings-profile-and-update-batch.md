# 设置/我的/关于十项：分享隐藏、帮助中心搬家、OTA 进度弹层、App 升级检测与养护建议本地化

> 文档类型：Historical Change Record
> 日期：2026-09-08
> 环境：SSH 开发机（无 Flutter/Dart 工具链）
> 分支与起始版本：main / 2903cf7
> 范围：设备设置 / 其他设置 / 状态详情四页、我的 / 关于 / 意见反馈、`AppAvatar`、`AppShell`、`TuyaStatusCopy`、新增两个弹层组件与对应测试
> 当前权威文档：`AI_CONTEXT.md`

## 背景与目标

产品本轮十条，覆盖设置页入口调整、我的页数据与样式问题、App 升级链路补全、状态详情养护建议改本地文案，以及一条「选择植物没下发 161」的排查。

## 变更内容

1. **分享入口先隐藏**：设备设置页右上角的分享按钮由常量 `_shareEntryEnabled = false` 关掉，`_share` 与按钮代码都留着，后期恢复只需翻开关。
2. **帮助中心搬到设备设置页**：`MineMenuKind.helpCenter` 从「我的」删除，`DeviceSettingsMenuKind.helpCenter` 新增到设备设置的功能列表（内容本来就是设备用法问题）。
3. **OTA 进度弹层**：新增 `showOtaProgressDialog`，点「立即更新」发起升级后盖在页面上，进度条 + 百分比读 `FlowerpotState.otaProgressFor`，升级中不可关闭，成功/失败才出「知道了」。
4. **LED 与自动检测植物**：`DeviceToggleSettingsCard` 的标题去掉加粗（震动/触觉/自动检测植物共用这张卡，一并跟随）；`DeviceSettingSymbol` 新增 `led`，LED 页不再和「显示」共用 `brightness_symbol`。**没有新素材**：LED 与自动检测植物暂时用 Material 矢量图标画在轨道插画里（`_iconFor`），UI 出正式素材后在 `_assetFor` 补一行即可。
5. **意见反馈**：邮箱改读后台「基础信息配置」（`/Client/Basic/getBasicData` → `BackendBasicData.contact`），行尾箭头换成复制图标，点一下复制邮箱；后台没配就提示「后台还没有配置平台邮箱」。
6. **关于页与升级链路**：去掉「版本说明」整行；「检查更新」改为当场再查一次并弹升级弹窗；新增 `showAppUpdateDialog`（强制升级不可取消、提示升级可「稍后再说」）；`AppShell` 在 App 打开后检测一次，命中强制升级立刻弹窗；「我的 → 关于YSplanter」在有新版本时点红点。同时按 swagger 的 `AppVersionConApiOutput` 修正了字段解析：`compulsory`(1=强制) / `downloadPath` / `upgradeTips`，此前用的 `isForce`/`downloadUrl`/`updateContent` 都是字段名未定时的猜测。
7. **昵称与头像**：`MinePage` 改为有状态组件，进页面就 `refreshUserInfo()`——此前只有「个人信息」页刷新，所以我的页显示「用户」、进个人信息再退回来才对；`AppAvatar` 改为在图片**加载失败**时退回占位图（`CircleAvatar` 的 child 只在没有 foregroundImage 时显示，加载失败就只剩一个空底色，这正是「返回列表页后左上角入口不见了」的原因）。
8. **列表行高与下划线**：「我的」功能列表行高 48 → 61、设备设置功能列表 46 → 58，两处都打开 `AppSettingsList` 的分隔线并把缩进对齐各自的内容边距，与「账号与安全」（忘记密码所在的那张卡）一致。
9. **养护建议改本地文案**：`DeviceStatusCopy` 增加第三段 `advice`，12 条中文按产品给稿写入，另配 12 条英文；需水/光照/温度/湿度四个状态详情页的建议改读这张表并跟随界面语言，页面模型新增 `language` 入参。原来每页各写一段 switch，温度页写的还是「适宜温度范围…」。
10. **选择植物没下发 161**：见下方「关键决策」。

## 关键决策

- **161 这条是数据问题，不是 App 解析问题**：拉了 `https://api.yikaltd.com/v2/api-docs` 核对，`ClientProductPlantApiOut`（`/Client/Product/getProductPlantList` 的行）**有** `categoryType`（1 水培 / 2 适中 / 3 耐旱），App 也确实读的是 `row['categoryType']`（`_plant`），选植物页用的就是这个列表。所以只有后台该行没填分类（或值不在 1–3）才会走到「未下发 161」。本轮把提示改成点名字段：「该植物在后台没有配置分类（categoryType），未下发 161」，方便直接回后台核对。**注意 `ClientProductPlantDetailApiOut` 里没有 `categoryType`**，以后若改成走详情接口会丢分类。
- **`_debugPlantIdentifier = '17'` 仍然写死**（`app_backend_repository.dart`）：联调期把下发给设备的 DP 116 标识统一写成冷水花的 `17`。后台把 `tuYaRemark` 补齐后必须改回 `null`，否则选任何植物设备都当成冷水花。本轮没动它——改了会让还没填标识符的植物直接失败，需要产品确认后台是否已全部补齐。
- 「立即更新」目前是把下载地址复制到剪贴板：项目没有 `url_launcher` 依赖，加它要跑 `flutter pub get`，本机没有 SDK，改 pubspec 会让别人拉下来直接构建失败。
- 版本号仍是 `AboutPageModel.current()` 里写死的 `1.0.0`（没有 `package_info_plus`），发版前需要换成包信息，否则升级判定永远拿这个值去比。

## 外部操作

只读拉取 `https://api.yikaltd.com/v2/api-docs`（swagger 契约），未调用任何写接口。

## 验证结果

- **本机没有 Flutter / Dart 工具链，`flutter analyze` 与 `flutter test` 都没跑**，只做静态复核，不宣称通过。
- 同步修改的测试：`mine_page_test`（帮助中心已移出、邮箱改为 fixture）、`about_page_test`（版本说明下线、检查更新不再只弹 toast）。
- 未补测试：OTA 进度弹层、升级弹窗、头像加载失败回退、昵称刷新——这些都要驱动异步事件或图片加载失败，没有 SDK 无法确认写法。

## 未完成项与风险

1. 全套 analyze/test 待补跑；本轮改动面很大（10 项 + 2 个新弹层）。
2. LED 与自动检测植物的插画是矢量图标占位，等 UI 出正式素材。
3. 「立即更新」不能直接打开下载页；强制升级弹窗在没有 `url_launcher` 时只能复制链接。
4. 161 那条需要后台核对冷水花的分类字段；`_debugPlantIdentifier` 的写死也要产品确认后再撤。
5. 帮助中心落在「设备设置」页（设备详情入口），若产品指的是「更多设备信息」那一页，挪一行即可。

## 回滚或恢复

十项互相独立，可按文件粒度 revert；两个新弹层各自独立成文件。
