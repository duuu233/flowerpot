# 涂鸦推送 · APP 机器日志对接说明

> **面向**：APP 开发
> **固件基线**：MCU_VER 1.1.4+
> **上游文档**：`涂鸦推送_App机器日志方案_分析稿.md`（分析过程）、`涂鸦消息推送对接方案.md`（云端推送规则）、`涂鸦推送告警分级方案.md`（三档定义）
> **本文件定位**：**精简落地版**——只讲 APP 要做什么。分析、取证、取舍过程不在此重复。

**一句话**：APP 自己**订阅 DP** → 判定**值变化边沿** → 按**档位**生成日志条目（中文 / English）。

```
设备(MCU) --DP上报--> 涂鸦云 --MQTT--> APP
                                     ├─ ① 日志引擎  ← 本文件定义（订阅 DP、本地生成）
                                     └─ ② 系统推送  ← 云端规则，另一路，只负责通知栏
```

> 日志**不依赖云端推送规则**——推送规则是给"通知栏"用的，日志是 APP 自己算的。

---

## 1. 抓哪条 DP

### 1.1 必需（6 条）

| DP | 名称 | 类型 | 抓什么 | 触发方式 |
|---|---|---|---|---|
| **5** | status | enum(12) | 作业开始/结束、急停、故障停机、回充、等待 | 变化即报 |
| **111** | fault_alarm | string(JSON) | **全部故障与告警**（严重/轻微/通知） | 变化即报 |
| **117** | charging | enum(3) | 充电开始 / 完成 / 离桩 | 变化即报 |
| **118** | cover_closed | bool | 开盖 / 合盖 | 变化即报 |
| **113** | shutdown_report | bool | 设备关机 | 事件（关机瞬间连发，需去重） |
| **13** | battery_percentage | value | 低电预告（≤35） | ≥1% 变化即报 |

### 1.2 可选（按产品需要）

| DP | 抓什么 | 说明 |
|---|---|---|
| 115 | **命令被拒理由** | 详见 §7 |
| 116 / 112 | 升级进度 / 升级成功确认 | 均为 string |

### 1.3 ⚠️ 不需要抓的

| DP | 为什么 |
|---|---|
| **18** fault | **日志不消费它**。DP18 是"云端推送用"的**粗粒度**位图（13 位，把左轮过流/过温/霍尔/离线**并成 1 位**）。DP111 信息更全、粒度更细，一个就够 |
| 3 / 2 | 与 DP5 同源，状态重复 |
| 101~110 / 114 / 119 | 参数类，属"配置变更"不属机器行为 |

---

## 2. 怎么分等级

### 2.1 三档定义

| 档 | 名称 | 判定 | APP 表现 |
|---|---|---|---|
| **3** | **严重** critical | 机器已停机 / 涉及安全 / 需用户到场 | 强提醒：横幅+声音；红点；弹窗 |
| **2** | **轻微** minor | 出现异常但机器正在或已**自恢复** | 角标+列表，**不弹窗** |
| **1** | **通知** notice | 正常作业过程，或机器已自动处理完 | 静默入列表 |

### 2.2 等级表达式（直接照抄）

输入 = **DP111** 解析出的四个数字 + 各 DP 的边沿事件。

```js
// 解析 {"device":N,"error":N,"function":N,"circularize":N}
let level = 0;
if (cir & 0x00006) level = 1;                  // 通知：雨滴 / 低电
if (cir & 0x01038) level = 2;                  // 轻微：脱困/丢信号/圈外/抬起
if (dev || err || fn) level = 3;               // 严重：三层任一非零，最高优先，直接覆盖
```

| 常量 | 值 | 含义 |
|---|---|---|
| `LOG_NOTICE_MASK` | `0x00006` | 通知档位 |
| `LOG_MINOR_MASK` | **`0x01038`** | 轻微档位 |
| `LOG_SKIP_MASK` | `0xFEFC1` | **不做日志的位**（§3.5 逐位列出） |

> **自校验**：`(0x00006 \| 0x01038) \| 0xFEFC1 = 0xFFFFF` —— circularize 20 位全覆盖、无重叠。
> **优先级**：严重 > 轻微 > 通知；同一时刻多事件取**最高档**。

---

## 3. 事件与中英文文案（核心表）

> **event_id 是给 APP 用的稳定键**（做 i18n 表、做日志存储用），格式 = `层.位名`，与 DP111 的位一一对应。

