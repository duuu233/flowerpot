# 植物分类字段名确认与四条建议展示

> 状态：Historical
> 日期：2026-09-08
> 环境：SSH 开发机
> 分支与起始版本：main / 65c8715
> 范围：后端植物详情解析、`PlantProfile` 模型、植物详情页

## 变更

### 1. 植物分类字段名已确认为 `categoryType`

`app_backend_repository.dart` 的 `_plant` 里那条 **TODO(后端)** 关掉了。原来字段名未定，按
`plantType` / `plantTypeId` / `plantCategory` / `categoryId` 四个常见命名依次兜底；后端本轮确认
实际字段是 **`categoryType`**（`1` 水培、`2` 适中、`3` 耐旱），四个猜测名全部删除，只读
`row['categoryType']`。

下游一个字没改：值仍进 `PlantProfile.plantType`，绑定植物时由
`FlowerpotState._publishPlantSelection` 经 `TuyaConfig.plantTypeValue` 换算后下发 DP 161
（`plant_type`）。范围外或缺失仍是 `null`，此时只下发 DP 116，不猜分类。

⚠️ 之前那四个名字后端从来没返回过，也就是说**在此之前分类恒为 null、DP 161 实际上一直没下发过**。
本轮起后台配了分类就会真的下发到设备，这是行为变化，需要真机复核。

### 2. 新增四条建议文案的读取与展示

`PlantProfile` 新增四个 String 字段（默认空串）：`lightingSuggestion`、`waterSuggestion`、
`temperatureSuggestion`、`humiditySuggestion`，分别读后端的 `lightingSuggestions`、
`waterSuggestion`、`temperatureSuggestion`、`humiditySuggestion`，并加进 `copyWith`。

⚠️ 与既有的 `*Requirement` 不是一回事：`temperatureRequirement` / `humidityRequirement` /
`lightingRequirement` 读的是后台的「适宜温度 / 适宜湿度 / 光照需求等级」，是阈值区间与等级；
这四条是后台单独维护、给用户看的建议文案。两组都在，不要互相替代。

植物详情页「基础信息」卡片在「生长特点」下面按顺序追加四行：光照建议 / 需水建议 / 空气温度建议 /
湿度建议。**没有本地兜底**：`_byId` 的六个写死植物与 `_generic` 都留空串，后台没配就整行不渲染，
不拿阈值区间冒充建议。`hasBackendDetail` 把这四个字段也算进去——只配了建议、别的都空的植物
也要走后端分支，否则会整页回落到写死数据。

## 同步与验证

修改前在 main 执行 `git pull --ff-only`，结果 Already up to date，未切分支。

⚠️⚠️ **本轮完全没有验证**：SSH 开发机没有 Flutter / Dart SDK，`flutter analyze`、`flutter test`、
`dart format` 一个都没跑，改动是纯静态编写。恢复到有 SDK 的机器后**必须先补跑**
`flutter analyze --no-pub lib/src` 与 `flutter test`，再谈可用。本机也没有 CodeGraph 索引。

真机未验。需要复核的两点：① 后台配了分类后 DP 161 真的下发且设备接受；② 四条建议在详情页的
排版与缺失时的留白。

## 后续与回滚

后台侧同批改动见 `flowerpot-web/docs/history/2026-09/2026-09-08-plant-category-and-suggestions.md`。
需要回滚时 revert 本次提交，DP 下发链路与既有 `*Requirement` 字段均未改动。
