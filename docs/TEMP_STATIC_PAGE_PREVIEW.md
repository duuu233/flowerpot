# 静态演示构建

## 用途

当前构建用于向他人演示整体 UI 效果：走真实的导航链路，但后端是 Mock，账号下没有任何已绑定设备，
因此可以从「登录 → 无设备 → 配网 → 设备列表 → 选择植物 → 设备详情」完整走一遍。

早期的「页面场景调试目录」已移除，App 启动直接进入登录页。

## 演示动线

1. **登录页**：输入任意手机号 + 任意验证码，勾选协议后登录（Mock 仓库不校验手机号格式）。
2. **登录后无设备**：底部菜单出现「首页 / 我的」；首页 Tab 在无设备时显示该页。
3. **添加设备**：搜索设备 → 选择设备 → 连接 Wi-Fi → 连接成功（「已完成」回到首页）。
4. **设备列表**：绑定设备后首页 Tab 即为设备列表；左上角是个人中心入口，右上角是添加设备。
5. **设备详情**：点击设备先进入「未添加植物」，选择植物后进入详情页；两页左上角都是返回按钮。

## 页面归属

| 位置 | 页面 |
| --- | --- |
| 底部 Tab「首页」（无设备） | `HomePage` → `HomeEmptyDeviceContent` |
| 底部 Tab「首页」（有设备） | `DeviceListPage` |
| 底部 Tab「我的」 | `MinePage(showBackButton: false)` |
| 设备页（未添加植物） | `HomePage(scene: withoutPlant, showBackButton: true)` |
| 设备页（详情） | `HomePage(scene: withCompanionSummary, showBackButton: true)` |

## 相关文件

- `lib/src/features/preview/preview_config.dart`：演示模式开关。
- `lib/src/features/shell/presentation/shell_page.dart`：底部菜单与首页 Tab 分流。
- `lib/src/features/home/presentation/home_page.dart`：三种首页/设备页形态与 `HomeDeviceArguments`。
- `lib/src/features/home/presentation/widgets/home_header.dart`：左上角个人中心入口与返回按钮的切换。
- `lib/src/routes/app_routes.dart`：命名路由，含 `deviceHome`。

## 恢复正式数据

`StaticPreviewConfig.enabled` 只控制 Mock 后端是否预置一台演示设备，不再影响启动入口或鉴权：

```dart
// lib/src/features/preview/preview_config.dart
static const bool enabled = false;
```

置为 `false` 后，Mock 仓库重新预置 `planter-demo-01`，登录后直接进入设备列表。
启动入口、鉴权分流和页面导航在两种取值下完全一致。