### 3.1 严重档 · DP111 `device` 层

| event_id | 位值 | 中文 | English |
|---|---|---|---|
| `device.battery` | `0x001` | 电池异常，机器已停机 | Battery fault, machine stopped |
| `device.imu` | `0x002` | IMU 异常，机器已停机 | IMU fault, machine stopped |
| `device.flash` | `0x004` | 存储异常，机器已停机 | Storage fault, machine stopped |
| `device.motor_left` | `0x008` | 左轮电机离线，机器已停机 | Left wheel motor offline, machine stopped |
| `device.motor_right` | `0x010` | 右轮电机离线，机器已停机 | Right wheel motor offline, machine stopped |
| `device.motor_blade` | `0x020` | 刀盘电机离线，机器已停机 | Blade motor offline, machine stopped |
| `device.xxx` | `0x040` | —— 保留位，**不记** | — |

### 3.2 严重档 · DP111 `error` 层

| event_id | 位值 | 中文 | English |
|---|---|---|---|
| `error.pose` | `0x0001` | 机器倾覆，请检查现场 | Machine tilted, check the site |
| `error.lift` | `0x0002` | 机器被抬起，已停机 | Machine lifted, stopped |
| `error.boundary` | `0x0004` | 边界线信号异常，机器已停机 | Boundary signal fault, machine stopped |
| `error.left_ocp` | `0x0008` | 左轮电机过流，机器已停机 | Left wheel overcurrent, machine stopped |
| `error.left_otmp` | `0x0010` | 左轮电机过温，机器已停机 | Left wheel overheated, machine stopped |
| `error.left_hall` | `0x0020` | 左轮电机霍尔异常，机器已停机 | Left wheel hall error, machine stopped |
| `error.right_ocp` | `0x0040` | 右轮电机过流，机器已停机 | Right wheel overcurrent, machine stopped |
| `error.right_otmp` | `0x0080` | 右轮电机过温，机器已停机 | Right wheel overheated, machine stopped |
| `error.right_hall` | `0x0100` | 右轮电机霍尔异常，机器已停机 | Right wheel hall error, machine stopped |
| `error.blade_otmp` | `0x0400` | 刀盘电机过温，机器已停机 | Blade motor overheated, machine stopped |
| `error.blade_hall` | `0x0800` | 刀盘电机霍尔异常，机器已停机 | Blade hall error, machine stopped |
| `error.blade_stall` | `0x1000` | 刀盘堵转（可能卡异物），机器已停机 | Blade stalled (possible obstruction), stopped |
| `error.outside` | `0x4000` | 机器在边界外，已停机 | Machine outside boundary, stopped |
| `error.spot_out` | `0x8000` | 定点作业位置超出边界，已停机 | Spot position out of boundary, stopped |
| `error.blade_ocp` | `0x0200` | ⛔ **死位，永不置位，不记** | — |
| `error.not_in_schedule` | `0x2000` | ⛔ **死位，永不置位，不记** | — |

### 3.3 严重档 · DP111 `function` 层

| event_id | 位值 | 中文 | English |
|---|---|---|---|
| `function.trap` | `0x002` | 机器被困（陷坑），已停机 | Machine stuck (pit), stopped |

### 3.4 轻微 / 通知档 · DP111 `circularize` 层（**只记这 6 个位**）

| event_id | 位值 | 档 | 中文 | English |
|---|---|---|---|---|
| `circularize.trap_out` | `0x008` | 轻微 | 机器陷入坑洼，正在脱困 | Recovering from stuck |
| `circularize.lost_signal` | `0x010` | 轻微 | 丢失边界信号，正在搜索 | Boundary signal lost, searching |
| `circularize.outside` | `0x020` | 轻微 | 机器在边界外，正在找回 | Outside boundary, recovering |
| `circularize.lift` | `0x1000` | 轻微 | 机器被抬起 | Machine lifted |
| `circularize.rain` | `0x002` | 通知 | 检测到积水，机器自动回充 | Water detected, returning to dock |
| `circularize.low_charge` | `0x004` | 通知 | 电量过低，机器自动回充 | Battery too low, returning to dock |

### 3.5 ⛔ 不做日志的位（`LOG_SKIP_MASK = 0xFEFC1`）

> **请严格按照本表**——这些位在割草中会**频繁抖动**，记进日志会刷屏。

