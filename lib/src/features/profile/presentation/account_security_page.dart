import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../../auth/presentation/password_page.dart';
import '../models/account_security_page_model.dart';
import 'login_password_page.dart';
import 'modify_password_page.dart';
import 'widgets/account_security_card.dart';

class AccountSecurityPage extends StatelessWidget {
  const AccountSecurityPage({super.key, this.pageModel});

  final AccountSecurityPageModel? pageModel;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final model = pageModel ?? AccountSecurityPageModel.fromUser(state.user);

    return AppPageScaffold(
      appBar: const AppPageHeader(title: '账号与安全', leading: AppBackButton()),
      background: AppPageBackground.account,
      body: SingleChildScrollView(
        key: const Key('account-security-scroll-view'),
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            32,
            AppSpacing.pageMargin,
            40,
          ),
          child: AccountSecurityCard(
            model: model,
            onPhoneTap: state.busy
                ? null
                : () => showAppMessage(
                    context,
                    '手机号修改功能暂未开放',
                    tone: AppMessageTone.info,
                  ),
            onLoginPasswordTap: state.busy
                ? null
                : () => _openLoginPasswordPage(context),
            onChangePasswordTap: state.busy
                ? null
                : () => _openModifyPasswordPage(context),
            onForgotPasswordTap: state.busy
                ? null
                : () => _openPasswordPage(
                    context,
                    title: '忘记密码',
                    returnToLoginOnSuccess: true,
                  ),
          ),
        ),
      ),
    );
  }

  void _openLoginPasswordPage(BuildContext context) {
    Navigator.pushNamed(
      context,
      AppRoutes.loginPassword,
      arguments: LoginPasswordArguments(
        account: FlowerpotScope.of(context).user?.account ?? '',
      ),
    );
  }

  void _openModifyPasswordPage(BuildContext context) {
    final account = FlowerpotScope.of(context).user?.account ?? '';
    Navigator.pushNamed(
      context,
      AppRoutes.modifyPassword,
      arguments: ModifyPasswordArguments(
        account: account,
        region: account.contains('@')
            ? LoginRegion.overseas
            : LoginRegion.domestic,
      ),
    );
  }

  void _openPasswordPage(
    BuildContext context, {
    required String title,
    bool returnToLoginOnSuccess = false,
  }) {
    final account = FlowerpotScope.of(context).user?.account ?? '';
    Navigator.pushNamed(
      context,
      AppRoutes.password,
      arguments: PasswordArguments(
        account: account,
        region: account.contains('@')
            ? LoginRegion.overseas
            : LoginRegion.domestic,
        title: title,
        returnToLoginOnSuccess: returnToLoginOnSuccess,
      ),
    );
  }
}
