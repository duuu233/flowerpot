# 配网链路核查与模拟数据标识

> 文档类型：Historical Change Record
> 日期：2026-08-18
> 环境：远程 SSH 工作树（本机无 Flutter/Dart SDK）
> 分支与起始版本：main / 32b872b
> 范围：配网动线核查、`core/config`、`design_system` 模拟数据标识、约 20 个页面
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`

## 背景与目标

真实账号注册完成后要开始真机配网联调。先核查配网是否真的接了蓝牙设备搜索，再把界面上所有不是真实 SDK 数据的内容标出来，避免占位值在联调时被当成设备返回。

## 核查结论

配网动线里只有最后一步是真的：

- `DeviceSearchPage` 是 4 秒循环的雷达动画加一个 2 秒定时器，到点直接跳转，没有任何扫描调用。
- `DeviceSelectionPage` 的三台设备与信号格写死在页面里，「连接」是 600ms 延时，选中的名字只当文案传给下一页，不进入 `PairingRequest`。
- `PairingPage` 调用 `pairWifiDevice`，桥接使用 `getActivatorToken` + `newMultiActivator`，模式固定 `TY_AP`。
- Kotlin 桥接与 `TuyaRepository` 都没有设备发现接口；Manifest 里的蓝牙权限是涂鸦 Activator 需要的，不代表存在扫描能力。

## 变更内容

- 新增 `lib/src/design_system/widgets/feedback/mock_data_marker.dart`：`MockDataBanner`（整页或整块模拟）、`MockDataBadge`（单值模拟）、`LiveDataBadge`（确实走桥接），由 `DebugToolsConfig` 统一开关，release 未显式开启时完全不渲染。
- 把 `DebugToolsConfig` 从 `features/devtools/` 移到 `lib/src/core/config/debug_tools_config.dart`，避免 `design_system` 反向依赖 feature；同步更新 `AppRoutes`、登录页与「我的」页的引用。
- 配网三页加标识：搜索页说明雷达是动画、选择页说明设备列表写死、Wi-Fi 弹窗说明网络名是示例，Wi-Fi 页对「已连接 X」加「模拟设备名」、对开始配网一步加「真实 SDK · AP 配网」。
- 配网模式改为可切换：`PairingRequest.mode` 由页面状态提供，默认仍是 `ap`，debug 构建在「真实 SDK」标识旁多一个 AP/EZ 选择器（`Key('pairing-mode-switch')`），从失败页返回时沿用上一次的模式。release 不显示该选择器，行为与之前一致。
- `AppShell` 在 `usingMockBackend` 为真时置顶横幅，区分「体验模式切换」与「未启用 TUYA_ENABLED」两种来源。
- 其余标识：首页养护文案、设备列表植物占位、设备信息占位字段、五个状态页、设备设置与其他设置、植物选择与详情、动画、个人信息、账号与安全、帮助、协议、关于、登录页「体验模式」。
- 修正 `BatteryTrendChartCard` 的标题：原本写成「相对湿度变化」，实际画的是电量。
- `MinePageModel` 的意见反馈邮箱标为占位。

## 关键决策

- **清掉配网页预填的 Wi-Fi 凭据**。`ssid` 原本预填 `Home_2.4G`、密码预填 `12345678`，而这两个值会原样进入真实的 `pairWifiDevice` 调用。只有从失败页返回重试时才回填上一次输入。
- **把 SSID 输入框从 `readOnly` 改为可编辑**。原先只能从写死的网络列表里选，真机上没有办法输入自己的 2.4G 名称。「切换」弹窗保留，但明确标注是示例列表，并过滤掉空的当前网络避免出现空行。
- 标识只做提示，不改动模拟行为本身：假的雷达动画和 600ms 连接延时保留，因为它们不参与真实调用；只有会流入 SDK 的假数据才改。
- 标识与 SDK 联调入口共用 `DebugToolsConfig`，不引入第二个开关。
- 设备列表页把 `ListView` 包进 `Column` + `Expanded`，而不是把横幅塞成第 0 个 item，避免关闭标识时留下一个空行。

## 外部操作

无。未修改涂鸦平台配置，未接触本机密钥、安全组件与签名材料。

## 验证结果

- 本环境没有 Flutter/Dart，`dart format`、`flutter analyze`、`flutter test` 均未执行。改动经过人工核对与一次独立静态复查（逐个核对组件参数、`const` 正确性、括号与控件树平衡、约束边界、受影响测试断言）。
- 复查未发现编译错误，但发现并已修正六个问题：
  - 设备列表横幅在滚动区之外，被透明 AppBar 盖住 → 顶部留出 `kToolbarHeight`。
  - `AppShell` 只给横幅套了 `SafeArea`，Tab 页会二次叠加状态栏高度 → 用 `MediaQuery.removePadding` 去掉重复内边距。
  - 意见反馈行的邮箱加「（占位）」后把「意见反馈」标题挤成换行 → 改为「待配置」，弹窗文案同步改成「意见反馈渠道尚未配置」。
  - Wi-Fi 名称输入框的提示语超出可用宽度被省略 → 缩短为「输入 2.4G 名称」。
  - 搜索页 320dp 下底部横幅可能与说明文字重叠 → 缩短文案并上移雷达区。
  - 失败页「重试」没有回传 `PairingRequest`，在取消预填后会得到一张空表单 → 回传 `PairingArguments`。
- 因此没有任何运行时结论；真机验证与静态检查必须在带 SDK 的开发机上完成。

## 未完成项与风险

- 待在带 SDK 的机器上执行 `dart format lib test`、`flutter analyze`、`flutter test`。受影响的测试已同步更新：配网页与整体流程测试改为先输入 Wi-Fi 名称和密码，Wi-Fi 弹窗改为初始无选中项，电量图表标题断言改为「电池电量变化」，搜索页与选择页新增标识断言。
- 设备发现仍未实现。要做真实搜索需要新增 `TuyaRepository` 契约、桥接扫描接口与事件通道，并替换搜索页与选择页。
- 配网模式仍固定 `TY_AP`。EZ 快连需要改 `PairingPage` 的 `mode` 或提供选择。
- 仍有未标注的占位：报表页与 `AppSettingsPage` 目前无入口、`core/network` 未被使用，这三处没有加标识；`FlowerpotState` 里预置的两条内建动画不渲染但也未清理。
- Wi-Fi 选择弹窗是固定 360 高度、只有列表可滚动的结构。加入提示后非滚动区更高，约 1.8 倍字号会溢出。这是既有结构问题，本次只把提示文案压到一行；彻底解决需要让弹窗按内容自适应高度。
- `mine_page_test` 自己构造 `MinePageModel`，因此没有任何测试覆盖 `MinePageModel.fromUser` 的实际取值。
- 真实模式下 `PlantCatalog.byId` 的 `orElse` 会把没有 `plantId` 的设备统一显示为植物库第一项；已在设备列表与植物页加标识，但根因仍需在植物绑定接通后解决。

## 回滚或恢复

删除 `lib/src/design_system/widgets/feedback/mock_data_marker.dart` 与其导出，回退各页面的标识插入即可恢复外观。配网页的凭据预填与 `readOnly` 属于行为变更，回退会重新引入向真实 SDK 发送占位 Wi-Fi 凭据的风险，不建议单独回退。