| 位值 | 名称 | 不记的理由 |
|---|---|---|
| `0x040/0x080/0x100/0x400` | 刀盘电流等级 P0/P1/P2/P4 | **工况**：机器在怎么干活，不是事件；随负载持续跳变 |
| `0x200` | 密草停顿 | 工况：正常密草应对 |
| `0x2000` | 前上坡 | 地形：正常上坡 |
| `0x80000` | 边界停止确认期 | 过程：每次停机都经历的约 1 秒过渡态 |
| `0x4000` | 边界过渡超时 | 内部过程量：机器自处理，用户不可行动 |
| `0x20000` | 状态卡死超时 | 内部过程量：不停机，有下游兜底 |
| `0x40000` | 停止确认超时 | **与 `0x010` 丢信号同生同灭**，信息重复（固件设计上同步置位/清位） |
| `0x001` | 碰撞霍尔感应 | **死位**：固件无写入点，恒 0 |
| `0x8000/0x10000` | 左/右边界传感器故障 | **死位**：恒 0 |
| `0x800` | 刀盘过温（通知位） | **死位**：恒 0（刀盘过温实际走 `error` 层 `0x0400`） |

### 3.6 故障恢复（**必做**）

**规则**：某位由 `1 → 0` 时，把对应条目置为**已恢复**，并按"通知"档展示（不弹窗、不计红点）。

| | 文案 |
|---|---|
| 中文 | `{故障名}已恢复` |
| English | `{Fault name} cleared` |

> **示例**：`左轮电机过流，机器已停机` → `左轮电机过流已恢复` / `Left wheel overcurrent cleared`
> ⚠️ 云端推送**只推"发生"不推"恢复"**，恢复边沿只能由 APP 从 DP 订阅流自己取。

---

## 4. 其他 DP 的事件与文案

### 4.1 DP5 作业类

| event_id | 触发（旧值 → 新值） | 档 | 中文 | English |
|---|---|---|---|---|
| `dp5.mowing` | `≠1 → 1` | 通知 | 开始割草 | Mowing started |
| `dp5.edge` | `≠8 → 8` | 通知 | 开始沿边割草 | Edge mowing started |
| `dp5.spot` | `≠3 → 3` | 通知 | 开始定点割草 | Spot mowing started |
| `dp5.secondary` | `≠11 → 11` | 通知 | 开始第二区域割草 | Secondary area mowing started |
| `dp5.finish_dock` | `{1,3,8,11} → 4` | 通知 | 作业结束，正在返回充电桩 | Work finished, returning to dock |
| `dp5.cancel` | `{1,3,8,11} → 0` | 通知 | 作业已取消，机器待机 | Work cancelled, standby |
| `dp5.fault` | `* → 6` | **严重** | 机器故障停机 | Machine stopped: fault |
| `dp5.estop` | `* → 7` | **严重** | 机器被急停 | Emergency stop activated |
| `dp5.docked` | `4 → {9,10}` | 通知 | 机器已回到充电桩 | Machine docked |
| `dp5.wait_rain` | `≠10 → 10` | 通知 | 检测到降雨，机器等待雨停 | Rain detected, waiting at dock |
| `dp5.wait_charge` | `≠9 → 9` | — | **默认不记**（在桩等待是每天长时间常态，会刷屏） | — |

**DP5 值表**：`0` 待机｜`1` 割草｜`2` 关机｜`3` 定点｜`4` 回充中｜`5` 暂停(**已废弃，永不出现**)｜`6` 故障｜`7` 急停｜`8` 沿边｜`9` 在桩等充电｜`10` 在桩等雨停｜`11` 第二区域

### 4.2 充电 / 电量 / 安防 / 电源类

| event_id | 触发 | 档 | 中文 | English |
|---|---|---|---|---|
| `dp117.charging` | `≠1 → 1` | 通知 | 已开始充电 | Charging started |
| `dp117.full` | `≠2 → 2` | 通知 | 充电完成 | Charging complete |
| `dp117.leave` | `{1,2} → 0` | 通知 | 机器已离开充电桩 | Machine left the dock |
| `dp13.low` | 首次 `≤35` | 通知 | 电量低（{v}%），即将自动回充 | Battery low ({v}%), returning soon |
| `dp118.open` | `1 → 0` | **轻微** | 机器盖子被打开 | Cover opened |
| `dp118.close` | `0 → 1` | 通知 | 机器盖子已关闭 | Cover closed |
| `dp113.off` | `false → true` | 通知 | 设备已关机 | Device powered off |
| `dp113.on` | `true → false` | 通知 | 设备已开机 | Device powered on |

