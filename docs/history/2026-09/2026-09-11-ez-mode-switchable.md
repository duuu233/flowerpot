# 2026-09-11 加入 EZ 快连配网（可在页面上与 AP 切换）

## 产品要求

> 那你改一个 EZ 配网模式我测试一下吧，原来的也备份下，不行就切回 AP 模式。

以及顺带的追问「你知道智能生活 APP 的配网模式是什么模式吗」。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `898841b`。

## 先回答「智能生活用的是什么模式」

智能生活**两种都支持**，但对 Wi-Fi 设备**默认先走 EZ（快连）**；AP 是它的备选
（界面上「指示灯慢闪 / AP 模式」那条，选了才引导用户去系统 Wi-Fi 连设备热点）。

产品自己在 iOS 上的观察正是 EZ：「**选择了一下 WIFI，是 WIFI 不是设备**，然后输入了 wifi
密码就去配网了」——不选设备、不连热点、直接广播凭据。这解释了「从始至终没有系统框」。
（AP 模式下 iOS 也会弹一次「加入Wi-Fi网络?」。）

## 改动

### 新增 `lib/src/tuya/pairing_mode.dart`

`enum PairingMode { ez, ap }`（带 `label` / `hint` / `wire`）+ `PairingModeSwitch.current`
运行时开关，**默认 `ez`**。做成运行时开关而不是编译常量，是因为产品要在**同一个包**里把两种
都测一遍再定。注释里写明：定稿后删掉开关、只留选中的那一种。

### `lib/src/state.dart` — 新增 `pairViaEz`

```
connectingDevice: 取令牌（EZ 全程有外网，现取即可）
sendingWifi:      _pairInternal(PairingRequest(mode: 'ez')) → 原生 pairWifiDevice
connectingCloud:  由 _pairInternal 收尾
```

**全程不调 `_joinHotspotForPairing`**——这正是它零系统 UI 的原因。失败消息同样带各步耗时，
并附「手机在「xxx」」：EZ 失败时这一项最要紧，手机不在目标网络上就一定收不到广播。
文档注释里写清两条前置（手机必须在目标 2.4GHz 网络上；固件必须开了 EZ）。

原生侧**不需要改**：`pairWifi` / `activatorFactory` 早就有 EZ 分支
（`EZ_MODE_NAMES` + `newEZWifiConfigDevActivator`），连注释都写着「EZ 全程连在路由器上，
走的就是下面这条回落路径，所以 EZ 不需要用户先点获取配网令牌」。

### `lib/src/features/devices/presentation/pairing_page.dart`

- 「连接 Wi-Fi」页加一行**测试开关** `_PairingModeSelector`（`pairing-mode-selector`，
  两颗 ChoiceChip `pairing-mode-ez` / `pairing-mode-ap`，下面一行说明当前模式的代价）。
- `_startPairing` 按开关分支：EZ → `pairViaEz`；AP → `pairViaHotspot`（原样不动）。

### `lib/src/features/devices/presentation/device_search_page.dart`

`_connectAndOpen` 在 EZ 模式下**跳过连热点**，只选定设备 + 跳页；副标题也跟着换
（EZ 不提「系统会弹确认框」）。AP 模式行为不变。

> 说明：EZ 本身不需要设备热点，但搜索页仍然用「扫到热点」作为**设备处于可配网状态**的证据，
> 所以列表照旧有用。

### 测试

- `MockTuyaRepository` 加 `hotspotJoins` 计数——EZ 模式下应当**恒为 0**。
- `pairing_page_test.dart` 用 `setUp` / `tearDown` **把模式钉成 AP**：该文件的配网用例都是
  按 AP 那条路写的（令牌、连热点、下发凭据），不能让默认值变动改掉它们的含义。
- 新增一条 EZ 用例：断言 `hotspotJoins == 0`、`tokenCalls == 1`（EZ 现取令牌）、
  `pairCalls == 1`、跳成功页，以及开关在页面上可见。

### 文档

`PRODUCT_RULES.md` **1.1 整节重写**为「EZ 快连（在测）+ AP 热点（备用，可随时切回）」，
并**修正旧口径**：此前写的「永远不考虑 EZ，设备不支持」来自设备开发的「**没使用** EZ」——
「没使用」≠「不能用」，已改为「进入测试」。桥接层的 EZ 路径从此不再标注为死代码。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链。按 §6 清单自检：

1. 五个改动文件 + 一个新文件括号配平。
2. 新符号来源与引用：`PairingMode` / `PairingModeSwitch`（新文件 + 两个页面）、
   `pairViaEz`（state + pairing_page）、`hotspotJoins`（mock + 新用例）均无悬空引用。
3. 新文件在两个页面都已 import。
4. `ChoiceChip` / `ValueChanged` 来自已 import 的 `material.dart`。
5. 修掉了一次脚本替换留下的孤立 `@override`（落在 `hotspotJoins` 字段上，会编译失败）——
   **这是同一个坑第二次，以后用脚本插字段时先确认前一行不是 `@override`。**
6. 没有引入新语法糖。

## 遗留

- **真机测 EZ**：① 全程应当**没有任何系统弹框**；② 配网能否成功。
  - 成 ⇒ 这就是产品要的流程，之后删掉开关、固定 EZ。
  - 不成（多半是 `1006 out of time`）⇒ 在页面上切回 AP 验证对照，并把失败消息整行带回来
    （末尾有「手机在「xxx」」）。**EZ 失败最可能的两个原因**：手机不在要配的那个 2.4GHz
    网络上；设备固件没开 EZ——后者需要设备团队确认。
- 测试前请确认：手机连的就是要配给设备的那个 **2.4GHz** Wi-Fi（不是 5GHz）。
