# 登录页隐藏微信快捷登录（iOS / Android）

> 文档类型：Historical Change Record
> 日期：2026-11-19；环境：远程 SSH 服务器
> 分支与起始版本：main / b24d638

## 依据与范围

产品：iOS 端隐藏微信快捷登录，先不删除代码；随后补充：Android 端也不需要。

## 改动

- `LoginEntryConfig.wechatLogin` 由 true 改为 false，两端同时隐藏。按钮、回调和图标资源都保留，以后恢复只需把这一行改回 true。
- `LoginEntryConfig.anySocialLogin`：微信、支付宝快捷登录都关闭时，登录页不再显示「其他登录方式」分隔线和那一行空的快捷登录区。
- `test/features/auth/auth_page_test.dart`：改为断言微信图标与「其他登录方式」都不显示。

## 验证

服务器上没有 Flutter，未编译、未运行测试。需要在本地运行 `flutter test test/features/auth/auth_page_test.dart`。

## 回滚

`wechatLogin` 改回 true 即可恢复，分隔线会随之出现。