> ⚠️ **关机只能用 DP113 判断**——DP5=2(sleep) 在"在桩关机"时也会上报，会误报。
> ⚠️ `dp13.low` 阈值**必须 > 30**（固件 30% 就回充上桩了，配 ≤30 永不触发）；建议 35。

---

## 5. 生成日志的 6 条规则（必读）

| # | 规则 | 说明 |
|---|---|---|
| **1** | **按"值变化"处理，同值丢弃** | 固件有**兜底重报**（DP5 每 1s、DP18/13/111/117 每 60s 重发同值）。收到即记会刷屏 |
| **2** | **同一事故合并成 1 条** | 2 秒窗口内同一物理原因的多条 → 合并，取**最高档**。例：`dp5.fault` 与 DP111 的 `error.*/device.*` 同时出现 ⇒ 只记 **1 条严重**，正文列具体故障名 |
| **3** | **"抬起"只记 1 条** | `circularize.lift`(轻微) 与 `error.lift`(严重) 会**同时置位**（短时抬起只有轻微，>10s 或待机整体抬起才有严重）⇒ 有 `error.lift` 就记严重，否则记轻微 |
| **4** | **恢复要配对** | 位 `1→0` 时找到同 `event_id` 的未恢复条目，标记已恢复（§3.6） |
| **5** | **等级保持窗口** | 轻微位会瞬时抖动。**升档立即、降档延迟**（严重 30s / 轻微 60s / 通知 60s）——只影响"当前等级"显示，**不影响日志条目生成** |
| **6** | **查询回读不产生日志** | APP 重连后的全量查询只用于对齐当前值；不要拿它当"事件"记日志 |

### 5.1 不需要处理的两种情况

| 现象 | 处理 |
|---|---|
| 开机后几十秒内什么都没收到 | **开机自检静默窗口**，正常现象，不是故障 |
| 升级期间收不到任何 DP | OTA 期间设备不上报，正常现象 |

### 5.2 时间戳

DP 载荷**不带设备时间**，请用**云端接收时间戳**，并在详情里标注为"云端记录时间"。

---

## 6. 快速实现参考

```js
// ---- DP111 位表（只记这些）----
const DEVICE = { battery:0x001, imu:0x002, flash:0x004,
                 motor_left:0x008, motor_right:0x010, motor_blade:0x020 };
const ERR    = { pose:0x0001, lift:0x0002, boundary:0x0004,
                 left_ocp:0x0008, left_otmp:0x0010, left_hall:0x0020,
                 right_ocp:0x0040, right_otmp:0x0080, right_hall:0x0100,
                 blade_otmp:0x0400, blade_hall:0x0800, blade_stall:0x1000,
                 outside:0x4000, spot_out:0x8000 };
const FN     = { trap:0x002 };
const CIR    = { rain:0x002, low_charge:0x004,
                 trap_out:0x008, lost_signal:0x010, outside:0x020, lift:0x1000 };

const NOTICE_MASK = 0x00006, MINOR_MASK = 0x01038, SKIP_MASK = 0xFEFC1;

function classify(dp111) {
  const { device:dev, error:err, function:fn, circularize:cir } = dp111;
  const events = [];
  for (const [k,v] of Object.entries(DEVICE)) if (dev & v) events.push({ id:`device.${k}`, level:3 });
  for (const [k,v] of Object.entries(ERR))    if (err & v) events.push({ id:`error.${k}`,  level:3 });
  for (const [k,v] of Object.entries(FN))     if (fn  & v) events.push({ id:`function.${k}`, level:3 });
  for (const [k,v] of Object.entries(CIR)) {
    if (cir & v) events.push({ id:`circularize.${k}`, level:(v & NOTICE_MASK) ? 1 : 2 });
  }
  return events;   // 按 event_id 查 i18n 表取中/英文案
}
```

> `SKIP_MASK`（`0xFEFC1`）内的位**不产生任何事件**，代码里无需处理——列出来只是为了让你知道"它们存在但被故意忽略"。

---

## 7. 可选：命令被拒理由（DP115）

