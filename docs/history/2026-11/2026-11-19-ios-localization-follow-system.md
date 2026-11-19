# iOS 本地化改为跟随系统语言（中文兜底）

> 文档类型：Historical Change Record
> 日期：2026-11-19；环境：远程 SSH 服务器
> 分支与起始版本：main / b8fe84d

## 依据与范围

产品最终口径：按系统语言自适应。系统中文时，涂鸦返回中文名；系统英文时，返回英文名。b8fe84d 的「只声明中文」作废。

## 改动

- `Info.plist`：`CFBundleLocalizations` 由只有 `zh-Hans` 改为 `zh-Hans`、`en`。`CFBundleDevelopmentRegion` 保持 `zh-Hans`，系统语言既不是中文也不是英文时用中文。
- `project.pbxproj` 不变：`developmentRegion = "zh-Hans"`，`knownRegions` 为 en、Base、zh-Hans。

## 验证

服务器上没有 Xcode / Flutter，未编译，也未在真机上验证。用 `plistlib` 解析过 `Info.plist`，确认格式正确。真机核对方法见 `2026-11-19-ios-default-chinese.md`：看联调日志「设备列表快照」里的「按产品 ID 查涂鸦产品名」。

## 回滚

撤销本次提交即可。撤销后恢复为只声明中文。
