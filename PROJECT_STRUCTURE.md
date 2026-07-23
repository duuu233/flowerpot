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
    │   └── network/
    ├── tuya/
    │   ├── tuya_config.dart
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
        ├── devices/presentation/
        └── profile/presentation/
```

应用图片统一放在 `assets/images/`，该目录已在 `pubspec.yaml` 注册。

## 关键约定

1. 页面不直接调用原生 SDK。所有调用经过 `TuyaRepository`，因此可在体验数据与真实 SDK 之间切换。
2. 产品功能点集中在 `TuyaConfig.dp`。拿到真实 PID 的 DP 定义后只修改该映射。
3. Android 与 iOS 通过同名 MethodChannel `com.flowerpot.smart/tuya` 对齐。
4. AppKey、AppSecret 和安全组件不进入 Git；Android 使用 `local.properties`，iOS 使用未跟踪的 `Tuya.xcconfig`。
5. REST 请求统一经过 `core/network/ApiClient`，页面不得直接发起 HTTP 请求。
6. 设备图片同步依赖硬件 PID 的文件传输协议；统计报表依赖涂鸦设备数据统计服务或自有后端，未开通时返回明确配置错误。