订阅 DP115（string JSON），`code ≠ 0` 时记 1 条**轻微**档日志。`code = 0`（成功，含幂等）**不记**。

载荷：`{"code":N,"seq":N,"dp":N,"val":N}`

| code | 中文 | English |
|---|---|---|
| 16 | 机器已关机，命令未生效 | Machine is off, command ignored |
| 17 | 开机自检中，请稍后再试 | Self-test in progress, try later |
| 18 | 升级中，命令未生效 | Updating, command ignored |
| 19 | 机器处于急停，请先恢复 | Machine in emergency stop |
| 21 | 盖子未关，请合上盖子 | Cover open, please close it |
| 23 | 请松开急停按钮 | Release the emergency stop button |
| 24 | 机器正在找线，请稍候 | Machine is searching for the boundary |
| 25 | 边界信号丢失，请检查边界线 | Boundary signal lost, check the wire |
| 26 | 故障未排除，命令未生效 | Fault not cleared, command ignored |
| 32 | 机器在充电桩上 | Machine is on the dock |
| 33 | 机器在界外，请移回界内 | Machine outside boundary |
| 34 | 电量低，正在充电 | Battery low, charging |
| 35 | 雨天暂停中 | Paused due to rain |
| 48 | 请先选择工作模式 | Please select a work mode first |
| 49 | 机器在桩等待中 | Machine is waiting at the dock |
| 52 | 上次任务已取消，请重新选择模式 | Previous task cancelled, select a mode |
| 53 | 设备正忙，请稍后重试 | Device busy, try again later |
| 64~70 | 参数不合法，命令未生效 | Invalid parameter, command ignored |
| 255 | 操作未生效（码 {v}） | Command not applied (code {v}) |

> **`26` 的特殊处理**：收到 26 时请读 DP111 的 `device`+`error` 两层定位残留故障，用**具体故障名**做日志文案，不要统一写"机器故障"。

---

## 8. 已知边界（不影响实现，但请知情）

| # | 项 | 说明 |
|---|---|---|
| 1 | **回充原因不可分** | 低电 / 雨滴 / 计划完成 / 手动回充**都表现为 DP5→4**，日志只能写"返回充电桩" |
| 2 | **作业时长需自算** | 用 DP5 边沿自己配对（进入作业 → 离开作业）；断电/断网会切断配对，请标注为"预估" |
| 3 | **离线期间会丢事件** | APP 不在线时收不到 DP 变化；关机（DP113）与故障位之外基本不可补 |
| 4 | **"作业中被抬起"只报轻微** | 固件设计：割草中四霍尔整体抬起只置"通知级"位，不置 `error.lift`。若产品要求记为严重，**需固件改动**（见分析稿 §7） |
| 5 | **两条"圈外"不是一回事** | `error.outside`(严重，停机) vs `circularize.outside`(轻微，自找回)。文案已区分，勿合并 |
| 6 | **DP111 是 string** | **云端配置不了推送规则**，只能 APP 自己解析——所以日志必须由 APP 生成 |

---

## 9. 自测清单

| # | 用例 | 期望 |
|---|---|---|
| 1 | 机器静置 5 分钟 | 日志 **0 条新增**（兜底重报被正确去重） |
| 2 | 制造单一故障（抬起 10s+） | **1 条**严重；不出现"故障停机"+"抬起"两条 |
| 3 | 故障排除后 | 原条目出现"已恢复"，不弹窗、不计红点 |
| 4 | 挡刀盘 / 淋雨 / 开盖 / 关机 / 急停 / 回充 各触发一次 | 档位与 §3/§4 表一致，中英文齐全 |
| 5 | 弱信号反复（丢信号搜索） | 保持窗口生效，列表无连续重复条目 |
| 6 | 开盖时下发启动命令 | 1 条：`盖子未关，请合上盖子`（code 21） |
| 7 | 放电到 35% → 30% | `电量低(35%)` → `返回充电桩` → `已开始充电`，顺序正确 |
| 8 | 切换语言 | 全部条目中英文切换正常，无缺失回退英文 |

---

## 附：变更记录

| 版本 | 日期 | 内容 |
|---|---|---|
| V1.0 | 2026-10-12 | 首版：6 条必需 DP、三档表达式与掩码（`0x00006`/`0x01038`/`0xFEFC1`）、约 40 条事件中英文文案、6 条生成规则、DP115 理由码、自测清单 |
