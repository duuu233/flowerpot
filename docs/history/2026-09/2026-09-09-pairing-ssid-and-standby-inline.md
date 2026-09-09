# 配网页 Wi-Fi 名称刷新，休眠模式改为「行为」页内展开

> 文档类型：Historical Change Record
> 日期：2026-09-09
> 环境：SSH
> 分支与起始版本：main / 992b8f8
> 范围：`lib/src/features/devices/presentation`（配网页、行为页、休眠卡片）、`lib/src/routes`
> 当前权威文档：`AI_CONTEXT.md`、`docs/TUYA_SDK_SETUP.md`

## 背景与目标

1. 反馈「连接Wi-Fi」页显示的 Wi-Fi 名称和手机实际连着的网络不一致。先确认 2026-09-08 的输入框样式改动（`85854f6`）是不是原因，再修。
2. 2026-09-08 的休眠模式（DP 151/152）做成了「行为」页上的一个入口 + 二级页面，产品要求直接在「行为」页里展开，样式和交互模仿同页上面两张卡。

## 变更内容

### 1. 配网页的 Wi-Fi 名称会跟着当前网络刷新

`pairing_page.dart`：

- `initState` 里的首次读取改成 `_loadNetworks(force: true)`：不再复用 `FlowerpotState.wifiScan` 里的旧快照。那份缓存通常是搜索页几分钟前扫的，用户之后很可能已经换过网络。
- 页面实现 `WidgetsBindingObserver`，`didChangeAppLifecycleState` 收到 `resumed` 时再强制读一次。用户在这一页最常见的动作就是切到系统设置换 Wi-Fi 再回来（手动连热点的路径更是必须这么做）。配网进行中（`_pairing`）不刷新：那时手机是故意挂在设备热点上的。
- 新增 `_autoFilledSsid` 记住上次自动填进去的名字。刷新只在输入框为空、或内容仍等于上次自动填入值时才覆盖；用户自己打过字或从「切换」里选过的名称一律不动。重试带进来的 `arguments.request.ssid` 同样不会被覆盖。
- 原有的过滤条件不变：只用真实扫描结果，5 GHz（`currentIs24g == false`）和设备热点仍然不会被填进去。

### 2. 休眠模式从二级页面改为「行为」页内的第三张卡

- 新增 `presentation/widgets/standby_settings_card.dart`：`StandbySettingsCard` 复用 `BehaviorScheduleCard` 的版式（上半标题 + 状态 + 开关，分隔线，下半说明 + 可点行 `BehaviorTimeRow`），可点行是「延迟时间」；`showStandbyDelayDialog` 是照 `showScheduleSlotDialog` 外壳做的滚轮弹窗（时 / 分两根，沿用原页面的越界回拨逻辑），`standbyDelayLabel` 负责行内取值文案（不足一小时只写分钟）。
- `behavior_settings_page.dart`：删掉 `AppSettingsTile` 入口，换成这张卡；新增 `_setStandbyEnabled`（DP 151 即时下发）与 `_editStandbyDelay`（弹窗返回后写 DP 152，取值没变就不发），用独立的 `_standbyUpdating` 标记，不和午休 / 夜间的在途状态互锁。
- 删除 `standby_settings_page.dart` 以及 `AppRoutes.standbySettings` 路由与其分发分支——内容进了行为页之后它不可达。

## 关键决策

- 「名称不一致」不是 2026-09-08 那次样式改动引起的：`85854f6` 只是把两格输入抽成 `_CredentialInput`，控制器和取值来源都没变。真正的原因是首屏那次填充**只做一次、且只在输入框为空时才做**，配上一份可能过期的全局扫描缓存。因此修的是刷新时机，不是样式。
- 刷新以「用户没动过」为前提，宁可少改也不覆盖用户输入：Wi-Fi 名称错了顶多重填，把用户选好的网络冲掉会直接让配网发到错的网络上。
- 休眠的延迟时间保持「弹窗里保存才下发」，没有跟着滚轮实时发 DP——滚动一格发一条只会把指令堆在链路上。原页面底部那个整页「保存」按钮随页面一起去掉了，保存动作收进弹窗。

## 外部操作

无。

## 验证结果

- 本机（SSH 开发机）**没有 Flutter/Dart SDK**，`flutter analyze` 与 `flutter test` 都没有执行。改动只经过人工通读与静态检查（引用、导入、Key、l10n 词条均已核对：删掉 `AppRoutes`/`AppL10n` 引用后行为页不再残留未使用导入；`lib` 内已无 `standbySettings`/`StandbySettingsPage` 引用）。
- 测试代码已同步但同样未运行：
  - `test/features/devices/pairing_page_test.dart` 新增三例——缓存过期时进页面重扫、回到前台刷新、用户选过的名称不被覆盖；helper 增加 `primeScan` 用来先把缓存写脏。
  - `test/features/devices/standby_settings_page_test.dart` 删除，改为 `standby_settings_card_test.dart`：行为页上直接可见开关与延迟时间、开关写 DP 151、弹窗保存写 DP 152、取消不写、原值保存不写、设备不存在时的错误态。

## 未完成项与风险

- **必须在有 Flutter SDK 的机器上跑一遍 `flutter analyze` 和 `flutter test`**。其中生命周期用例用 `tester.binding.handleAppLifecycleStateChanged` 走了 inactive → hidden → paused → hidden → inactive → resumed 一整轮，不同 SDK 版本对状态迁移的断言不同，若报错优先调这一处；延迟弹窗用例靠拖动滚轮改值，只断言「写了 152 且不再是 30」，没有钉死落在哪一格。
- 真机未验证：换网络后回到前台是否确实刷新、Android 扫描节流（每两分钟几次）下 `current` 是否仍然准确（桥接里 `current` 取自 `connectionInfo`，不依赖扫描结果，理论上节流也准），以及休眠卡在小屏上的高度表现。
- 休眠二级页面已删除，若后续要恢复，从本次提交的父版本取 `standby_settings_page.dart` 与路由两处即可。
