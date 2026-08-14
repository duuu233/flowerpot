import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../models/mine_page_model.dart';
import 'widgets/mine_menu_list.dart';
import 'widgets/mine_profile_header.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key, this.pageModel});

  final MinePageModel? pageModel;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final model = pageModel ?? MinePageModel.fromUser(state.user);

    return AppPageScaffold(
      appBar: const AppPageHeader(title: '我的', leading: AppBackButton()),
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
    final email = model.menuItems
        .firstWhere((item) => item.kind == MineMenuKind.feedback)
        .trailingValue;
    showAppMessage(
      context,
      '请发送反馈至 ${email ?? '客服邮箱'}',
      tone: AppMessageTone.info,
    );
  }
}
