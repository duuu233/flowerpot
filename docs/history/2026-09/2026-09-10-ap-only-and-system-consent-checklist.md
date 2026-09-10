# 设备只支持 AP 配网；「昨天的包不需要授权」的排查清单

> 文档类型：Historical Change Record（**仅文档，无代码改动**）
> 日期：2026-09-10
> 环境：SSH
> 分支与起始版本：main / e2a479e
> 范围：`AI_CONTEXT.md`、本记录
> 当前权威文档：`AI_CONTEXT.md`、`docs/TUYA_SDK_SETUP.md`

## 一、来自设备开发的口径（**新增的确定事实**）

> 配网模式：设备采用涂鸦标准 AP 热点配网（AP-cfg），**没使用 EZ/SmartConfig 快连**。
> 配网流程：未激活设备开机后自动开启 Wi-Fi 热点（热点名 `smartlife_xxx` / `tuya_mdev_xxx`）
> → 手机连接该热点 → 打开涂鸦 App → App 通过热点下发目标路由器 SSID/密码 → 设备自动切换
> 连网并连云激活。

两条推论：

1. **EZ 这条路不存在**，不要再考虑。本仓库的原生桥接确实实现了 EZ（Android `EZ_MODE_NAMES`、
   `DUAL_MODE_NAMES`，iOS `ThingActivatorModeEZ`，注释还写着「EZ 默认，AP 兜底」），Dart 侧
   2026-08-30 的 `a55a9ad` 把 `mode` 写死成 `'ap'`。**那不是退化，是对的**——设备本来就不支持
   EZ。桥接里的 EZ 分支从此只能视为死代码。
2. **AP 必须连设备热点** ⇒ Android 10（API 29）起只能走 `WifiNetworkSpecifier` +
   `requestNetwork` ⇒ **系统授权框在「由 App 发起连接」这条路上无法避免**。

热点名核对过：`isDeviceHotspotName` 的白名单（去分隔符后匹配 `smartlif` / `tuya` /
`ysplanter`，外加 `ty_` / `ty-` 前缀）对 `smartlife_xxx` 与 `tuya_mdev_xxx` **都能认出**
（大小写、下划线、连字符各试过）。这一条不是问题来源。

## 二、「昨天的包不需要授权」——EZ 假设已排除，剩下两个解释

昨天（2026-09-09）的包里 `mode` 同样是 `'ap'`（`a55a9ad` 起就没变过），所以**不可能是 EZ**。
剩下两个都能解释「没弹框」，而且都可验证：

### 解释 A（最可能）：手机当时已经连在设备热点上，App 根本没发起连接

设备开发描述的正是这个流程——**「手机连接该热点 → 打开 App」**。只要手机已经在
`smartlife_xxx` 上，我们的代码就走「手动路径」直接开始配网，**不会调 `requestNetwork`，
自然不弹框**（`FlowerpotState._joinHotspotForPairing` 里 `scan.currentIsDeviceHotspot`
那一支；2026-09-10 又补了一条「已连在目标热点上就跳过 `requestNetwork`」）。

反过来，如果测试这次是**手机连着路由器**直接点「开始配网」，那就必然要由 App 去连热点 ⇒
必然弹框。两次的差别可能只是**点按钮那一刻手机连的是谁**。

### 解释 B（待核实）：系统记住了这个应用对这个网络的授权

较新的 Android 会记住「某应用请求某网络」的用户授权，同一组合第二次起可能不再弹。若为真，
第一次装机弹过一次之后就不会再弹，看起来就像「这个包不需要授权」。
**这条我没有在真机上验证过，也不该当成结论**——它只影响「为什么以前没看到」，不影响
「AP 模式下第一次必然要授权」这个事实。

## 三、请测试按这份清单核对（每条都能二选一地判定）

1. **点「开始配网」那一刻，手机连的是哪个 Wi-Fi？** 路由器，还是 `smartlife_xxx` / 
   `tuya_mdev_xxx`？——这一条最可能直接解释两次的差别。
2. **「昨天的包」是哪一个提交/版本号？** 昨天推了 12 个提交（`d0ab4d0` … `4eabac5`），
   配网链路上的改动集中在家庭 id 那几个。
3. **测试机的 Android 版本？** 9 及以下走的是完全不同的路径（App 不能自己连热点，只能引导
   手动连，因此**本来就没有系统框**）。
4. **这台手机以前连过/授权过同一个 `smartlife_xxx` 吗？** 若「忘记该网络」+ 清除应用数据后
   重试又弹框了，说明是解释 B。
5. **对比的是我们的 App 还是涂鸦官方 App？** 官方 App 的 AP 流程同样要连热点，同样受这条
   系统限制；若它没弹，多半也是因为手机已经先连上了热点。

## 三点五、新证据：同一台手机、同一台设备，智能生活 App 不弹框

测试补充：**同机同设备，用智能生活（涂鸦官方 App）配网不会弹这个提示。**

智能生活也是普通第三方应用、没有系统签名，受的是同一条限制。所以「不弹」只能来自下面三种
之一，而不是「它有我们没有的权限」：

