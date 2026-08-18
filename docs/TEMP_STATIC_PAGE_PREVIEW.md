# 静态演示构建

## 用途

当前构建用于向他人演示整体 UI 效果：走真实的导航链路，但后端是 Mock，账号下没有任何已绑定设备，
因此可以从「登录 → 无设备 → 配网 → 设备列表 → 选择植物 → 设备详情」完整走一遍。

早期的「页面场景调试目录」已移除，App 启动直接进入登录页。

## 演示动线

1. **登录页**：输入任意手机号 + 任意验证码，勾选协议后登录。两个输入框都不能为空，除此之外不做校验：即使真实 SDK 拒绝，也会退回演示会话并提示「未通过涂鸦验证，已进入演示会话」，此后所有数据都来自 Mock 后端。

   登录页当前只保留手机验证码入口。密码登录、支付宝快捷登录由 `lib/src/features/auth/login_entry_config.dart` 关闭（对应平台参数尚未具备），微信入口保留但参数待配置，底部的「涂鸦 SDK 联调」入口保留用于真实链路验证。要恢复某个入口，把 `LoginEntryConfig` 里对应的常量改回 `true` 即可。

   只剩一种登录方式时，面板顶部不再画双 Tab（否则一半有文案一半空着），也不加标题，直接从输入框开始；面板底色改成整块白卡、不画 Tab 缺口。登录按钮下方原来的「没有账户？去注册」入口改成一句说明：「输入验证码即登录，未注册手机将自动创建账户」。`_LoginTabs` 与缺口绘制的代码都保留在原处，把 `passwordLogin` 改回 `true` 就会自动切回 Tab 形态；注册页路由 `/register` 仍在，只是登录页不再有入口。
2. **登录后无设备**：没有底部菜单，首页直接是设备列表；无设备时显示「暂无设备」页。
3. **添加设备**：搜索设备 → 选择设备 → 连接 Wi-Fi → 连接成功（「已完成」回到首页）。
4. **设备列表**：绑定设备后首页即设备列表；左上角头像进入「我的」（普通路由，可返回），右上角是添加设备。
5. **设备详情**：点击设备先进入「未添加植物」，选择植物后进入详情页；两页左上角都是返回按钮。

## 页面归属

| 位置 | 页面 |
| --- | --- |
| 首页（无设备） | `HomePage` → `HomeEmptyDeviceContent` |
| 首页（有设备） | `DeviceListPage` |
| 我的（左上角头像推入） | `MinePage` |
| 设备页（未添加植物） | `HomePage(scene: withoutPlant, showBackButton: true)` |
| 设备页（详情） | `HomePage(scene: withCompanionSummary, showBackButton: true)` |

## 相关文件

- `lib/src/features/preview/preview_config.dart`：演示模式开关。
- `lib/src/features/shell/presentation/shell_page.dart`：首页在「无设备」与设备列表之间分流。
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
