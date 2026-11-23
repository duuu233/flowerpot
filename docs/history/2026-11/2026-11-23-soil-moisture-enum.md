# 土壤湿度 DP106 改为枚举、去掉土壤湿度曲线

> 文档类型：Historical Change Record
> 日期：2026-11-23；环境：远程 SSH 服务器
> 分支与起始版本：main / fe646d3

## 依据与范围

产品口径：

- DP106 `soil_moist` 土壤湿度：只上报（ro），枚举型，枚举值 dry、moderate。
- 土壤湿度数据、历史数据等都不再上报，取消土壤湿度历史数据曲线图。
- 需水状态页按枚举显示内容，不做具体数值。

范围确认：改的是需水状态页里的土壤湿度（DP106 只在这一页显示）；相对湿度页显示的是空气湿度 114 / 115 / 165，不改。枚举文字：dry = 干燥，moderate = 适中，没上报显示「--」。

## 改动

- 模型：新增 `SoilMoisture { dry, moderate }`，`DeviceStatusReport.soilMoisture` 存 106 的档位；`SensorSnapshot.soilMoisture` 数值字段与 `SensorMetric.soilMoisture` 删除。
- 解析：`MethodChannelTuyaRepository` 用 `reported('soil_moist', …)` 认 dry / moderate，其余值（含旧固件的数值）按没上报。`TuyaConfig.history` 去掉 soilMoisture，134–136 不再解码；`TuyaConfig.dp` 保留 134–136 行，只为与平台导出逐行对照。
- 文案：`TuyaStatusCopy.soilMoistureLabel`（干燥 / 适中 / --，英文 Dry / Moderate）。
- 需水状态页：「当前土壤湿度」显示档位文字，不带单位；曲线只剩「水仓水位变化」，去掉指标切换下拉；进页历史体检只查水位；首页进需水状态页不再指定初始指标。
- 状态层：日视图实时接点表去掉 106；报表页（当前无入口）去掉土壤湿度一项。
- 调试信息页电池说明里的历史 DP 范围改为 131–133、137–139。
- 测试：各处 `SensorSnapshot` 去掉土壤湿度数值；`water_status_page_test` 改为断言显示「适中」、没有百分号、只有水位曲线且无切换菜单；`status_page_dps_test` 新增 106 枚举解析与文字用例、历史键去掉 soilMoisture；`device_updates_test` 改用枚举值；Mock 设备报 moderate。

## 未改

- 相对湿度页（空气湿度）及其 165 曲线。
- 帮助中心「为什么土壤湿度没有变化？」条目。
- 首页四张状态卡（不含土壤湿度）。

## 验证

服务器上没有 Flutter / Dart，未编译、未运行 analyze 与测试、未真机。需要本地运行 `dart analyze lib test` 与 `flutter test`（重点 `test/features/devices/water_status_page_test.dart`、`test/tuya/status_page_dps_test.dart`、`test/tuya/device_updates_test.dart`），真机进入需水状态页确认土壤湿度显示「干燥 / 适中」、下方只有水仓水位曲线。

## 回滚

还原本次提交即可；设备侧 106 若仍报数值，回滚后按数值显示。