| 可能 | 说明 | 怎么判定 |
| --- | --- | --- |
| **A. 它把用户送去系统设置手动连**（最可能） | 涂鸦 AP 流程的经典做法：`ThingActivatorModeAP` 要求手机**已经**连在热点上，**SDK 自己不负责连**。官方 App 于是画一屏「请连接设备热点」+ 一个跳系统 Wi-Fi 设置的按钮。App 从不调 `requestNetwork` ⇒ 自然没有框，但**用户多跑一趟设置**。 | 问测试：**智能生活里有没有一步是让你去系统 Wi-Fi 设置里选 `smartlife_xxx`？** |
| B. 这台手机早就授权过智能生活 | 较新 Android 会记住「某应用 + 某网络」的授权；官方 App 之前配过同一个热点，之后就不再弹。 | 在系统里清除智能生活的数据/忘记该网络后重试，看是否又弹 |
| C. 它用的是 `WifiNetworkSuggestion` | 首次要用户在通知里允许「建议 Wi-Fi 网络」，之后系统可自动连。但连接时机由系统决定，对配网这种即时场景不可靠。 | 看首次使用时有没有出现过「允许 XXX 建议 Wi-Fi 网络」的通知 |

**如果是 A**，那么「没有弹框」并不等于「步骤更少」——恰恰相反：

| | 系统框 | 用户步骤 |
| --- | --- | --- |
| 我们现在（App 发起连接） | 1 次 | 在框上点一下「连接」 |
| 智能生活（推测的 A） | 0 次 | 退出 App → 进系统设置 → 找到热点 → 连接 → 忽略「无法上网」提示 → 回 App |

在框上点一次，比跑一趟系统设置少得多。所以在 A 被证实的前提下，**当前实现已经是步数更少的
那一个**，不建议为了消掉那个框改回手动引导。

## 三点六、测试再确认：智能生活**不跳系统设置、也不弹框，直接就连上了**

A（送用户去系统设置）被排除。智能生活没有系统签名，能静默连网只剩一条已知机制：

### 最可能：它的 `targetSdkVersion` 停在 28 或更低，走的是**旧 API**

Android 的 Wi-Fi 限制是按**应用的 `targetSdkVersion`** 生效的，不是按设备系统版本。
`WifiManager.addNetwork()` / `enableNetwork()` 的官方兼容性说明写得很直白：

> **Compatibility Note:** For applications targeting `Build.VERSION_CODES.Q`（API 29）or above,
> this API will always fail and return -1 / false.

反过来：**`targetSdk ≤ 28` 的应用，在 Android 10/11/12/13 的机器上仍然可以
`addNetwork()` + `enableNetwork()` 自己加的网络并静默连上，没有任何弹框。**
国内市场的 App 常年停在低 targetSdk，正是为了保住这类能力；Google Play 强制的
targetSdk 下限对国内商店不适用。

**我们的 `targetSdk` 跟着 Flutter 走**（`android/app/build.gradle.kts`：
`targetSdk = flutter.targetSdkVersion`），是现代版本 ⇒ 落在「always fail」那一侧 ⇒
只能用 `WifiNetworkSpecifier`，于是必然弹框。**这就是两边行为不同的根源，不是权限差异。**

### 怎么查别人 App 的 targetSdk（三选一）

**① 有电脑 + 手机开 USB 调试（最省事，不用拿到 APK）**

```bash
adb shell pm list packages | grep -iE 'tuya|thing|smartlife'   # 先找包名
adb shell dumpsys package <包名> | grep -i targetSdk           # 直接打印 targetSdk=NN
```

**② 手机上装个「应用信息」类工具**（App Info / Package Viewer / MyAndroidTools 之类），
应用详情里通常直接列出 target SDK。不用电脑。

**③ 拿到 APK，用本仓库的离线脚本**（不需要 Android SDK / aapt）

```bash
adb shell pm path <包名>          # 打印 /data/app/.../base.apk
adb pull <上一步的路径> ./smartlife.apk
python3 tool/apk_target_sdk.py ./smartlife.apk
```

脚本 `tool/apk_target_sdk.py` 纯标准库解析二进制 `AndroidManifest.xml`，打印
`minSdkVersion` / `targetSdkVersion` 与 Wi-Fi 相关权限，并直接给出结论。
**只读 APK，不解包不改写。**

### 判读



```bash
adb shell dumpsys package com.tuya.smartlife | grep -i targetSdk
# 包名也可能是 com.thingclips.smartlife；或用 aapt dump badging <apk> 看 targetSdkVersion
```

`targetSdk` 是 28 或更低 ⇒ 结论坐实。

### 那我们能照做吗——能，但代价是产品级的

