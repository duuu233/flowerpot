# Grass Master Automower · 拒绝理由码与 App 文案（V1.0）

> **本文档是拒绝码与文案的唯一依据**，配合 `Grass_Master_Automower_DP协议对接_V3.0.md` 使用。
> 固件基线：**2026-10-22**（`Grass_Master_Automower/Tuya/tuya_protocol.h` 474 行）
> **取代**以下历史文档：
> `拒绝理由DP_完整交接文档.md`、`拒绝理由DP_实施方案总纲.md`、
> `拒绝理由DP_重新分析_对照当前代码.md`、`DP拒绝理由上报_改造记录与分析.md`、
> `Grass_Master_Automower_DP下发结果_给App团队说明.md`(Draft V1)

---

## 1. 怎么用

```
设备收到一条下发  ⇒  处理  ⇒  回 1 帧 DP115
                                 {"code":N,"seq":M,"dp":D,"val":V}

code == 0   ⇒ 成功（已执行，或幂等达成——固件不细分成功码）
code != 0   ⇒ 被拒绝，按第 3 节的表出文案
```

**三条硬规则**

| # | 规则 |
|---|---|
| 1 | **`code` 是唯一权威判据**。不要用"DP 值有没有变"推测成功与否 |
| 2 | 用 `seq` 去重：只处理比上次大的 `seq`（0~255 循环） |
| 3 | `code == 26` ⇒ **必须读 DP111 的 `device` + `error` 两层**定位"还剩哪几项没排除"，按优先级出**具体**文案（见 §5.1），不要只提示"机器故障" |

**上报时机**

| 场景 | 是否发 |
|---|---|
| 每条下发处理完 | ✅ 立即 1 帧 |
| 云端 `0x08` 查询 / 连云首报 | ✅ 回读**最后一条**（内容与 `seq` 都不变 ⇒ 是旧结果） |
| 本次上电从未下发过 | ❌ 不发（不产生初值） |

---

## 2. 结果码（`0x00 ~ 0x0F`）

| 十进制 | 十六进制 | 宏 | 含义 | 当前是否产生 |
|---|---|---|---|---|
| 0 | `0x00` | `RES_OK` | 已执行（**含幂等达成**，成功不细分） | ✅ |
| 1 | `0x01` | `RES_ALREADY` | 保留未用 | ❌ |
| 2 | `0x02` | `RES_NONE` | 保留未用 | ❌ |
| 3 | `0x03` | `RES_INTERNAL_FAIL` | 回写/落盘失败（**非业务拒绝**） | ✅ |

> `3` 是设备内部错误（如 Flash 写失败、DP 回读发送失败），App 文案建议"操作未生效，请重试"。

---

## 3. 拒绝码总表

> "回显"列：动作类（DP2/DP3）拒绝时固件会**回真实状态值**，App 靠它把控件弹回。

### 3.1 状态类（`0x10 ~ 0x1F`）

| 十进制 | 十六进制 | 宏 | 触发条件 | 中文文案 | English | App 建议动作 |
|---|---|---|---|---|---|---|
| 16 | `0x10` | `REJ_POWER_OFF` | 设备已关机 | 机器已关机 | Machine is off | 提示开机，无需重发 |
| 17 | `0x11` | `REJ_SELFTEST` | 开机自检/工作启动自检窗口 | 开机自检中，请稍候 | Self-test in progress, please wait | 等待后重发 |
| 18 | `0x12` | `REJ_OTA_BUSY` | OTA 会话中（READY/RECEIVING/FINALIZING） | 固件升级中，暂不接受操作 | Firmware updating, please wait | 提示等升级完成 |
| 19 | `0x13` | `REJ_ESTOP` | 已处于急停 | 机器处于急停状态 | Machine is in emergency stop | 提示先恢复 |
| 21 | `0x15` | `REJ_COVER_OPEN` | 盖子未关 | 请合上盖子 | Please close the cover | 提示合盖，**无需重发**（关盖后设备自己往下走） |
| 22 | `0x16` | `REJ_LOCKED` | 面板锁 / PIN 态 | 机器已锁定 | Machine is locked | ⚠️ **当前固件不产生**，App 可保留分支 |
| 23 | `0x17` | `REJ_ESTOP_NOT_RELEASED` | 急停按钮未松开 | 请松开急停按钮 | Please release the emergency stop button | 提示松开 |
| 24 | `0x18` | `REJ_SIGNAL_SEARCH` | 本次上电**尚未锁定边界信号** | 机器正在寻找边界线，请稍候 | Searching for the boundary wire | 稍候重发 / 检查线是否通电 |
| 25 | `0x19` | `REJ_SIGNAL_LOST` | 边界信号丢失（曾锁定后丢失/无线框） | 边界信号丢失，请检查边界线 | Boundary signal lost, check the wire | 检查线路供电与机器位置 |
| 26 | `0x1A` | `REJ_FAULT_ACTIVE` | 故障态且**故障未排除** | （**不统一写"机器故障"**，见 §5.1） | (see §5.1) | **读 DP111 定位具体故障** |

