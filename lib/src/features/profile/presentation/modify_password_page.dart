import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../../auth/presentation/password_page.dart';
import '../models/modify_password_page_model.dart';
import 'widgets/account_password_form_card.dart';

class ModifyPasswordArguments {
  const ModifyPasswordArguments({
    this.account = '',
    this.region = LoginRegion.domestic,
  });

  final String account;
  final LoginRegion region;
}

typedef ChangeLoginPassword =
    Future<ActionResult> Function(String oldPassword, String newPassword);

class ModifyPasswordPage extends StatefulWidget {
  const ModifyPasswordPage({
    required this.arguments,
    super.key,
    this.pageModel,
    this.onChangePassword,
  });

  final ModifyPasswordArguments arguments;
  final ModifyPasswordPageModel? pageModel;
  final ChangeLoginPassword? onChangePassword;

  @override
  State<ModifyPasswordPage> createState() => _ModifyPasswordPageState();
}

class _ModifyPasswordPageState extends State<ModifyPasswordPage> {
  final oldPasswordController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmationController = TextEditingController();
  bool oldPasswordVisible = false;
  bool passwordVisible = false;
  bool confirmationVisible = false;
  bool saving = false;

  ModifyPasswordPageModel get model =>
      widget.pageModel ?? const ModifyPasswordPageModel();

  @override
  void dispose() {
    oldPasswordController.dispose();
    passwordController.dispose();
    confirmationController.dispose();
    super.dispose();
  }

  void _openForgotPassword() {
    Navigator.pushNamed(
      context,
      AppRoutes.password,
      arguments: PasswordArguments(
        account: widget.arguments.account,
        region: widget.arguments.region,
        title: '忘记密码',
        returnToLoginOnSuccess: true,
      ),
    );
  }

  Future<void> _confirmChange() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final oldPassword = oldPasswordController.text;
    final password = passwordController.text;
    if (oldPassword.isEmpty) {
      showAppMessage(context, '请输入原密码', tone: AppMessageTone.error);
      return;
    }
    if (!model.hasValidLength(password)) {
      showAppMessage(
        context,
        '密码长度需为${model.minimumLength}-${model.maximumLength}位字符',
        tone: AppMessageTone.error,
      );
      return;
    }
    if (password != confirmationController.text) {
      showAppMessage(context, '两次输入的密码不一致', tone: AppMessageTone.error);
      return;
    }

    final changePassword = widget.onChangePassword;
    if (changePassword == null) {
      showAppMessage(context, '修改密码功能暂未开放', tone: AppMessageTone.info);
      return;
    }

    setState(() => saving = true);
    final result = await changePassword(oldPassword, password);
    if (!mounted) return;
    setState(() => saving = false);
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
    if (result.success) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '修改密码', leading: AppBackButton()),
      background: AppPageBackground.account,
      body: SingleChildScrollView(
        key: const Key('modify-password-scroll-view'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            28,
            AppSpacing.pageMargin,
            40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AccountPasswordFormCard(
                fields: <AccountPasswordField>[
                  AccountPasswordField(
                    controller: oldPasswordController,
                    label: '原密码',
                    hintText: '请输入原密码',
                    visible: oldPasswordVisible,
                    visibilityKey: const Key('old-password-visibility'),
                    onVisibilityChanged: () => setState(
                      () => oldPasswordVisible = !oldPasswordVisible,
                    ),
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.password],
                  ),
                  AccountPasswordField(
                    controller: passwordController,
                    label: '密码',
                    hintText: '请输入密码',
                    visible: passwordVisible,
                    visibilityKey: const Key('modify-password-visibility'),
                    onVisibilityChanged: () =>
                        setState(() => passwordVisible = !passwordVisible),
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.newPassword],
                  ),
                  AccountPasswordField(
                    controller: confirmationController,
                    label: '确认密码',
                    assetPath: AppAssets.accountPasswordConfirmIcon,
                    hintText: '请确认密码',
                    visible: confirmationVisible,
                    visibilityKey: const Key(
                      'modify-password-confirmation-visibility',
                    ),
                    onVisibilityChanged: () => setState(
                      () => confirmationVisible = !confirmationVisible,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _confirmChange(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('modify-password-forgot'),
                  onPressed: _openForgotPassword,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.textSecondary,
                    textStyle: AppTypography.body.copyWith(fontSize: 15),
                  ),
                  child: const Text('忘记密码?'),
                ),
              ),
              const SizedBox(height: 157),
              FilledButton(
                key: const Key('confirm-modify-password'),
                onPressed: saving ? null : _confirmChange,
                child: saving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.surface,
                        ),
                      )
                    : const Text('确认修改'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
