# 临时静态页面调试入口

## 本次调整

为了集中调整静态页面样式，项目当前启用了临时“页面场景调试目录”：

- App 启动默认进入调试目录，不再根据登录状态进入登录页或首页。
- 目录按业务模块列出了现有页面；同一页面的重要状态（例如验证码/密码登录、有无设备、有无植物、配网成功/失败、水位/土壤湿度、空设备列表、植物绑定状态）均拆成独立入口。
- 有对应 `docs/UI/*.png` 的页面，目录标题与图片文件名（不含扩展名）保持一致；额外调试状态统一使用 `页面名-状态` 命名。
- UI 中不存在的旧“设备详情”页已移除；`植物详情.png` 对应目录中的“植物详情”，未绑定状态单列为“植物详情-未绑定”。
- 临时模式启动后自动进入本地演示模式并准备演示设备，设备、传感器、报表和设置页面可直接预览。
- 所有从目录打开的页面右下角均显示“返回目录”按钮；在页面内继续跳转后，该按钮仍然存在。
- 目录支持按页面名称或状态搜索。

## 相关文件

- `lib/src/features/preview/preview_config.dart`：临时模式总开关与演示设备 ID。
- `lib/src/features/preview/presentation/preview_hub_page.dart`：页面与状态目录。
- `lib/src/features/preview/presentation/preview_return_overlay.dart`：统一返回目录按钮。
- `lib/src/routes/app_routes.dart`：临时默认入口、鉴权旁路和返回按钮包装。
- `lib/src/app/flowerpot_app.dart`：临时模式下准备本地演示数据。

## 页面调试完成后恢复真实流程

将以下开关改为 `false` 即可恢复原有启动与鉴权流程：

```dart
// lib/src/features/preview/preview_config.dart
static const bool enabled = false;
```

关闭后：

1. 根路由重新按登录状态进入 `AuthPage` 或 `AppShell`。
2. 受保护路由重新启用登录鉴权。
3. 启动时不再自动进入演示模式。
4. 业务页面不再显示“返回目录”悬浮按钮。

预览目录代码无需立即删除，保留后可用于后续 UI 回归；若确定不再需要，可删除 `features/preview` 目录、本文档，并移除 `flowerpot_app.dart` 与 `app_routes.dart` 中对应引用。
