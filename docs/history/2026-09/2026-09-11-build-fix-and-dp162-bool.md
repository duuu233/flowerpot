# 2026-09-11 打包报错修复（我自己的删除脚本造成）＋ DP 162 改布尔

## 一、打包报错：`MainActivity.kt:34 Expecting a top level declaration`（已修）

### 现象

产品打包时从第 34 行起刷出几十条 `Syntax error: Expecting a top level declaration`，
行号一路往下。

### 根因：是我上一轮删代码留下的，**一个字符**

上一轮「只留 AP 模式常量」那段删除用的是 Python 脚本里的 `cut(a, b, insert)`，它保留
`s[:ia+1]`——这个 `+1` 是为了在 marker **以 `\n` 开头**时留住上一行的换行。而这一处的
marker 是 `"/**\n * 配网模式常量，新拼写在前。"`，**不以 `\n` 开头**，于是 `+1` 留下了
marker 的第一个字符 `/`，紧接着插入的文本又以 `/**` 开头：

```kotlin
//**
 * AP 热点配网的模式常量，新拼写在前。
 ...
 */
```

`//**` 是**行注释**，于是整个 KDoc 块失去了块注释的身份，里面每一行 ` * …`、`*/` 都变成
了顶层裸文本——第 34 行往后每一行都报 "Expecting a top level declaration"。

### 同一批删除的其它残留（不影响编译，一并清掉）

| 残留 | 影响 |
| --- | --- |
| `//**`（1 处） | **编译失败**，已改回 `/**` |
| 只含一个空格的空行（1 处） | 无，已删 |
| 被挤成 5 空格缩进的 `private fun`（3 处） | 无，已改回 4 空格 |

### 为什么静态自检没抓到

上一轮我查的是括号配平、被删符号零残留、`PairingStage` 引用——**这些全都通过了**，因为
`//**` 不改变任何括号数量、也不留下任何被删符号。**块注释的开闭是我那套自检里没有的一项。**

已补进 `PRODUCT_RULES` §6 的自检清单：

- 改完 Kotlin/Dart 后数一遍 `/**` 与 `*/` 的数量是否相等、`//**` 是否为 0；
- 用脚本删代码时，`cut` 的 marker **一律以 `\n` 开头**（`+1` 才是对的），或者干脆不做
  "保留一个字符"这种偏移。

## 二、DP 162 `plant_confirm` 由数值改布尔

### 产品口径

> pdid162=0 改成 pdid162=false（不弹提示框）
> pdid162=1 改成 pdid162=true（弹提示框）

即这一项在涂鸦后台由 value 型改成 **bool 型**，桥接收到的是 Dart `bool`。

### 为什么原来的解析会失效

```dart
final value = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
return value == 1 ? prompt : hidden;
```

`raw == true` 时：`raw is num` 为 false → `int.tryParse('true')` → `null` → 归成 `hidden`。
**结果是引导窗永远不弹**，而且不会报任何错——典型的静默失效。

### 改法：认布尔，但**保留**数值/字符串兜底

```dart
if (raw is bool) return raw ? prompt : hidden;          // 新口径
if (raw is num)  return raw.toInt() == 1 ? prompt : hidden;  // 旧固件 0/1
final text = '${raw ?? ''}'.trim().toLowerCase();
if (text == 'true' || text == '1') return prompt;       // 桥接字符串化
return hidden;
```

**为什么不只认布尔**：真机上两种固件会并存一段时间（没升级的设备还在报 0/1），只认一种
会让其中一批设备永远不弹窗。新老两套映射到同一个结论，没有歧义——`0`/`false` 都是不弹，
`1`/`true` 都是弹。

`PlantConfirmState.dpValue` 的类型跟着从 `int` 改成 `bool`（`hidden(false)` / `prompt(true)`）。
它只用在详情页那个 DP 162 探针对话框里显示，文案从「1 才弹引导窗」改成「true 才弹引导窗」。

`plantConfirmRaw`（上报原文）照旧原样保留，探针弹窗里先显示它、再显示 App 的解析结论——
布尔/数值哪种形态都能一眼看出来。

## 三、验证

**未验证**（本机无 Flutter/Dart/Kotlin 工具链）。静态自检：

1. `MainActivity.kt`：`/**` 与 `*/` 各 50 个、`//**` 为 0、非文档块 `/*` 为 0；括号
   `{}` 330/330、`()` 916/916；逐行扫顶层深度，唯一"可疑行"是 `SingleResult` 多行签名的
   续行（正常）；文件以 `    }\n}` 收尾。
2. `tuya_models.dart`：括号 `{}` 76/76、`()` 149/149；`fromDp` 四条分支覆盖
   bool / num / 字符串 / 其余。