> **`24` 与 `25` 的区别**：`24` 是"开机后还没找到线"；`25` 是"曾经找到过，现在丢了"。

### 3.2 场景类（`0x20 ~ 0x2F`）

| 十进制 | 十六进制 | 宏 | 触发条件 | 中文文案 | English | App 建议动作 |
|---|---|---|---|---|---|---|
| 32 | `0x20` | `REJ_ON_PILE` | 已在充电桩上（定点/回桩场景） | 机器已在充电桩上 | Machine is on the dock | 无需处理 |
| 33 | `0x21` | `REJ_OFF_BOUNDARY` | 边界外 / 骑线（双外确认） | 机器在界外，请移回界内 | Machine is outside the boundary | 提示挪回界内 |
| 34 | `0x22` | `REJ_LOW_CHARGE` | 因**低电**正处于回桩/等待 | 电量低，正在充电 | Battery low, charging | **无需重发**（充满会自己出发） |
| 35 | `0x23` | `REJ_RAIN` | 因**雨天**正处于回桩/等待 | 雨天暂停中，雨停后自动继续 | Paused due to rain | **无需重发**（雨停会自己出发） |

### 3.3 任务类（`0x30 ~ 0x3F`）

| 十进制 | 十六进制 | 宏 | 触发条件 | 中文文案 | English | App 建议动作 |
|---|---|---|---|---|---|---|
| 48 | `0x30` | `REJ_NO_MODE` | 待机且**从未选过模式** | 请先选择工作模式 | Please select a work mode first | 引导选模式 |
| 49 | `0x31` | `REJ_ON_PILE_WAIT` | 在桩等待中（等充电 / 等雨停）且不可打断 | 机器在桩等待中 | Machine is waiting at the dock | 提示不必操作 |
| 50 | `0x32` | — | **保留值，不再产生**（原"暂停类"） | — | — | — |
| 51 | `0x33` | — | **保留值，不再产生** | — | — | — |
| 52 | `0x34` | `REJ_TASK_CANCELLED` | 上次任务被"取消"过，开关拉不起来 | 上次任务已取消，请重新选择模式 | Previous task was cancelled, please select a mode again | 引导重新选模式 |
| 53 | `0x35` | `REJ_BUSY` | 设备正忙 / 半启动态（兜底） | 设备正忙，请稍后重试 | Device busy, please try again later | 稍后重试 |
| 54 | `0x36` | `REJ_ON_PILE_LOW_SOC` | **在桩且电量 <70%**：不出桩割草，已进"在桩等待充电" | **机器电量小于70%，已进入充电等待** | **Battery below 70%, waiting to charge at the dock** | **无需重发**（充满到 90% 自动出发） |

> `54` 的两处触发：① 待机在桩发 `DP3=smart`（电量 <70%）② 已在"在桩等待"中再发 `DP3=smart`（电量仍 <70%）。

### 3.4 参数/协议类（`0x40 ~ 0x4F`）