| 方案 | 效果 | 代价 |
| --- | --- | --- |
| **把 targetSdk 降到 28** | 恢复静默连网，彻底没有框 | **Google Play 拒绝**低于其下限的更新（只发国内商店才可行）；放弃十年的平台行为与安全改进；Flutter/三方库在低 target 下的行为要重测；属于产品 + 安全决策，不是改一行 |
| **`WifiNetworkSuggestion`** | **首次**在通知里允许一次「建议 Wi-Fi 网络」，之后系统可自动连、不再打断 | 连接时机由系统决定（不保证立刻），对配网这种即时场景可靠性待测；仍需一次首启授权 |
| 维持现状（`WifiNetworkSpecifier`） | 每次一个框，点「连接」即可 | 框去不掉；较新 Android 会记住同一应用+同一网络的授权，之后可能不再弹（未实测） |

⚠️ 以上三条**都没有在真机验证过**，`targetSdk` 那条也还只是待验证的推断——但它是目前唯一能
解释「同机同设备、官方 App 静默连上」的机制。

## 三点七、结论落定：授权框去不掉；官方 AP 流程本来就是「用户自己去系统设置连」

向涂鸦官方渠道求证过两轮，加上对官方文档与 Maven 仓库的实测，结论已经可以定下来。

### 实测一：官方文档里没有那个「Kit」

第一轮答复声称有个 `ThingSmartHotspotCredentialKit`，接入后即可静默连接。实测：

- **Maven 仓库不存在**。探测 `maven-releases` 与 `maven-commercial-releases` 两个仓库
  （即本项目 `android/build.gradle.kts` 配的那两个），4 个 groupId × 3 种命名 × 2 个仓库的
  `maven-metadata.xml` **全部 404**；同法探测 `com.thingclips.smart:thingsmart` 与
  `thingsmart-expansion-sdk` 均 200，证明探测方法有效。
- **它给的两篇官方文档里也没有**。抓取
  `developer.tuya.com/cn/docs/iot/ap-mode?id=K9obrofrfk4sk` 与
  `.../device-sdk-android?id=Ka8qhzkgfr4uh`（均 200、正文完整，「热点配网」分别出现 21 / 2 次），
  `HotspotCredential`、`CredentialKit`、`ThingApActivator`、`WifiNetworkSpecifier`
  **四个关键词出现次数都是 0**。

第二轮答复已自行改口：该组件「未公开发布、不向第三方开放」。

### 实测二：官方 AP 流程原文

`ap-mode` 文档原话：

> 在 Wi-Fi 设置页面中找到以 SmartLife 开头的 Wi-Fi 热点，并单击进行连接。**连接成功后，再返回
> App**，即可开始配网流程。……同时手机连接的 Wi-Fi 必须为 2.4GHz 频段。

**涂鸦自己记载的 AP 流程就是「用户到系统设置里手动连热点，再回 App」**——App 不发起连接，
所以没有授权框，代价是用户跑一趟系统设置。

### 结论

1. **Android 10+ 没有任何公开 API 能让普通第三方应用绕开入网授权**（第二轮答复也确认了这一点）。
2. **我们现在的做法比官方文档记载的流程更省事**：由 App 发起连接，用户只需在系统框上点一下
   「连接」，不必跑系统设置。这**一个框换掉了一整趟设置之旅**，不该为了消掉它退回手动引导。
3. 「智能生活不弹框」最可能的解释是**手机里已经保存过那个热点**：`smartlife_xxx` 一旦连过一次
   就会被系统记住，设备再开机时手机会**自动重连**，App 打开时早已在热点上，于是既不跳设置也
   不弹框。**我们的实现在同样情形下同样不弹**——`_joinHotspotForPairing` 会先看当前 SSID，
   已经连在目标热点上就跳过 `requestNetwork`（2026-09-10 补的）。
   **验证：在测试机上看「设置 → WLAN → 已保存的网络」里有没有 `smartlife_xxx`。**
4. 由此，授权框实际上主要出现在**第一次配某台设备**时；之后手机记住热点，多半不再出现。

⚠️ 第 3 条仍是推断，需要按上面那句去测试机上核实。涂鸦第二轮给的「厂商预置白名单」说法
无法验证、也与第 3 条不冲突，不影响端上结论。

**因此本轮不改代码**：当前实现（App 发起连接 + 已连上则跳过）已经是可行方案里步骤最少的。

## 四、如果确认「必须让用户少一步」，可选的方向（都要产品决定，本轮未做）

| 方向 | 效果 | 代价 |
| --- | --- | --- |
| 维持现状（App 发起连接） | 用户只输密码 + 点按钮，中间一次系统框点「连接」 | 那一次框无法消除 |
| 改回「引导用户先去系统设置连热点」 | 没有系统框 | 步骤更多、更容易走丢，是这轮一直在去掉的东西 |
| 页面上预告那次弹框 | 用户有预期、不会犹豫 | 就是本轮刚按产品要求删掉的那段文案 |

## 验证结果

- **本轮没有改任何代码**，只更新 `AI_CONTEXT.md` 与新增本记录。
- 热点名白名单的匹配用一段等价的 Python 复算过（`smartlife_xxx` / `tuya_mdev_xxx` 及其大小写、
  分隔符变体全部命中），**不是在真机上验的**。
- 解释 A / B 都**未经真机验证**，需要按第三节的清单核对后才能定论。
