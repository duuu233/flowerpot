# 接入 PID orhqsdjyigmh8bwa 的真实功能点表

> 文档类型：Historical Change Record
> 日期：2026-08-20
> 环境：SSH
> 分支与起始版本：main / 020f0ef
> 范围：`lib/src/tuya/`、设备设置与状态页、相关测试与文档
> 当前权威文档：`docs/TUYA_SDK_SETUP.md` 第 4 节与第 6 节

## 背景与目标

配网链路此前已经跑通，但 `TuyaConfig.dp` 里的 101–123 是占位编号，值类型和倍率都没有对过，真机上任何 DP 读写都不会成立。产品方提供了 PID `orhqsdjyigmh8bwa`（智能花盆test）2026-08-20 导出的功能点表（`assets/智能花盆test(orhqsdjyigmh8bwa)_08_20.xlsx`，DP 101–150 共 50 条），本次把这张表接到已有功能上。

## 变更内容

- `TuyaConfig.dp` 重写为 50 条真实功能点，键改为涂鸦标识符本身，可与平台导出逐行对照；新增 `dpScale`、`setting`、`history`、`historySampleBytes`、`temperatureUnits`、`calibrationSteps` 与编码函数 `settingDps`。
- 读路径按真实 id 重写：温度（112）与湿度（114）倍数 1，读除以 10；电量、充电、固件版本（148）、硬件版本（149）、陪伴天数（102）、植物品种（116）、设备状态（101）改为取 DP。
- 设备自报的五个状态枚举（104/107/108/113/115）接入电量、水位、光照、温度、湿度五个状态页，设备没报时回落到原有阈值判断，界面文案不变。
- 作息时间从「一条字符串 DP」改为两条分钟数 DP（126/127、129/130），App 内仍是 `HH:MM-HH:MM`，两头换算。
- 温标改用 enum `C`/`F`（146）；水位校准改用 enum `step0`–`step5`（140），校准弹窗改为逐步下发、中途取消发 `step5`。
- 新增 `TuyaHistoryCodec` 解码 131–139 的 raw 历史包，`getDevices` 时就地解码并缓存，`getHistory` 从这份快照取；不再调用云端统计服务。
- 删除没有对应功能点的 `weatherService`；「修复系统文件」改为提示「系统修复暂未开放」，不再下发不存在的 DP。
- 新增 `touch_vib_switch`(123)、`touch_plant_vib_switch`(124) 到设置模型，可读可写，界面暂未提供开关。

## 关键决策

- DP 表以涂鸦标识符为键，而不是 App 语义名。换 PID 或改功能点时整表重导，避免逐行手改导致的漂移；App 语义名通过 `TuyaConfig.setting` / `history` 两张小表转接。
- 缺功能点时 `settingDps` 返回 `null`，App 报 `unsupported_dp`。把「还没接」和「设备拒绝」分开，避免下发一条注定失败的指令。
- 状态枚举采用「设备优先、阈值兜底」。新绑定的设备还没上报枚举，直接改成只信 DP 会让状态页空白。
- raw 历史包解析失败按「暂无历史」处理，不抛异常：图表本来就有空态，设备升级期间不应让状态页崩掉。
- 校准步骤映射（弹窗第 N 步 → `stepN`）是按「步骤」和 step5 取消推断的，导出件没有写每个枚举值采样哪一阶段。映射集中在 `TuyaConfig.calibrationSteps`，确认后改一行即可。

## 外部操作

无。功能点表由产品方提供，未调用涂鸦平台接口，未改动密钥、安全组件或签名材料。

## 验证结果

未执行。本机没有 Flutter/Dart 工具链（`flutter`、`dart` 均不存在，`find /` 未找到 SDK），无法运行 `flutter analyze`、`flutter test` 或构建。改动经人工逐文件复核与括号配对检查，但**没有编译验证**。

## 未完成项与风险

- 需在有工具链的机器上执行 `flutter analyze` 与 `flutter test`，再上真机联调。
- 校准步骤枚举映射待固件确认。
- 设备 DP 实时上报仍未接（`IDevListener` + 事件通道）。表接进来后这项更关键：电量、水位、光照、五个状态枚举和全部历史包都是只上报。
- 温度、湿度、电量三条趋势曲线没有历史 DP，真机上会是空曲线。
- 142/143/144 图片链路与 `uploadAnimation` 现有实现不匹配（142 收 URL 而非本地文件），未接入。

## 回滚或恢复

单次提交内完成，`git revert` 即可。回滚后 DP 表退回占位编号，真机 DP 读写会重新失效。
