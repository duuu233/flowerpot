import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';

class PasswordArguments {
  const PasswordArguments({
    this.account = '',
    this.region = LoginRegion.domestic,
    this.title = '忘记密码',
    this.returnToLoginOnSuccess = true,
  });

  final String account;
  final LoginRegion region;
  final String title;
  final bool returnToLoginOnSuccess;
}

class PasswordPage extends StatefulWidget {
  const PasswordPage({required this.arguments, super.key});

  final PasswordArguments arguments;

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  late final TextEditingController accountController;
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmationController = TextEditingController();
  bool passwordVisible = false;
  bool confirmationVisible = false;

  LoginRegion get region => widget.arguments.region;

  @override
  void initState() {
    super.initState();
    accountController = TextEditingController(text: widget.arguments.account);
  }

  @override
  void dispose() {
    accountController.dispose();
    codeController.dispose();
    passwordController.dispose();
    confirmationController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final result = await FlowerpotScope.of(
      context,
    ).sendCode(account: accountController.text, region: region, type: 3);
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  Future<void> _submit() async {
    if (passwordController.text.length < 6) {
      showAppMessage(context, '新密码至少需要 6 位', tone: AppMessageTone.error);
      return;
    }
    if (passwordController.text != confirmationController.text) {
      showAppMessage(context, '两次输入的密码不一致', tone: AppMessageTone.error);
      return;
    }

    final result = await FlowerpotScope.of(context).resetPassword(
      account: accountController.text,
      newPassword: passwordController.text,
      code: codeController.text,
      region: region,
    );
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
    if (result.success) {
      if (widget.arguments.returnToLoginOnSuccess) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.auth,
          (_) => false,
        );
      } else {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final domestic = region == LoginRegion.domestic;
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: widget.arguments.title,
        leading: const AppBackButton(),
      ),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        child: ResponsiveContent(
          maxWidth: 375,
          padding: const EdgeInsets.fromLTRB(28, 72, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PasswordField(
                controller: accountController,
                hintText: domestic ? '请输入手机号' : '请输入邮箱',
                icon: domestic
                    ? Icons.phone_iphone_rounded
                    : Icons.mail_outline_rounded,
                keyboardType: domestic
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                readOnly: widget.arguments.account.isNotEmpty,
              ),
              const SizedBox(height: AppSpacing.lg),
              _PasswordField(
                controller: codeController,
                hintText: '请输入验证码',
                icon: Icons.verified_user_outlined,
                keyboardType: TextInputType.number,
                suffix: _CodeButton(busy: state.busy, onPressed: _sendCode),
              ),
              const SizedBox(height: AppSpacing.lg),
              _PasswordField(
                controller: passwordController,
                hintText: '请输入密码',
                icon: Icons.lock_open_outlined,
                keyboardType: TextInputType.visiblePassword,
                obscureText: !passwordVisible,
                suffix: IconButton(
                  key: const Key('reset-password-visibility'),
                  tooltip: passwordVisible ? '隐藏密码' : '显示密码',
                  onPressed: () =>
                      setState(() => passwordVisible = !passwordVisible),
                  icon: Icon(
                    passwordVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _PasswordField(
                controller: confirmationController,
                hintText: '请确认密码',
                icon: Icons.lock_outline_rounded,
                keyboardType: TextInputType.visiblePassword,
                obscureText: !confirmationVisible,
                suffix: IconButton(
                  key: const Key('reset-confirmation-visibility'),
                  tooltip: confirmationVisible ? '隐藏密码' : '显示密码',
                  onPressed: () => setState(
                    () => confirmationVisible = !confirmationVisible,
                  ),
                  icon: Icon(
                    confirmationVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: 155),
              FilledButton(
                onPressed: state.busy ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: AppColors.surface,
                  shape: const StadiumBorder(),
                  textStyle: AppTypography.pageTitle.copyWith(
                    color: AppColors.surface,
                  ),
                ),
                child: state.busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.surface,
                        ),
                      )
                    : const Text('确认'),
              ),
              const SizedBox(height: 240),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.keyboardType,
    this.obscureText = false,
    this.readOnly = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool readOnly;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        readOnly: readOnly,
        style: AppTypography.body,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
            fontSize: 15,
          ),
          prefixIcon: Icon(icon, color: AppColors.brandPrimary, size: 22),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
          border: const OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: AppRadius.full,
          ),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: AppRadius.full,
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.brandPrimary),
            borderRadius: AppRadius.full,
          ),
        ),
      ),
    );
  }
}

class _CodeButton extends StatelessWidget {
  const _CodeButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(
          height: 30,
          child: VerticalDivider(color: AppColors.divider),
        ),
        TextButton(
          onPressed: busy ? null : onPressed,
          child: const Text(
            '获取验证码',
            style: TextStyle(color: AppColors.brandPrimary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}
