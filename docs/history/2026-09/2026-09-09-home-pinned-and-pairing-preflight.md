# 家庭固定到账号，配网前先把家庭确认下来

> 文档类型：Historical Change Record
> 日期：2026-09-09
> 环境：SSH
> 分支与起始版本：main / b9f7dba
> 范围：`FlowerpotState` 会话与配网准备、配网页、`TuyaRepository`、Android / iOS 桥接的家庭解析
> 当前权威文档：`AI_CONTEXT.md`、`docs/TUYA_SDK_SETUP.md`

## 背景与目标

承接同日 `2026-09-09-relogin-device-list-empty.md`。要求两条：

1. **家庭 id 固定传给涂鸦**——家庭属于涂鸦账号，既不依赖设备也不依赖 APP 后端，不该每次登录重新从家庭列表里挑。
2. **配网前加 loading**——手机连上设备热点后没有外网，此时查家庭会误判；等这一步确认完成再走后续配网。

后端是否返回了不同账号，本轮不查。

## 变更内容

### 家庭固定

- `TuyaRepository` 新增 `useHome(String homeId)`（桥接方法 `setHomeId`）：Android 直接写 `homeId` 字段，iOS 用它构造 `currentHome`；给的值不可用时按「没记过」处理，退回正常解析。
- `FlowerpotState` 按**涂鸦 uid** 把家庭记在 `SharedPreferences`（键 `tuyaHome:<uid>`）：
  - 新增 `_startSession()`，把「会话换代 → 钉家庭 → 拉设备列表」串成一处，登录、注册、恢复会话、会话自检四个入口统一走它（顺序不能反：家庭没钉住就拉列表等于又让原生自己挑一次）。
  - 每次成功读到设备列表后，把实际用上的家庭写回本地（`_rememberHome`）。
- 原生的挑选规则（先挑带设备的家庭、再按 homeId 最小）保留，作为「本地还没记过」时的第一次解析。

### 配网前的准备与 loading

- `FlowerpotState.prepareForPairing()`：先 `currentHomeId()` 把家庭确认下来、记住，再取配网令牌；两步都在手机还连着路由器时完成。装着旧原生包、没有 `currentHomeId` 方法的机器（`sdk_unavailable`）不拦路，因为取令牌本身也会解析家庭。
- 配网页 `_pair()` 先跑这一步，期间盖一层遮罩（`Key('pairing-preparing')`，`AppLoading`「正在确认账号与家庭，请保持当前 Wi-Fi…」，`AbsorbPointer` 挡住误触）；失败就弹错误、**根本不去碰设备热点**。

### 空家庭列表不再随手建家

- Android `withHome` 拆出 `queryHome(retry:)`，空列表按危险程度三分：进程正绑在设备热点上（`boundNetwork != null`）→ 直接报 `home_offline`，绝不建家；还有重试机会 → 再查一次挡掉瞬时空返回；两次都空且在正常网络上 → 才认为账号确实没有家庭，建一个。
- iOS `queryHome(retry:)` 同样先重查一次再走建家；iOS 侧另外补上了缺失的 `currentHomeId` 分支（之前这个方法在 iOS 上根本没实现，Dart 调用会被映射成 `sdk_unavailable`）。

## 关键决策

- 固定值按 **uid** 存而不是全局一份：同一台手机换账号登录时不能互相污染。
- 准备阶段失败**不降级继续**：这一步的全部意义就是"在还有外网时把家庭钉死"，失败还往下走等于回到出问题的老路。
- 没有动"账号确实没有家庭时自动建家"：新账号需要它，只是把触发条件收紧到"在正常网络上连查两次都为空"。

## 外部操作

无。

## 验证结果

- 本机（SSH 开发机）**没有 Flutter/Dart SDK、Android SDK、Xcode**：`flutter analyze`、`flutter test` 未执行，两端桥接**未编译**。
- 新增用例（未运行，`test/state_pairing_test.dart`）：会话开始把 `tuyaHome:mock-user` 钉给涂鸦；准备阶段查不到家庭时不取令牌、不连热点；确认家庭后才取令牌且令牌在有效期内不重取；旧原生包没有 `currentHomeId` 时不拦路。

## 未完成项与风险

- 真机未验证：需要走一次完整配网，确认准备阶段的遮罩出现且很快消失、日志里 `home pinned to …` 与 `home picked …` 对得上，配网完成后设备出现在同一个家庭。
- 已经被写进第二个空家庭的老设备不会自动搬家：本轮只保证今后固定用同一个家庭。若用户账号里已有两个家庭且设备在"不是最小 homeId"的那个里，第一次解析仍可能挑错——挑错时页面底部的诊断行会显示家庭 id，可据此在涂鸦后台确认。
- `setHomeId` 只在会话开始钉一次；用户在涂鸦 App 里删掉那个家庭的极端情况没有处理，此时设备列表会读到空，需要清掉本地记录（重新登录即可再解析一次）。
