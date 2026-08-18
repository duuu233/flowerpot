# 配网链路核查、假数据清理与登录页收敛

> 文档类型：Historical Change Record
> 日期：2026-08-18
> 环境：远程 SSH 工作树（本机无 Flutter/Dart SDK）
> 分支与起始版本：main / 32b872b，中途由用户提交 c21ac17
> 范围：配网动线核查、`core/config`、配网页与桥接权限、SDK 联调页、登录页入口
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`

## 背景与目标

真实账号注册完成后开始真机配网联调。先核查配网是否真的接了设备搜索，再清掉会污染真实调用的假数据，最后按演示需要收敛登录页入口。

## 核查结论

配网动线里只有最后一步是真的：

- `DeviceSearchPage` 是雷达动画加一个 2 秒定时器，到点直接跳转，没有任何扫描调用。
- `DeviceSelectionPage` 的三台设备与信号格写死在页面里，「连接」是 600ms 延时，选中的名字只当文案传给下一页，不进入 `PairingRequest`。
- `PairingPage` 调用 `pairWifiDevice`，桥接使用 `getActivatorToken` + `newMultiActivator`。
- 桥接与 `TuyaRepository` 都没有设备发现接口。随后产品确认设备**只支持 2.4GHz Wi-Fi 配网、没有蓝牙配网**，因此不应该去补 BLE 扫描：EZ/AP 配网本来就没有「先扫描再选设备」这一步。

## 变更内容

- **配网页停止预填假凭据**：`ssid` 原本预填 `Home_2.4G`、密码预填 `12345678`，这两个值会原样进入真实的 `pairWifiDevice`。现在只有从失败页重试时才回填。
- **SSID 输入框从 `readOnly` 改为可编辑**：原先只能从写死的网络列表里选，真机上无法输入自己的 2.4G 名称。「切换」弹窗保留，并过滤掉空的当前网络避免出现空行。
- **配网模式可切换**：`PairingRequest.mode` 由页面状态提供，默认 `ap`，debug 构建显示 AP/EZ 选择器（`Key('pairing-mode-switch')`），从失败页返回时沿用上一次的模式。release 不显示该选择器。
- **桥接配网权限去掉蓝牙**：原实现在 Android 12+ 要求 `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` 必须授予，用户在蓝牙弹窗点拒绝会让配网直接返回 `permission_denied`，而设备根本用不到蓝牙。现在 API 33 以下只要求 `ACCESS_FINE_LOCATION`，API 33 及以上要求 `NEARBY_WIFI_DEVICES` 并附带申请（不强制）定位；只有必需项被拒才失败。Manifest 保留蓝牙声明不动，涂鸦 SDK 自身可能合并同名权限，本机无法构建验证。
- **失败原因不再被丢弃**：新增 `PairingFailureArguments`，把 `ActionResult` 的 `code` 与 `message` 带到配网失败页，debug 构建在副标题显示 `[code] message`；release 仍只显示原文案。路由兼容旧的 `PairingRequest` 参数。失败页「重试」补上回传上一次请求，否则取消预填后会得到一张空表单。
- **SDK 联调页新增「配网」一节**：Wi-Fi 名称、密码、EZ/AP 模式加一个直接调用 `pairWifiDevice` 的按钮，结果连同原始错误码写进调用日志，不跳转失败页，便于连续重试。
- **蓝牙口径文案全部纠正**：搜索页提示、帮助中心两条 FAQ、隐私政策的权限说明改为 2.4GHz Wi-Fi 口径。
- **登录页入口收敛**（`lib/src/features/auth/login_entry_config.dart`）：隐藏密码登录与支付宝快捷登录，保留微信入口与「涂鸦 SDK 联调」入口；手机验证码登录只要求两个输入框非空，真实 SDK 拒绝时退回演示会话并提示「未通过涂鸦验证，已进入演示会话」。每个入口都是一个常量开关，平台参数到位后改回 `true` 即可。
- 修正 `BatteryTrendChartCard` 的标题：原本写成「相对湿度变化」，实际画的是电量。
- `DebugToolsConfig` 从 `features/devtools/` 移到 `lib/src/core/config/`，避免 `design_system` 与其他 feature 反向依赖。

## 关于模拟数据标识

本次曾在约 20 个页面加过 `MockDataBanner` / `MockDataBadge` / `LiveDataBadge` 标识与说明文案（提交于 c21ac17），随后按用户要求全部撤除：标识组件、导出、用例与文档章节都已删除，页面回到标注前的形态。上面列出的行为修复不属于标识，全部保留。

判断界面上的值是否真实，现在只能回到源码：设备与传感器值来自 `TuyaRepository`，养护建议、坐标轴刻度、植物库、帮助中心、协议正文、关于页版本号等始终是写死的文案。真实链路以 SDK 联调页的调用日志为准。

## 配网崩溃与原生异步防护

真机点「开始配网」后进程直接退出。原因在桥接的异步结构，不是某一次调用失败：

- `handle()` 的 `try/catch` 只覆盖同步部分。配网链路是 `queryHomeList` 回调 → `getActivatorToken` 回调 → `startActivator`，后两段都跑在 SDK 的后台线程上、已经脱离那个 `try`。`startActivator` 全靠反射（类名、枚举、方法签名），任何一处对不上就抛异常到线程顶层，直接杀进程。其中 `enumConstants.first { it.name == modeName }` 最危险：SDK 换了枚举命名就必抛 `NoSuchElementException`。
- activator 在后台线程创建并启动。涂鸦的 activator 内部要注册 Handler 与广播接收器，没有 Looper 的线程上会抛 `Can't create handler inside thread that has not called Looper.prepare()`。
- 同一次调用可能回复两次（先 error 后 success），Flutter 引擎对重复回复会抛异常。

