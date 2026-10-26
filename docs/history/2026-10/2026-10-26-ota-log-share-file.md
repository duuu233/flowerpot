# OTA 调试日志改为分享文件

> 文档类型：Historical Change Record
> 日期：2026-10-26；环境：远程 SSH 服务器
> 分支与起始版本：main / c44a8c4

## 依据与范围

用户确认：联调日志框「OTA日志」不再复制到剪贴板（日志长时受 Android 剪贴板约 1MB 与聊天软件消息长度限制），改为调起系统分享把日志文件当附件发到微信 / QQ / 邮件，手机可打开、可传到电脑端。

## 改动

- `OtaDebugLog.exportForShare`：把 `ota_logs/` 下保留的 `ota-YYYY-MM-DD.log` 按日期从旧到新合并成 `ota_logs/share/ota-log-<日期_时分秒>.txt`，文件头含导出时间、App 版本、平台与包含的文件；每次导出先删除上一次的导出目录；没有日志返回 null。用 `.txt` 便于微信 / QQ 在手机上预览。
- 联调日志框「OTA日志」：导出后 `SharePlus.instance.share(ShareParams(files: [XFile(.., text/plain)]))`；没有日志提示先做一次升级；分享出错提示原因与文件路径。去掉剪贴板复制。
- `pubspec.yaml` 新增 `share_plus: '>=11.0.0 <14.0.0'`（11 起 SharePlus API）；pubspec.lock 未更新。
- 测试：`ota_debug_log_test` 增导出用例（无日志为 null、合并顺序、文件头、旧导出删除、文件名）。

## 验证

本机无 Flutter，测试、analyze、编译均未运行；未真机。`git diff --check` 通过。需 `flutter pub get` 确认 share_plus 解析到与 Flutter 3.44 / 其它插件兼容的版本。

## 回滚

还原对应提交并移除 share_plus 依赖。