| 十进制 | 十六进制 | 宏 | 触发条件 | 中文文案 | English |
|---|---|---|---|---|---|
| 64 | `0x40` | `REJ_BAD_ENUM` | 枚举值非法/越界 | 参数不在允许范围内 | Invalid parameter value |
| 65 | `0x41` | `REJ_BAD_LENGTH` | 长度不合法（DP101≠88B、DP103≠25B、DP114≠10 字符等） | 数据长度不正确 | Invalid data length |
| 66 | `0x42` | `REJ_PARSE_FAIL` | 解析失败（内容不合法） | 数据格式不正确 | Invalid data format |
| 67 | `0x43` | `REJ_BAD_TYPE` | DP 类型不符（如 bool DP 按 enum 下发） | 数据类型不匹配 | Data type mismatch |
| 68 | `0x44` | `REJ_NOT_WRITABLE` | 该 DP **只上报不可下发** | 该功能不支持设置 | This parameter is read-only |
| 69 | `0x45` | `REJ_TIME_SYNC_OFF` | DP106 自动同步关闭时下发 DP114 | 请先开启自动同步 | Please enable auto time sync first |
| 70 | `0x46` | `REJ_UNKNOWN_DPID` | 设备不认识的 DP 号 | 设备不支持该功能 | Unsupported feature |
| 255 | `0xFF` | `REJ_UNSPECIFIED` | 未归类拒绝（兜底） | 操作未生效（码 {code}） | Command not applied (code {code}) |

---

## 4. 按 DP 分的拒绝点清单

### 4.1 DP2 `switch_go`

> 判定按**代码实际执行顺序**；顺序不同会得到不同的码。

| 下发 | 场景 | 码 |
|---|---|---|
| `true` / `false` | 已关机 | `16` |
| `true` | 故障态 + 门禁①不过 | `26` |
| `true` | 故障态 + 门禁①过 + **无**继续位（复位后落待机启动） | `52` / `48` |
| `true` | 急停 + 按钮未松开 | `23` |
| `true` | 急停 + 急停期有故障 | `26` |
| `true` | 急停 + 盖子未关 | `21` |
| `true` | **待机 + NORMAL**（无进行中作业） | `48` |
| `true` | **待机 + 上次任务被取消** | `52` |
| `true` | 盖子开（**非待机**） | `21` |
| `false` | 故障态 | `26`（**拒绝且不做任何事**，"暂停"不承担清除职责） |
| `false` | 待机 + 已在急停 | `19` |
| `false` | 待机 / 自检期 | `17` / `48`（仅静音） |
| `false` | 等关盖（待机 + PREPARE_WORK） | `21` |
| `false` | **在桩等待** | `49`（+ 静音，不打断等待状态机） |
| `false` | 已在急停（非待机） | `19` |
| `false` | 其它未覆盖模式 | `19` / `21` / `53` |

> ⚠️ **待机时盖开不会回 `21`**：`true` 分支里"待机判定"在"盖子判定"之前 ⇒ 会先回 `48`/`52`。

### 4.2 DP3 `mode`

| 下发 | 场景 | 码 |
|---|---|---|
| 任意 | 枚举不在 0~3 | `64` |
| 任意 | 关机 | `16` |
| 任意 | 自检窗口 | `17` |
| 任意 | OTA 会话中 | `18` |
| 任意 | 故障态且清不掉 | `26` |
| `2` | **在桩（`is_pile` 充电会话为真）** | **`32`**（**先于一切硬门**，含在桩等待中） |
| `2` | 线外 / 骑线（左右传感器非全 INSIDE） | **`33`**（先于硬门） |
| `1/2` | 回充中（低电回桩） | `34` |
| `1/2` | 回充中（雨天回桩） | `35` |
| `1` | 待机野外 + 界外 | `33` |
| `1` | 未锁定/丢信号 | `24` / `25` |
| `1` | **在桩 + 电量 <70%** | **`54`** |
| `1` | **在桩等待 + 有雨** | **`35`** |
| `1` | 在桩等待 + 其它不可放行情况 | `49` |
| `0` | **在桩等待** | `49`（不打断等待状态机） |
| `2` | **在桩等待但 `is_pile` 为假**（如已充满仅挂桩） | `49` |
| `3` | **在桩**（含等待/已触桩/待机在桩） | `32` |
| 任意 | 半启动态（等关盖等） | `21` / `53` |

> ⚠️ **DP3 各分支的判定顺序不同**：
> - `smart`/`standby`：先判模式（在桩等待/幂等），再判硬门
> - `spot`：先判 **`is_pile`** + 位置门，再判硬门 ⇒ **在桩等待时若仍在充电会话中，回的是 `32` 而不是 `49`**
> - `goto_charge`：先判硬门，再判 `tuya_on_pile_get()`（在桩 ⇒ `32`）

