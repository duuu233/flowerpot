# 智能花盆 App

Flutter 智能花盆客户端，技术架构沿用 `D:\Work\learn\flutter`：feature-first 业务分层、统一命名路由、全局 `ChangeNotifier` 状态、公共 UI 组件和原生 MethodChannel 桥接。

项目默认运行在体验模式，不需要密钥即可检查全部页面和交互。接入涂鸦平台参数后，通过 `--dart-define=TUYA_ENABLED=true` 切换到 Smart Life App SDK。

## 运行

```powershell
D:\Work\Flutter\flutter\bin\flutter.bat pub get
D:\Work\Flutter\flutter\bin\flutter.bat run
```

真实 SDK 模式：

```powershell
D:\Work\Flutter\flutter\bin\flutter.bat run --dart-define=TUYA_ENABLED=true
```

## 文档

- [项目结构](PROJECT_STRUCTURE.md)
- [PRD 功能落地清单](docs/PRD_IMPLEMENTATION.md)
- [涂鸦 SDK 配置](docs/TUYA_SDK_SETUP.md)

## 当前边界

本仓库实现 PRD 的 iOS/Android App。PRD 中的 PC 管理后台、Java 服务端和 PC 官网属于独立交付物，本仓库仅预留其需要的数据接口边界，不将多套工程混入 Flutter 项目。
