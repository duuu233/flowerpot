# 网络异常与服务器异常分开：没网才弹框，服务器异常改 toast

> 文档类型：Historical Change Record
> 日期：2026-11-05；环境：远程 SSH 服务器
> 分支与起始版本：main / 5dad8c6

## 依据与范围

产品排查「网络异常」弹框：闪屏结束、回前台 2 秒后、接口请求失败 / 超时或涂鸦报错后，都只解析一次后端域名，单次解析失败或超过 3 秒就弹「当前网络不可用」。手机能上网但后端域名 DNS 异常、后端连不上时也会弹，属误报。要求：网络异常和服务器异常分开，不要笼统地用一个弹框处理；服务器异常直接用 toast，显示一段时间后自己隐藏。

## 改动

- `core/network/network_status.dart`：`NetworkStatus.probe` 改为「手机能不能上网」——后端域名与 `publicHosts`（www.baidu.com / www.qq.com / www.apple.com）同时解析，任一成功即有网，全部失败或超时（每个 3 秒）才算没网。新增 `serverProbe`（只解析后端域名，域名配错仍按能连）。`reportFailure` 带上来源 `NetworkFailureSource`：`backend`（ApiClient 重试用尽的连不上 / 超时，含上传）、`tuya`（`FlowerpotState._run` 收口的涂鸦报错，默认值）。
- `app/network_alert.dart`：查网后分三种——手机没网：照旧弹「网络异常」（取消 / 重试、配网动线不弹、盖着别的弹框先等、取消 3 秒冷却都不变）；手机有网且失败来自后端，或冷启动 / 回前台主动检查时后端域名解析不了：`AppToast.warn`「服务器异常，请稍后重试」（约 3 秒自动消失，`serverToastCooldown` 5 秒内只提示一次，配网动线同样不提示）；手机有网且是涂鸦报错：什么都不提示，页面自己的失败处理照常。
- `shared/widgets/app_toast.dart`：传入的是 Overlay 自身的 context（全局宿主拿的根 Navigator `overlay.context`，祖先里找不到这个 Overlay）时直接用它，否则 toast 静默不显示。
- `shared/l10n/app_l10n.dart`：新增 `serverErrorMessage`（服务器异常，请稍后重试 / Server error. Please try again later.）。
- 设备列表无网络缺省页仍用 `NetworkStatus.probe`，口径随之变为「手机真的没网」才进缺省页。

## 测试

- `test/app/network_alert_test.dart` 新增 4 个用例：有网时后端失败只出 toast、连续失败只提示一次、会自己消失；有网时涂鸦失败什么都不出；没网时后端失败仍弹框；冷启动有网但后端域名解析不了出 toast。
- `test/flutter_test_config.dart`：`serverProbe` 同 `probe` 一样统一换成恒为 true，不做真 DNS。

## 验证

本机没有 Flutter / Dart，未运行 `flutter analyze` / `flutter test`，未真机。改动文件只核对了括号配平与行宽。本地需跑：`flutter analyze`、`flutter test test/app/network_alert_test.dart test/features/devices/device_list_offline_test.dart`，真机核对：关 Wi-Fi 与蜂窝弹框；有网时把 `API_BASE_URL` 指向连不上的地址只出 toast。

## 未改

- 弹框出现后网络恢复不会自动关闭（报告第二节第 3 条），仍需点「重试」或「取消」。
- 刚切网 / 回前台网络未稳（第二节第 2 条）：回前台仍等 2 秒查一次；现在要后端域名和三个公共域名全部解析失败才判没网，误报会少，但未加二次确认。
- HTTP 非 2xx（如 502）不触发全局 toast，仍由页面按原来的文案提示（带状态码）。

## 回滚

`probe` 改回 `_resolveApiHost`，`network_alert.dart` 的 `_check` 去掉有网分支里的 `serverDown` 判断即回到原行为；`reportFailure` 的来源参数可保留。
