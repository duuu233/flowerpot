import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../core/config/debug_tools_config.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../models/mine_page_model.dart';
import 'widgets/mine_menu_list.dart';
import 'widgets/mine_profile_header.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key, this.pageModel, this.showBackButton = true});

  final MinePageModel? pageModel;

  /// The shell renders this page as a bottom tab, where a back button would
  /// have nothing to pop.
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final model = pageModel ?? MinePageModel.fromUser(state.user);

    return AppPageScaffold(
      appBar: AppPageHeader(
        title: '我的',
        leading: showBackButton ? const AppBackButton() : null,
        automaticallyImplyLeading: showBackButton,
        // A live session skips the login page on start-up, so the SDK console
        // needs a way back in that does not require logging out.
        actions: DebugToolsConfig.enabled
            ? <Widget>[
                IconButton(
                  key: const Key('mine-tuya-debug-entry'),
                  tooltip: '涂鸦 SDK 联调',
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.tuyaDebug),
                  icon: const Icon(Icons.bug_report_outlined),
                ),
              ]
            : null,
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
                  maxWidth: 375,
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    AppSpacing.xxxl,
                    20,
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 375),
                    child: MineMenuList(
                      items: model.menuItems,
                      height: panelHeight,
                      onItemTap: (kind) => _openItem(context, kind),
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

  void _openItem(BuildContext context, MineMenuKind kind) {
    final route = switch (kind) {
      MineMenuKind.personalInfo => AppRoutes.profile,
      MineMenuKind.accountSecurity => AppRoutes.settings,
      MineMenuKind.helpCenter => AppRoutes.help,
      MineMenuKind.privacyPolicy => AppRoutes.privacy,
      MineMenuKind.userAgreement => AppRoutes.agreement,
      MineMenuKind.about => AppRoutes.about,
      MineMenuKind.feedback => null,
    };
    if (route != null) {
      Navigator.pushNamed(context, route);
      return;
    }
    // No real feedback address exists yet; showing the placeholder as if it
    // were a mailbox is worse than saying so.
    showAppMessage(context, '意见反馈渠道尚未配置', tone: AppMessageTone.info);
  }
}
