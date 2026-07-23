import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import '../models/login_password_page_model.dart';
import 'widgets/account_password_form_card.dart';
import 'widgets/login_password_account_card.dart';
import 'widgets/login_password_advice_card.dart';

class LoginPasswordArguments {
  const LoginPasswordArguments({this.account = ''});

  final String account;
}

typedef SaveLoginPassword = Future<ActionResult> Function(String password);

class LoginPasswordPage extends StatefulWidget {
  const LoginPasswordPage({
    required this.arguments,
    super.key,
    this.pageModel,
    this.onSave,
  });

  final LoginPasswordArguments arguments;
  final LoginPasswordPageModel? pageModel;
  final SaveLoginPassword? onSave;

  @override
  State<LoginPasswordPage> createState() => _LoginPasswordPageState();
}

class _LoginPasswordPageState extends State<LoginPasswordPage> {
  final passwordController = TextEditingController();
  final confirmationController = TextEditingController();
  bool passwordVisible = false;
  bool confirmationVisible = false;
  bool saving = false;

  LoginPasswordPageModel get model =>
      widget.pageModel ??
      LoginPasswordPageModel.fromAccount(widget.arguments.account);

  @override
  void dispose() {
    passwordController.dispose();
    confirmationController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final password = passwordController.text;
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

    final save = widget.onSave;
    if (save == null) {
      showAppMessage(context, '登录密码设置功能暂未开放', tone: AppMessageTone.info);
      return;
    }

    setState(() => saving = true);
    final result = await save(password);
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
      appBar: const AppPageHeader(title: '登录密码', leading: AppBackButton()),
      background: AppPageBackground.account,
      body: SingleChildScrollView(
        key: const Key('login-password-scroll-view'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ResponsiveContent(
          maxWidth: 375,
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LoginPasswordAccountCard(model: model),
              const SizedBox(height: 12),
              AccountPasswordFormCard(
                fields: <AccountPasswordField>[
                  AccountPasswordField(
                    controller: passwordController,
                    label: '密码',
                    hintText: '请输入密码',
                    visible: passwordVisible,
                    visibilityKey: const Key('login-password-visibility'),
                    onVisibilityChanged: () =>
                        setState(() => passwordVisible = !passwordVisible),
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.newPassword],
                  ),
                  AccountPasswordField(
                    controller: confirmationController,
                    label: '确认密码',
                    hintText: '请确认密码',
                    visible: confirmationVisible,
                    visibilityKey: const Key(
                      'login-password-confirmation-visibility',
                    ),
                    onVisibilityChanged: () => setState(
                      () => confirmationVisible = !confirmationVisible,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _savePassword(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: LoginPasswordAdviceCard(model: model),
              ),
              const SizedBox(height: 70),
              FilledButton(
                key: const Key('save-login-password'),
                onPressed: saving ? null : _savePassword,
                child: saving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.surface,
                        ),
                      )
                    : const Text('保存密码'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
