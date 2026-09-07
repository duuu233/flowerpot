# 设备详情页入口门禁与 DP 162 植物确认握手

> 文档类型：Historical Change Record
> 日期：2026-09-07
> 环境：SSH（Linux dev box，无 Flutter SDK）
> 分支与起始版本：main / 48b4b23
> 范围：DP 表（09-07 导出 + 163 占位）、设备列表入口、设备详情页、设备设置页、`FlowerpotState` 植物相关方法
> 当前权威文档：`AI_CONTEXT.md`、`docs/TUYA_SDK_SETUP.md`

## 背景与目标

产品提出设备详情页入口的三条交互（植物为空直跳添加、植物不一致要确认、离线不许进），核对时 09-03 的功能点表里没有「植物确认」。改按新提供的 `docs/智能花盆test(yciq4kssu1fv8umn)_09_07.xlsx` 实现：该导出在 101–160 之外追加了 161 `plant_type`（enum 1/2/3）和 162 `plant_confirm`。随后产品把 162 从 bool 改成数值并补齐了完整握手（0 正常 / 1 异常 / 2 确认 / 3 忽略、两级弹窗、设备先报状态后报植物），另外要求设备设置页加一个「自动检测植物」纯开关，以及添加植物时把 161 和 116 一起下发。

## 变更内容

- `TuyaConfig.dp` 换到 09-07 导出，补 161、162；另加**本地占位**的 163 `plant_detect_switch`（平台尚未导出）。新增 `TuyaConfig.plantTypes` / `plantTypeValue` 和 `setting['plantDetection']`。
- `PlantConfirmState`（0/1/2/3）替代原来的 bool；`SmartPlanterDevice.plantConfirm`、`DeviceControlSettings.plantDetection`、`PlantProfile.plantType` 三个字段落地，`MethodChannelTuyaRepository` 从 162/163 解码。
- `HttpAppBackendRepository._plant` 解析植物分类，字段名按 `plantType` / `plantTypeId` / `plantCategory` / `categoryId` 兜底。
- `FlowerpotState`：
  - `hasPlant` 改成以 DP 116 是否为空为准；
  - 新增 `plantConfirmState`、`plantDetectionEnabled`、`answerPlantConfirm`（下发 2 或 3）、`ensurePlantProfile`（按 116 补齐后端植物静态内容）；
  - `_publishPlantSelection` 取代 `_publishPlantVariety`，把 116 和 161 打包进同一条 `publishDps`；
  - `_applyDeviceUpdate` 遇到目录里没有的新标识符时补拉一次目录，`_unresolvedPlantIdentifiers` 防止为同一个对不上的标识符反复打接口；
  - `updateSetting` 支持 `plantDetection`。
- `DeviceListPage._openDevice`：离线设备提示「请打开设备并保持在线」并拦下；DP 116 为空的设备直接推 `plantPicker`（add 模式）；其余推详情页。
- `HomePage` 改成 `StatefulWidget`，首帧后跑入口检查：162 为 1 且自动检测未关时走两级弹窗（确认/忽略 → 各自二次确认 → 下发 2/3），之后再 `ensurePlantProfile`。
- 设备设置页在「选择植物」下面多一行纯开关「自动检测植物」：`DeviceSettingsMenuItem.toggle` 非空的行画 Switch 而不是箭头，`DeviceSettingsFunctionList` 多了 `onToggle` / `togglesBusy`。
- 测试：DP 表断言改成 63 条 / 101–163 并覆盖 `plantTypeValue` 与 `plantDetection` 编码；`state_backend_integration_test` 断言 116+161 同批下发、以及没有分类时只发 116；设备列表用例改成「无植物直接进添加植物」并新增离线拦截；新增 `home_plant_confirm_test.dart` 覆盖确认/忽略的两级弹窗、二次确认取消、检测关闭、162 正常、116 为空共六种情况。

### 同日追加：107/108/113/115 状态文案

产品给了四条状态功能点的「枚举值 → 短标签 + 一句说明」，短标签显示在状态页顶部、说明在它下面。落地方式：

- 新增 `lib/src/tuya/tuya_status_copy.dart`，键是涂鸦导出的枚举值本身，另带四个兜底判据（107 看水仓水位 DP 105、108 看照度、113 看换算后的 18–28 ℃、115 看相对湿度）。
- 四个 `*_status_page_model.dart` 的 `status`/`description` 改成读这张表，`advice` 跟着改成按枚举分档（湿度那条原来无论干湿都写「当前湿度适宜」，和上面的状态文字直接打架）。
- `HomeDashboardModel` 的三张状态卡片和养护建议横幅也改成同源。原来首页按传感器读数自己算一套（需浇水/偏湿/偏弱），和状态页的判据、阈值、措辞全都对不上；光照的阈值两边甚至不一样（首页 500、状态页 200）。
- 需水的兜底从「土壤湿度」改成「水仓水位」：三档文案说的都是水仓。
- 光照 `very_good` 不再当警告。原来 >1200 lux 会弹「光照偏强，注意避开正午的直射阳光」，但按 DP 108 的定义那是光合效率最高的好状态（晒太阳中）。

