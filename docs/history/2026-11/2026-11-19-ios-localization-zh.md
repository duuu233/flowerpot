# iOS 声明简体中文本地化：涂鸦名称按中文返回

> 文档类型：Historical Change Record
> 日期：2026-11-19；环境：远程 SSH 服务器
> 分支与起始版本：main / 3cf96eb

## 依据与范围

产品反馈：iOS 设备列表显示「Flower Pot Test」，涂鸦平台上的产品名是「YUSEN-智能花盆」，Android 一直正常。产品先提出「先查我们自己的接口有没有改过名，没改过再读涂鸦名称」，随后要求参考 Android 的做法。

## 核对结果

- **后端接口**：线上接口文档（`/v2/api-docs`）里，App 能用的 `/Client` 接口都没有设备名称字段。`/Client/UserProduct/getUserProductList`、`getUserProductDetail` 只读实测都返回 500，和不存在的路径一样（已有接口未登录时返回 406「请重新登录」）。`editUserProduct` 也不在文档里了。带 `productName` 的只有管理后台接口 `/ZoneAdmin/Product/getUserProductList`。`FlowerpotState._backendDevices` 从来没有被填充，所以改名时「同步后端」那一步实际不会执行。目前没有接口能查出用户是否改过名。
- **Android 做法**：设备列表和 iOS 是同一份 Dart 代码，名称都取涂鸦 SDK 设备名。Android 原生 `deviceMap` 取的是 `DeviceBean.getName`，没有查后端。
- **两端差别**：涂鸦 SDK 按 App 的语言请求云端。Android 跟随系统语言；iOS 工程只声明了英文（`developmentRegion = en`，`knownRegions` 只有 en / Base，`Info.plist` 没有 `CFBundleLocalizations`），所以中文系统的 iPhone 上，App 的本地化也会落到英文。涂鸦因此返回产品英文名「Flower Pot Test」，设备名、按产品 ID 查到的产品名都会受影响。这与「Android 正常、iOS 是英文名」的现象一致，但还没有在真机上证实。

## 改动

- `ios/Runner/Info.plist` 增加 `CFBundleLocalizations`：`zh-Hans`、`en`。
- `ios/Runner.xcodeproj/project.pbxproj` 的 `knownRegions` 增加 `zh-Hans`。

效果与 Android 一致：iPhone 系统语言为简体中文时，App 本地化为中文，涂鸦请求也按中文；系统语言为英文时，仍按英文。Flutter 的 `flutter_localizations` 在 iOS 上同样需要这项声明。显示规则没改：仍取涂鸦设备名，设备名为空时用按产品 ID 查到的产品名。

## 待在真机上核对

用中文系统的 iPhone 装新包，打开联调日志看「设备列表快照」：

- 「按产品 ID 查涂鸦产品名」应变为「YUSEN-智能花盆」。
- 已经用英文激活的设备，如果涂鸦设备名仍是「Flower Pot Test」，说明涂鸦把设备名固定在激活时的语言了。这种情况需要改名，或解绑后重新配网。

## 验证

服务器上没有 Xcode / Flutter，未编译，也未在真机上验证。用 `plistlib` 解析过 `Info.plist`，确认格式正确。

## 回滚

撤销本次提交即可。
