# 已绑定设备首页改用后台配置的植物图片

> 文档类型：Historical Change Record
> 日期：2026-09-09
> 环境：SSH
> 分支与起始版本：main / 559ba84
> 范围：`lib/src/features/home`
> 当前权威文档：`AI_CONTEXT.md`

## 背景与目标

要求：已绑定设备的首页和植物详情页，植物图片都取植物列表接口返回的那张（后台管理系统给这株植物配的），没有数据才用本地静态图，以接口给的为准。

## 变更内容

- `HomeDashboardModel` 增加 `plantImageUrl`，`fromDevice` 里取 `device?.plant?.imageUrl`——也就是 `Client/Product/getProductPlantList` 行里的 `plantImg`，由 `PlantProfile.imageUrl` 带过来。
- `HomePlantOverview` 正中那张 132×170 的图改由新的 `_PlantHeroImage` 渲染：字段有值就 `Image.network`，为空或加载失败（`errorBuilder`）才回落 `AppAssets.smartPlanterWithPlant`，尺寸、`BoxFit.contain` 与 `filterQuality` 保持不变。
- 植物详情页 `_PlantDetailArtwork` **本来就是这个口径**（`plant.imageUrl` 优先，失败回落 `AppAssets.plantImage(plant.id)`，未知 id 再退到通用图标），本次核对后未改。

## 关键决策

- 回落用的是首页原来那张「带植物的 YSplanter」静态图，不改成植物图鉴里的单株图：首页这张是设备主视觉，后台没配图时保持原样最不突兀。
- 没有动设备列表页 `_DeviceListCard` 里 48×62 的那张缩略图，它仍是静态图——需求说的是「首页-已绑定设备页面」，列表行是另一屏，改不改由维护者决定。

## 外部操作

无。

## 验证结果

- 本机（SSH 开发机）**没有 Flutter/Dart SDK**，`flutter analyze` 与 `flutter test` 均未执行。
- 新增 `test/features/home/home_plant_overview_test.dart`（未运行）：配了图片时控件树上挂的是带该 URL 的 `NetworkImage`；没配时画本地静态图且树上没有任何 `NetworkImage`。第一例刻意只断言控件树、且不多 pump 一帧——测试环境里 `Image.network` 必然加载失败，再 pump 就会走 `errorBuilder` 换成本地图。

## 未完成项与风险

- 需在有 SDK 的机器复跑 analyze/test，并在真机上确认后台配的图（尺寸、留白、透明底）放进 132×170 的容器里观感是否可接受——素材比例与那张静态图不同时可能偏小或偏扁。
- 加载中没有占位（保持与详情页一致），弱网下会先空一下再出图。