### 4.3 DP101 `mow_schedule`

| 场景 | 码 |
|---|---|
| 长度 ≠ 88 | `65` |
| 解析失败 | `66` |
| 组 0 标志置位但两时段都非法 | `64` |
| 有效时段时长 ≤ 10 分钟 | `65` |
| 落盘失败 | `3` |

### 4.4 DP103 `zone_config`

| 场景 | 码 |
|---|---|
| 长度 ≠ 25 | `65` |
| 解析失败 | `66` |
| 区号不在 1~5 | `64` |
| 各区百分比之和 > 100 | `64` |
| 落盘失败 | `3` |

### 4.5 DP114 `device_time`

| 场景 | 码 |
|---|---|
| 长度 ≠ 10 或首位为 `0` | `65` |
| 含非数字 / 数值溢出 | `66` |
| 时间过早（< 2001-09） | `64` |
| DP106 自动同步关闭 | `69` |
| 落盘失败 | `3` |

### 4.6 设置类 DP（102/104/105/106/107/108/109/110/119）

| 场景 | 码 |
|---|---|
| DP107 时区越界（>24） | `64` |
| DP109 语言越界（>17） | `64` |
| DP110 落盘失败 | `66` |
| **DP105 雨后延迟越界** | ⚠️ **不限界拒绝**，限幅到 120 后回 `code=0` |
| **DP119 工作时间越界** | ⚠️ **不拒绝**，限幅到 1/24 后回 `code=0` |

### 4.7 只上报的 DP（下发必拒）

`5` / `13` / `18` / `111` / `112` / `113` / `115` / `116` / `117` / `118` / `120` ⇒ 一律 `68`

> DP 号不在产品表内 ⇒ `70`；DP 号认识但类型不符 ⇒ `67`。

---

## 5. 特殊规则

### 5.1 `26 REJ_FAULT_ACTIVE` 的定位方法（**App 必须实现**）

收到 `26` 时，读 **DP111 `fault_alarm`** 的 `device` 与 `error` 两层，剩下的位就是"还没排除的故障"：

```
DP111 = {"device":<u32>,"error":<u32>,"function":<u32>,"circularize":<u32>}

device 层（硬件类，优先级 P0）  —— 位定义见 alarm.h device_e
  bit0  电池      0x0001
  bit1  IMU       0x0002
  bit2  FLASH     0x0004
  bit3  左电机    0x0008
  bit4  右电机    0x0010
  bit5  刀盘电机  0x0020

error 层（安全/位置类，优先级 P1 > P2）  —— 位定义见 alarm.h error_e
  bit0  位姿翻倒        0x0001
  bit1  抬起            0x0002
  bit2  边界            0x0004
  bit3  左电机过流      0x0008
  bit4  左电机过温      0x0010
  bit5  左电机霍尔      0x0020
  bit6  右电机过流      0x0040
  bit7  右电机过温      0x0080
  bit8  右电机霍尔      0x0100
  bit9  刀盘过流        0x0200
  bit10 刀盘过温        0x0400
  bit11 刀盘霍尔        0x0800
  bit12 刀盘堵转        0x1000
  bit13 不在计划时段    0x2000
  bit14 圈外            0x4000
  bit15 定点出界        0x8000
```

> ⚠️ **位序以 `alarm.h` 的 `error_e` 为准**（16 位）。旧文档里"bit6 左过流 / bit19 圈外"这类编号是**错的**，不要照抄。

**文案优先级**：**P0 硬件类 > P1 安全类（位姿/抬起）> P2 位置类（边界/圈外/定点出界）**
**示例**：`device=0x00000001, error=0x00000000` ⇒ 文案应为"电池异常未排除"，而不是"机器故障"。

> 例外说明：丢信号超时后 `error` 层会补出一个"边界"位 —— 若同时 `circularize` 有丢信号位，按"边界信号丢失"提示。

### 5.2 回显规则

| 类型 | 拒绝时是否回显 | 回显什么 |
|---|---|---|
| 动作类（DP2 / DP3） | ✅ 回显 | DP2 ⇒ 真实开关值（多为 `0`）；DP3 ⇒ 真实模式值 |
| 参数类（其它 DP） | ❌ 不回显 | — |

