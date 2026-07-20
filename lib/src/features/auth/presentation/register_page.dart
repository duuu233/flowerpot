import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final accountController = TextEditingController();
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmationController = TextEditingController();
  bool passwordVisible = false;
  bool confirmationVisible = false;
  bool accepted = false;

  @override
  void dispose() {
    accountController.dispose();
    codeController.dispose();
    passwordController.dispose();
    confirmationController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final result = await FlowerpotScope.of(context).sendCode(
      account: accountController.text,
      region: LoginRegion.domestic,
      type: 1,
    );
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  Future<void> _register() async {
    if (!accepted) {
      showAppMessage(context, '请先阅读并同意用户协议与隐私政策', tone: AppMessageTone.error);
      return;
    }
    if (passwordController.text.length < 8) {
      showAppMessage(context, '密码至少需要 8 位', tone: AppMessageTone.error);
      return;
    }
    if (passwordController.text != confirmationController.text) {
      showAppMessage(context, '两次输入的密码不一致', tone: AppMessageTone.error);
      return;
    }
    final result = await FlowerpotScope.of(context).register(
      account: accountController.text,
      password: passwordController.text,
      code: codeController.text,
      region: LoginRegion.domestic,
    );
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
    if (result.success) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.shell, (_) => false);
    }
  }

  void _backToLogin() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.auth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '注册账号', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ResponsiveContent(
              maxWidth: 375,
              padding: const EdgeInsets.fromLTRB(28, 72, 28, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _RegisterField(
                    controller: accountController,
                    hintText: '请输入手机号',
                    icon: Icons.phone_iphone_rounded,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _RegisterField(
                    controller: codeController,
                    hintText: '请输入验证码',
                    icon: Icons.verified_user_outlined,
                    keyboardType: TextInputType.number,
                    suffix: _RegisterCodeButton(
                      busy: state.busy,
                      onPressed: _sendCode,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _RegisterField(
                    controller: passwordController,
                    hintText: '请输入密码',
                    icon: Icons.lock_open_outlined,
                    keyboardType: TextInputType.visiblePassword,
                    obscureText: !passwordVisible,
                    suffix: IconButton(
                      key: const Key('register-password-visibility'),
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
                  _RegisterField(
                    controller: confirmationController,
                    hintText: '请确认密码',
                    icon: Icons.lock_outline_rounded,
                    keyboardType: TextInputType.visiblePassword,
                    obscureText: !confirmationVisible,
                    suffix: IconButton(
                      key: const Key('register-confirmation-visibility'),
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
                    onPressed: state.busy ? null : _register,
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
                        : const Text('注册'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        '已有账户？',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      InkWell(
                        onTap: _backToLogin,
                        child: Text(
                          '去登录',
                          style: AppTypography.body.copyWith(
                            color: AppColors.brandPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 112),
                  _RegisterAgreement(
                    accepted: accepted,
                    onChanged: (value) => setState(() => accepted = value),
                    onAgreement: () =>
                        Navigator.pushNamed(context, AppRoutes.agreement),
                    onPrivacy: () =>
                        Navigator.pushNamed(context, AppRoutes.privacy),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RegisterField extends StatelessWidget {
  const _RegisterField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.keyboardType,
    this.obscureText = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
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

class _RegisterCodeButton extends StatelessWidget {
  const _RegisterCodeButton({required this.busy, required this.onPressed});

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

class _RegisterAgreement extends StatelessWidget {
  const _RegisterAgreement({
    required this.accepted,
    required this.onChanged,
    required this.onAgreement,
    required this.onPrivacy,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onAgreement;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox.square(
          dimension: 28,
          child: Checkbox(
            value: accepted,
            shape: const CircleBorder(),
            side: const BorderSide(color: AppColors.textSecondary),
            onChanged: (value) => onChanged(value ?? false),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                '我已阅读并同意 ',
                style: AppTypography.smallBody.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              InkWell(
                onTap: onAgreement,
                child: Text(
                  '《用户协议》',
                  style: AppTypography.smallBody.copyWith(
                    color: AppColors.brandPrimary,
                  ),
                ),
              ),
              Text(
                ' 和 ',
                style: AppTypography.smallBody.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              InkWell(
                onTap: onPrivacy,
                child: Text(
                  '《隐私政策》',
                  style: AppTypography.smallBody.copyWith(
                    color: AppColors.brandPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
