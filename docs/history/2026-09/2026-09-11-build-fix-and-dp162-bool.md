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
