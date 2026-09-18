# 项目结构

项目采用与参考工程一致的 feature-first 架构。页面按业务域组织，涂鸦能力、共享组件、主题、路由和全局状态集中管理。

```text
lib/
├── main.dart
└── src/
    ├── app.dart
    ├── state.dart
    ├── app/
    │   ├── app_theme.dart
    │   └── flowerpot_app.dart
    ├── routes/app_routes.dart
    ├── core/
    │   ├── cache/image_cache_cleanup.dart
    │   ├── config/debug_tools_config.dart
    │   └── network/
    ├── tuya/
    │   ├── tuya_config.dart
    │   ├── tuya_history_codec.dart
    │   ├── tuya_models.dart
    │   └── tuya_repository.dart
    ├── shared/
    │   ├── shared.dart
    │   └── widgets/
    └── features/
        ├── auth/
        │   ├── domain/
        │   └── presentation/
        ├── home/presentation/
        ├── shell/presentation/
        ├── splash/presentation/splash_page.dart
        ├── devices/presentation/
        ├── devtools/presentation/tuya_debug_page.dart
        ├── mower/
        │   ├── mower_demo.dart
        │   └── presentation/
        └── profile/presentation/
```

应用图片统一放在 `assets/images/`，该目录已在 `pubspec.yaml` 注册。

## 关键约定

1. 页面不直接调用原生 SDK。所有调用经过 `TuyaRepository`，因此可在体验数据与真实 SDK 之间切换。
2. 产品功能点集中在 `TuyaConfig.dp`。拿到真实 PID 的 DP 定义后只修改该映射。
3. Android 与 iOS 通过同名 MethodChannel `com.common.yikaltd/tuya` 对齐。
4. AppKey、AppSecret 和安全组件不进入 Git；Android 使用 `local.properties`，iOS 使用未跟踪的 `Tuya.xcconfig`。
5. REST 请求统一经过 `core/network/ApiClient`，页面不得直接发起 HTTP 请求。
6. 设备图片同步依赖硬件 PID 的文件传输协议；统计报表依赖涂鸦设备数据统计服务或自有后端，未开通时返回明确配置错误。
7. `features/devtools/` 只服务于 SDK 联调，不属于产品动线；它同样经过 `FlowerpotState` 与 `TuyaRepository`，只是额外展示失败码。开关放在 `core/config/debug_tools_config.dart`。
8. `features/mower/` 是割草机（产品 `mz7g3yzaufvoh4ls`）。2026-09-18 起页面**按功能点接线**：`mower_dp.dart` 放 DP 表与 DP101/DP103 编解码，`mower_device.dart` 放当前 DP 值与唯一下发出口。⚠️ **没有真设备**：下发不经涂鸦 SDK，只写联调日志并本地回显；只读 DP 由长按电量环的模拟上报面板改。入口有两处（设备列表最后一张卡、搜索设备页列表下面那条），开关是 `MowerDemo.enabled`。
