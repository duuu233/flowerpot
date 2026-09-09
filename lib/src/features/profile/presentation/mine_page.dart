import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../models/mine_page_model.dart';
import 'widgets/mine_menu_list.dart';
import 'widgets/mine_profile_header.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key, this.pageModel, this.showBackButton = true});

  final MinePageModel? pageModel;

  /// The shell renders this page as a bottom tab, where a back button would
  /// have nothing to pop.
  final bool showBackButton;

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  @override
  void initState() {
    super.initState();
    // 昵称/头像以后端的 getUserInfo 为准：登录只拿到映射凭据，昵称字段可能还是
    // 空的，所以这一页进来就静默刷一次。以前只有「个人信息」页刷，于是首页显示
    // 「用户」、进个人信息再退回来才对——看着像 bug，其实是从没读过。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = FlowerpotScope.of(context);
      state.refreshUserInfo();
      // 意见反馈那一行的邮箱来自后台「基础信息配置」。
      state.loadBasicData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final model =
        widget.pageModel ??
        MinePageModel.fromUser(
          state.user,
          feedbackEmail: state.basicData.contact,
          hasAppUpdate: state.hasAppUpdate,
        );

    return AppPageScaffold(
      appBar: AppPageHeader(
        title: '我的',
        leading: widget.showBackButton ? const AppBackButton() : null,
        automaticallyImplyLeading: widget.showBackButton,
      ),
      background: AppPageBackground.standard,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelHeight = (constraints.maxHeight - 217)
              .clamp(440.0, double.infinity)
              .toDouble();
          return CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: ResponsiveContent(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageMargin,
                    AppSpacing.xxxl,
                    AppSpacing.pageMargin,
                    16,
                  ),
                  child: MineProfileHeader(
                    model: model,
                    onEdit: () =>
                        Navigator.pushNamed(context, AppRoutes.profile),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: double.infinity,
                    child: MineMenuList(
                      items: model.menuItems,
                      height: panelHeight,
                      onItemTap: (kind) => _openItem(context, kind, model),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openItem(BuildContext context, MineMenuKind kind, MinePageModel model) {
    if (kind == MineMenuKind.deviceSettings) {
      _openDeviceSettings(context);
      return;
    }
    final route = switch (kind) {
      MineMenuKind.personalInfo => AppRoutes.profile,
      MineMenuKind.accountSecurity => AppRoutes.settings,
      // 已在上面单独处理：它要带设备 id 才能跳。
      MineMenuKind.deviceSettings => null,
      MineMenuKind.privacyPolicy => AppRoutes.privacy,
      MineMenuKind.userAgreement => AppRoutes.agreement,
      MineMenuKind.about => AppRoutes.about,
      MineMenuKind.feedback => null,
    };
    if (route != null) {
      Navigator.pushNamed(context, route);
      return;
    }
    final email = model.menuItems
        .firstWhere((item) => item.kind == MineMenuKind.feedback)
        .trailingValue;
    if (email == null || email.isEmpty) {
      showAppMessage(context, '后台还没有配置平台邮箱', tone: AppMessageTone.info);
      return;
    }
    unawaited(_copyEmail(context, email));
  }

  /// 设备设置的另一个入口。
  ///
  /// 首页那排快捷操作只在「已绑定植物」的完整形态里渲染（见 `HomePage` 的三个
  /// 分支），设备刚配网还没选植物时进不去设备设置，也就够不到解绑和恢复出厂。
  /// 这里给一个不依赖首页形态的入口。
  void _openDeviceSettings(BuildContext context) {
    final device = FlowerpotScope.of(context).selectedDevice;
    if (device == null) {
      showAppMessage(context, '请先添加并连接花盆', tone: AppMessageTone.info);
      return;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.deviceSettings,
      arguments: device.id,
    );
  }

  /// 复制平台邮箱：这一行没有可跳的页面，用户要的就是把地址拿走。
  Future<void> _copyEmail(BuildContext context, String email) async {
    await Clipboard.setData(ClipboardData(text: email));
    if (!context.mounted) return;
    showAppMessage(context, '邮箱已复制：$email');
  }
}