处理：

- 新增 `SingleResult` 包装，保证每次调用只回复一次；在 `setMethodCallHandler` 入口就包好，权限重试路径也覆盖到。
- 新增 `onMain(result) { … }`：把回调体切回主线程并捕获异常，失败转成错误码返回而不是抛出。家庭查询、建家、设备列表、令牌回调、配网结果回调全部改走它。
- 配网模式枚举查找从 `first` 改为 `firstOrNull`，找不到时抛出带「可用枚举名列表」的说明，`describe` 会把它转成 `native_error` 显示在联调页日志里。

## 配网 Builder 类名解析

上面的防护生效后，真机不再闪退，改为在联调页报出干净的错误：

```
com.thingclips.smart.sdk.builder.ActivatorBuilder, com.thingclips.smart.sdk.builder.ThingActivatorBuilder
```

这是 `firstClass()` 的 `ClassNotFoundException(names.joinToString())`，意思是这两个候选全限定名在 APK 里都不存在。注意这条报错出现的位置已经很靠后：`startActivator` 只在 `getActivatorToken` 成功回调里执行，所以 SDK 初始化、登录会话、家庭 ID、`getActivatorInstance()`、向云端换配网令牌**全部已经跑通**，卡住的仅仅是最后一步取 Builder 类。涂鸦在 7.x 内部挪过这个类的包名（`com.thingclips.smart.sdk.builder` 与 `com.thingclips.smart.home.sdk.builder` 都出现过），而 `ActivatorModelEnum` 留在 `com.thingclips.smart.sdk.enums`，当初照抄枚举的包名去拼 Builder 的包名就错了。

不再补候选名单，改为从方法签名反查类型（与 `invokeWithCallback` 取回调接口同一套做法）：

- 新增 `activatorFactory(activatorApi)`：在 activator 实例上找 `newMultiActivator` / `newActivator` 里参数唯一且类型名以 `Builder` 结尾的那个，优先 `newMultiActivator`；Builder 类型直接取 `parameterTypes.single()`，全限定名不再出现在代码里。
- 新增 `activatorMode(builder, name)`：模式枚举取 `setActivatorModel` 的参数类型，再按常量名找 `TY_EZ` / `TY_AP`，枚举包名同样不再硬编码。
- 两处解析失败都抛带清单的异常——前者附 `describeFactories()` 列出该类所有 `new*` 方法签名，后者列出实际枚举常量名——落到联调页日志里就是可直接行动的信息，不用再翻 AAR。

本机没有涂鸦 AAR（构建在 Windows 上），无法离线确认真实类名，这也是选择签名反查而不是再猜一个名字的直接原因。

## 关键决策

- 只改会流入真实 SDK 的假数据（预填 Wi-Fi 凭据、只读输入框），不动纯展示性的模拟行为（雷达动画、600ms 假连接）。
- 登录页放开为「非空即可登录」时仍先走一次真实登录，真实账号因此保留真实会话，只有被拒才退回演示会话，并明确提示。
- 配网模式选择器只在 debug 构建出现，不改产品 UI。
- 设备发现不做 BLE 扫描；搜索页与选择页建议后续改成「确认设备已进入配网状态」的引导页。

## 外部操作

无。未修改涂鸦平台配置，未接触本机密钥、安全组件与签名材料。

## 验证结果

- 本环境没有 Flutter/Dart，`dart format`、`flutter analyze`、`flutter test` 均未执行。改动经过人工核对与两次独立静态复查。
- 复查在标识版本上发现并修正过六个问题（横幅被 AppBar 遮挡、`AppShell` 二次叠加状态栏内边距、意见反馈行文字换行、SSID 提示语超宽、搜索页 320dp 重叠、失败页重试丢失凭据）。其中前五个随标识一起撤除，失败页重试的修复保留。
- 没有任何运行时结论；真机验证与静态检查必须在带 SDK 的开发机上完成。

## 未完成项与风险

- 待在带 SDK 的机器上执行 `dart format lib test`、`flutter analyze`、`flutter test`。受影响的测试已同步：配网测试改为先输入 Wi-Fi 名称和密码、Wi-Fi 弹窗初始无选中项、断言失败页拿到 `code`/`message`、电量图表标题改为「电池电量变化」、登录页断言密码登录与支付宝入口不存在并新增三条登录用例。
- 设备发现仍未实现，配网前两页仍是模拟动线。
- 配网默认模式仍是 AP，正式默认值需要产品确认。
- 登录页「非空即可登录」会让错误的验证码静默进入演示会话，演示期可接受，正式发布前必须关掉 `LoginEntryConfig.acceptAnyVerificationCode`。
- Android Manifest 仍声明蓝牙权限，是否移除需要在能构建的机器上核对合并后的 Manifest。

## 回滚或恢复

各项均为独立改动，可分别回退。配网页的凭据预填与 `readOnly` 属于安全性修复，回退会重新引入向真实 SDK 发送占位 Wi-Fi 凭据的风险，不建议单独回退。登录页入口只需修改 `LoginEntryConfig` 中的常量，无需改页面代码。