> APP 必须用回显值刷新控件，否则开关/模式控件会卡在用户点的位置。

### 5.3 OTA 期间

| 项 | 行为 |
|---|---|
| 所有 DP 上报 | **全静默**（DP116 除外） |
| 任何 DP 下发 | 一律 `18 REJ_OTA_BUSY` |
| OTA 自身状态 | DP116：`"7"`=拒绝（非待机），`"20"`=失败 |
| 升级成功 | 设备重启 ⇒ 连云 ⇒ DP112 版本变化 + 全量首报 |

### 5.4 幂等也算成功

| 场景 | 结果 |
|---|---|
| 已在割草中再发 `DP3=smart` | `code=0` |
| 已在回充中再发 `DP3=goto_charge` | `code=0` |
| 已待机再发 `DP3=standby` | `code=0` |
| 作业中发 `DP2=true` | `code=0` |

> 成功码不细分（`0x01 RES_ALREADY` 保留未用）。

---

## 6. 文案速查（可直接给平台配置）

> 建议平台按 `code` 配"值等于"推送规则；下面是推荐文案。

| code | 中文 | English |
|---|---|---|
| 3 | 操作未生效，请重试 | Operation failed, please retry |
| 16 | 机器已关机 | Machine is off |
| 17 | 开机自检中，请稍候 | Self-test in progress, please wait |
| 18 | 固件升级中，暂不接受操作 | Firmware updating, please wait |
| 19 | 机器处于急停状态 | Machine is in emergency stop |
| 21 | 请合上盖子 | Please close the cover |
| 22 | 机器已锁定 | Machine is locked |
| 23 | 请松开急停按钮 | Please release the emergency stop button |
| 24 | 机器正在寻找边界线，请稍候 | Searching for the boundary wire |
| 25 | 边界信号丢失，请检查边界线 | Boundary signal lost, check the wire |
| 26 | （按 §5.1 出具体故障名） | (see §5.1) |
| 32 | 机器已在充电桩上 | Machine is on the dock |
| 33 | 机器在界外，请移回界内 | Machine is outside the boundary |
| 34 | 电量低，正在充电 | Battery low, charging |
| 35 | 雨天暂停中，雨停后自动继续 | Paused due to rain |
| 48 | 请先选择工作模式 | Please select a work mode first |
| 49 | 机器在桩等待中 | Machine is waiting at the dock |
| 52 | 上次任务已取消，请重新选择模式 | Previous task was cancelled, please select again |
| 53 | 设备正忙，请稍后重试 | Device busy, please try again later |
| **54** | **机器电量小于70%，已进入充电等待** | **Battery below 70%, waiting to charge at the dock** |
| 64 | 参数不在允许范围内 | Invalid parameter value |
| 65 | 数据长度不正确 | Invalid data length |
| 66 | 数据格式不正确 | Invalid data format |
| 67 | 数据类型不匹配 | Data type mismatch |
| 68 | 该功能不支持设置 | This parameter is read-only |
| 69 | 请先开启自动同步 | Please enable auto time sync first |
| 70 | 设备不支持该功能 | Unsupported feature |
| 255 | 操作未生效（码 {code}） | Command not applied (code {code}) |

---

## 7. 本版（V1.0）相对旧文档的改动

| # | 改动 |
|---|---|
| 1 | **新增 `54 REJ_ON_PILE_LOW_SOC`**（2026-10-22） |
| 2 | 在桩等待中发割草：有雨时由 `49` 改为 **`35`**；电量 <70% 时由 `49` 改为 **`54`**（2026-10-22） |
| 3 | 在桩充电等待 + 电量 ≥70% + 无雨 ⇒ **不再拒绝**（`code=0`，出桩割草） |
| 4 | 明确 **DP105 / DP119 是限幅不是拒绝**（旧文档未提） |
| 5 | 明确 `0x32 / 0x33` 为**保留值不再产生** |
| 6 | 明确 `0x16 REJ_LOCKED` **当前固件不产生** |
| 7 | 合并了此前分散在 5 份文档里的码表（完整交接文档 / 实施方案总纲 / 重新分析 / 改造记录 / 给App团队说明） |
