# iOS 默认简体中文：涂鸦名称固定按中文返回

> 文档类型：Historical Change Record
> 日期：2026-11-19；环境：远程 SSH 服务器
> 分支与起始版本：main / fc77750

## 依据与范围

真机联调日志：手机系统语言为 `zh-Hans-US`，按产品 ID `ehbx83xdh9jkmxvz` 现查的涂鸦产品名、设备名都是「Flower Pot Test」。产品要求默认中文，效果与以前 Android 一致。

## 说明

App 代码没有给涂鸦传语种参数，涂鸦 iOS SDK 按 App 当前的本地化语言请求云端名称。工程原先只声明英文，所以 App 本地化落到英文，返回的是产品英文名。fc77750 改为同时声明中文和英文，但那样会跟随系统语言：英文系统的手机仍会拿到英文名。

## 改动

- `Info.plist`：`CFBundleDevelopmentRegion` 改为 `zh-Hans`，`CFBundleLocalizations` 只保留 `zh-Hans`，去掉 `en`。
- `project.pbxproj`：`developmentRegion` 改为 `zh-Hans`，`knownRegions` 保留 en、Base、zh-Hans。

改完后，不论手机是什么语言，App 的本地化都是简体中文，涂鸦 SDK 按中文请求；系统权限弹窗的按钮也显示中文，与 App 界面固定中文一致。Android 未改，仍跟随系统语言。

## 待在真机上核对

用 main 最新代码重新打包，打开联调日志看「设备列表快照」：「按产品 ID 查涂鸦产品名」应为「YUSEN-智能花盆」。

- 如果仍是「Flower Pot Test」，说明涂鸦 SDK 的请求语言不取自 App 本地化，或者平台上这个产品的中文名本身就是这个。需要对比 Android 同一账号的快照，并核对涂鸦平台的产品多语言名称。
- 已用英文激活的设备，涂鸦设备名可能仍是「Flower Pot Test」，需要改名或重新配网。

## 验证

服务器上没有 Xcode / Flutter，未编译，也未在真机上验证。用 `plistlib` 解析过 `Info.plist`，确认格式正确。

## 回滚

撤销本次提交，恢复 fc77750 的「中文 + 英文，跟随系统语言」。
