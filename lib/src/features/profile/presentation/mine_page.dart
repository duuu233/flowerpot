import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
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

class _MinePageState extends State<MinePage> with NetworkRetryAware<MinePage> {
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
      // 意见反馈那一行的邮箱来自后台「系统设置」里配的平台邮箱。**每次进页面都重拉**
      // （2026-09-21）：基础数据原来一次会话只拉一次，后台改了邮箱要重启 App 才看得到。
      state.loadBasicData(refresh: true);
    });
  }

  /// 「网络异常」弹窗点「重试」：进页面拉的两样再拉一遍。
  @override
  Future<void> reloadForNetworkRetry() async {
    final state = FlowerpotScope.of(context);
    await Future.wait<void>(<Future<void>>[
      state.refreshUserInfo(),
      state.loadBasicData(refresh: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final model =
        widget.pageModel ??
        MinePageModel.fromUser(
          state.user,
          feedbackEmail: state.basicData.platformEmail,
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
    final route = switch (kind) {
      MineMenuKind.personalInfo => AppRoutes.profile,
      MineMenuKind.accountSecurity => AppRoutes.settings,
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

  /// 复制平台邮箱：这一行没有可跳的页面，用户要的就是把地址拿走。
  Future<void> _copyEmail(BuildContext context, String email) async {
    await Clipboard.setData(ClipboardData(text: email));
    if (!context.mounted) return;
    showAppMessage(context, '邮箱已复制：$email');
  }
}
