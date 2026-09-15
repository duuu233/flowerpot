import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../devices/presentation/device_list_page.dart';
import '../../home/presentation/home_page.dart';
import '../../profile/models/about_page_model.dart';
import '../../profile/presentation/widgets/app_update_dialog.dart';

/// Root screen after login.
///
/// There is no bottom tab bar: the device list is the home screen, and it
/// falls back to the "no device yet" screen until a planter is bound. Both
/// pages put the profile entry behind the avatar in their header, which pushes
/// the profile page as an ordinary route, so device pages stack on top of this
/// screen instead of replacing a tab.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 强制升级弹窗只弹一次：弹窗关不掉，重复 show 会叠出好几层。
  bool _updateDialogShown = false;

  @override
  void initState() {
    super.initState();
    // App 打开就问一次版本：强制升级要当场挡住，提示升级要在「我的 → 关于」
    // 那一行点红点。查不到、后端没开都无声跳过。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAppVersion());
  }

  Future<void> _checkAppVersion() async {
    if (!mounted) return;
    final state = FlowerpotScope.of(context);
    await state.checkAppVersion(AboutPageModel.current().version);
    if (!mounted || _updateDialogShown || !state.mustUpdateApp) return;
    final version = state.appVersion;
    if (version == null) return;
    _updateDialogShown = true;
    await showAppUpdateDialog(context, version: version, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    // 手机没网、设备列表没读出来时不能落到「添加设备」页——那等于告诉用户账号下
    // 没设备。进设备列表，由它画无网络缺省页（2026-09-15 产品）。
    final showList = state.devices.isNotEmpty || state.deviceLoadOffline;
    return showList ? const DeviceListPage() : const HomePage();
  }
}