3. `PlantConfirmState` 的消费方逐个核对：`state.plantConfirmState` / `needsPlantConfirm`
   只比较枚举成员，不碰 `dpValue`；`tuya_repository.dart:756` 走 `fromDp`；
   `device_info_page` 那句文案已同步。`test/features/home/home_plant_confirm_test.dart`
   直接构造 `PlantConfirmState.prompt`，不受类型变化影响。


---

# 第二轮打包失败（同一批删除的另外两处）+ 写了个检查器

第一轮修掉 `//**` 之后，打包又报两条：

```
e: MainActivity.kt:981:22  Unresolved reference 'requested'.
e: MainActivity.kt:1013:13 Unresolved reference 'requested'.
e: MainActivity.kt:1146:13 Unresolved reference 'currentSsidForLog'.
e: MainActivity.kt:1211:75 Unresolved reference 'currentSsidForLog'.
```

## 一、`currentSsidForLog` —— 夹在删除区间里被一起带走

它原来的位置在 `optimizedActivator` 字段和 `startActivator` 之间，而我那一刀正是
`[optimizedActivator 的 KDoc, startActivator)`——整段连它一起删了，可连热点那条路还有
两处在用（`joinDeviceHotspot` 的「手机本来就在这个热点上」判断、`joinViaSpecifier` 的
`onAvailable` 日志）。

已按原样恢复，放在 `joinDeviceHotspot` 上方（现在只有连热点这条路用它），并在文档注释里
补了一句**不要拿它的返回值做门禁**——没有定位权限时它返回「(读不到)」，拿去判断会误伤。

## 二、`requested` —— 随模式分支删掉，但同一个函数后面还在用

「只留 AP 模式」那一刀删掉了

```kotlin
val requested = call.argument<String>("mode").orEmpty()
val modeNames = when (requested) { "ez" -> …; "dual" -> …; else -> AP_MODE_NAMES }
```

但 `startActivator` 后面还有两处用 `requested`：诊断串 `"$requested/${factory.name}/…"`，
以及 `if (requested == "ap") { 绑定进程到 Wi-Fi }`。

修法**不是**把那行变量加回来，而是顺着「AP 是唯一模式」改干净：

- 诊断串写死 `"ap/${factory.name}/${(mode as Enum<*>).name}"`；
- 绑定改成**无条件**。原来那句 `if (requested == "ap")` 在只剩 AP 之后恒真，而且万一
  Dart 侧漏传 `mode`，`.orEmpty()` 会让它变成 `""`、于是**静默跳过绑定**——手机连的设备
  热点没有互联网，不绑定流量会留在移动数据上，凭据根本发不到设备，而且不报任何错。
  把它留着就是留了个陷阱。EZ 当年为什么要按模式区分（广播凭据时绑死 Network 会挡住广播，
  正是 EZ 报 1006 的原因）作为历史背景写在注释里。

## 三、根因不是手滑，是**自检项不够**

三次失败（`//**`、`currentSsidForLog`、`requested`）全都发生在同一轮大删除之后，而当时的
自检——括号配平、被删符号 grep、枚举成员引用——**三次全部通过**。原因很直接：

| 失败 | 括号配平 | 被删符号 grep | 能不能抓到 |
| --- | --- | --- | --- |
| `//**` | 不变 | 无残留 | ❌ |
| `currentSsidForLog` 被删 | 不变 | 它不在我的「被删符号」清单里（我删的是 `activeStart` 那批） | ❌ |
| `requested` 越界 | 不变 | 同上 | ❌ |

所以补了 **`tools/kt_dangling_refs.py`**：本机没有 Kotlin 工具链，这是离「编译一次」最近的
东西。它做两件事：

1. **结构检查**：`/*` 与 `*/` 数量配平、`//**` 必须为 0；
2. **按函数作用域**找「用了但在可见范围内没声明」的小写标识符，可见范围 =
   文件级成员 ∪ 该函数自己的参数与局部变量。

⚠️ **第 2 点必须按作用域**，这一点是踩出来的：检查器第一版在全文件范围内比对，
`requested` 在 `requestPairingPermissions` 里确实声明过，于是被当成「已声明」漏掉了。
改成「统计文件级声明时先把所有成员函数体挖掉」才抓到。

### 验证过检查器本身

| 在哪个版本上跑 | 结果 |
| --- | --- |
| `a0aa3bf`（含 `//**`） | ✗ 报出 `//**` + 2 处 `currentSsidForLog` |
| `e3d3ae0`（第一轮修完，仍缺两个符号） | ✗ 报出 `requested` + 2 处 `currentSsidForLog`，**零误报** |
| 当前版本 | ✅ OK |
| `FlowerpotApplication.kt` | ✅ OK |

已写进 `PRODUCT_RULES` §6：**改完 Kotlin 必须跑一遍这个脚本**。

它不是类型检查器——不解析 import、不查签名，输出是**候选**。但对「删代码之后还有谁在用」
这一类，它正好够用，而这恰恰是本机唯一查不出、又最容易把包打挂的一类。