## 关键决策

- **162 缺省按 0（正常）**。DP 没上报过时值是 null 不是 1，按异常处理会让所有旧固件设备每次进详情页都被问一次。判据严格取「上报了 1」。同理 163 未上报时按「开」，那是设备的默认行为。
- **App 只下发 2 和 3**，0 和 1 是设备的判定结果，`answerPlantConfirm` 里用 assert 挡住其余取值。
- **确认/忽略都不在本地改植物**。162 写下去之后由设备重新上报 116（确认）或回报旧值（忽略），App 一律等上报再更新，显示的才是设备真正在用的那一株。写失败保持异常状态，下次进详情页再问。
- **161 必须和 116 同批下发**。分开发会让设备短暂拿到「新品种 + 旧分类」。后台没配分类时只发 116，并把这件事写进 `ActionResult.message`——分类是设备的养护策略输入，猜一个比缺一个更糟。
- **`hasPlant` 换判据**。原来只看 `_plantedDevices`，那个集合要等 116 的标识符解析成 `PlantProfile` 才会加进去；冷启动后目录还没拉时有植物的设备会被判成空，配上「为空直接跳添加植物」就会把用户直接推进添加流程。
- **确认后自动补拉植物目录**。设备重新上报的 116 可能是 App 目录里还没有的标识符，不补拉的话页面会停在旧植物。用 `_unresolvedPlantIdentifiers` 兜住「拉了也对不上」的情况，避免每次上报都打一次接口。
- **163 用占位 DP 号**。产品要的开关必须能点，平台导出还没有这条；写成占位 + TODO，比等导出把整个功能拖住、或者把开关做成纯本地状态都好。
- **「未添加植物」页保留但不再经过**。`HomeDashboardScene.withoutPlant` 和 `HomeUnplantedContent` 留在代码里（Figma 有这张画板，组件测试也在用），只是主动线不再走它。

## 外部操作

无。只读解析了 `docs/智能花盆test(yciq4kssu1fv8umn)_09_07.xlsx`、`assets/智能花盆功能列表.xlsx` 和 `docs/智能花盆1.0开发方案.docx`，没有调用任何接口或写入外部系统。

## 验证结果

**未验证。** 本机没有 Flutter/Dart SDK（`which flutter dart` 无输出），`flutter analyze` 与 `flutter test` 都跑不了。以上改动是静态写就的，新增的测试用例本身也没有执行过。需要在有 SDK 的机器或 CI 上补跑：

```bash
flutter analyze
flutter test test/tuya_config_test.dart \
             test/tuya_status_copy_test.dart \
             test/state_backend_integration_test.dart \
             test/features/devices/device_list_page_test.dart \
             test/features/devices/device_settings_page_test.dart \
             test/features/devices/water_status_page_test.dart \
             test/features/devices/light_status_page_test.dart \
             test/features/devices/temperature_status_page_test.dart \
             test/features/devices/humidity_status_page_test.dart \
             test/features/home/home_plant_confirm_test.dart
```

## 未完成项与风险

- **163 的 DP 号和标识符是猜的**，平台补完导出前不能真机验证自动检测开关。
- **植物分类的后端字段名未确认**。swagger 没有模型，代码按四个常见命名兜底；后台真正落哪个字段之前，161 大概率发不出去（只发 116，页面会带一句说明）。
- 162 置回 0 的时机由固件决定（处置完成后？重新上报 116 之后？）。设备如果一直停在 2 或 3，App 不会再弹——这是期望行为；但如果设备把值停在 1，用户每次进详情页都会被问一次。
- 第一级弹窗的系统返回键和「忽略」都返回 null，两者都走忽略分支。真正的闸门是第二级，返回键最多让用户多看一个可取消的确认框，但严格说这两个动作在语义上被合并了。
- 离线拦截会连带挡住详情页里离线仍可用的入口：解绑/恢复出厂（`state.dart` 里明确「设备离线或拒绝时不阻断解绑」）、报表缓存、纪念日后端列表。目前离线用户没有解绑路径，需要产品确认是维持整页拦截，还是改成放进页面、把控制类操作置灰。
- `online` 来自 `getDevices` 快照与 SDK 推送，列表上的值可能是旧的，只在点击那一刻判一次会有误拦。
- 设备详情页首屏画的是固定的花盆插画，后端植物图片与引导文案实际显示在植物详情页和设置页的植物行；「按 116 补齐静态内容」影响的是后面这两处。

## 回滚或恢复

- 回滚 `device_list_page.dart` 的 `_openDevice` 与 `home_page.dart` 的入口检查即可恢复原来的「点进去先看未添加植物空状态页、不判在线」动线。
- 回滚植物确认时要连着撤掉 `TuyaConfig.dp` 的 161–163、`PlantConfirmState`、设置页开关和 `tuya_config_test.dart` 的 63 条断言，不要只删页面逻辑留下半张 DP 表。
- `hasPlant` 的判据改动和 `_publishPlantSelection` 的 116+161 打包可以单独保留：前者修的是冷启动误判，后者是独立的下发契约。
