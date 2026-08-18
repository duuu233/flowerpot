import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import 'verification_code_countdown.dart';
import 'widgets/auth_asset_icon.dart';

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
  final codeCountdown = VerificationCodeCountdown();
  bool passwordVisible = false;
  bool confirmationVisible = false;

  LoginRegion get region => widget.arguments.region;

  @override
  void initState() {
    super.initState();
    accountController = TextEditingController(text: widget.arguments.account);
    codeCountdown.addListener(_refreshCountdown);
  }

  @override
  void dispose() {
    accountController.dispose();
    codeController.dispose();
    passwordController.dispose();
    confirmationController.dispose();
    codeCountdown.dispose();
    super.dispose();
  }

  void _refreshCountdown() {
    if (mounted) setState(() {});
  }

  Future<void> _sendCode() async {
    if (codeCountdown.active) return;
    final result = await FlowerpotScope.of(
      context,
    ).sendCode(account: accountController.text, region: region, type: 3);
    if (!mounted) return;
    if (result.success) codeCountdown.start();
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
      background: AppPageBackground.account,
      body: SingleChildScrollView(
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(28, AppSpacing.xxxl, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PasswordField(
                controller: accountController,
                hintText: domestic ? '请输入手机号' : '请输入邮箱',
                prefixIcon: domestic
                    ? const AuthAssetIcon(assetPath: AppAssets.phoneIcon)
                    : const Icon(
                        Icons.mail_outline_rounded,
                        color: AppColors.brandPrimary,
                        size: 22,
                      ),
                keyboardType: domestic
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                readOnly: widget.arguments.account.isNotEmpty,
              ),
              const SizedBox(height: AppSpacing.lg),
              _PasswordField(
                controller: codeController,
                hintText: '请输入验证码',
                prefixIcon: const AuthAssetIcon(
                  assetPath: AppAssets.verificationCodeIcon,
                ),
                keyboardType: TextInputType.number,
                suffix: _CodeButton(
                  busy: state.busy || codeCountdown.active,
                  label: codeCountdown.label,
                  onPressed: _sendCode,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _PasswordField(
                controller: passwordController,
                hintText: '请输入密码',
                prefixIcon: const AuthAssetIcon(
                  assetPath: AppAssets.passwordIcon,
                  size: 20,
                ),
                keyboardType: TextInputType.visiblePassword,
                obscureText: !passwordVisible,
                suffix: IconButton(
                  key: const Key('reset-password-visibility'),
                  tooltip: passwordVisible ? '隐藏密码' : '显示密码',
                  onPressed: () =>
                      setState(() => passwordVisible = !passwordVisible),
                  icon: passwordVisible
                      ? const Icon(
                          Icons.visibility_outlined,
                          color: AppColors.textTertiary,
                        )
                      : Image.asset(
                          AppAssets.passwordVisibilityOffIcon,
                          width: 22,
                          height: 22,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _PasswordField(
                controller: confirmationController,
                hintText: '请确认密码',
                prefixIcon: const AuthAssetIcon(
                  assetPath: AppAssets.confirmPasswordIcon,
                ),
                keyboardType: TextInputType.visiblePassword,
                obscureText: !confirmationVisible,
                suffix: IconButton(
                  key: const Key('reset-confirmation-visibility'),
                  tooltip: confirmationVisible ? '隐藏密码' : '显示密码',
                  onPressed: () => setState(
                    () => confirmationVisible = !confirmationVisible,
                  ),
                  icon: confirmationVisible
                      ? const Icon(
                          Icons.visibility_outlined,
                          color: AppColors.textTertiary,
                        )
                      : Image.asset(
                          AppAssets.passwordVisibilityOffIcon,
                          width: 22,
                          height: 22,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
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
    required this.prefixIcon,
    required this.keyboardType,
    this.obscureText = false,
    this.readOnly = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final Widget prefixIcon;
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
          prefixIcon: prefixIcon,
          prefixIconConstraints: const BoxConstraints(
            minWidth: 56,
            minHeight: 48,
          ),
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
  const _CodeButton({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool busy;
  final String label;
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
          child: Text(
            label,
            style: const TextStyle(color: AppColors.brandPrimary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}
