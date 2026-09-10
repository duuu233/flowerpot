import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../domain/auth_validator.dart';
import 'verification_code_countdown.dart';
import 'widgets/auth_asset_icon.dart';
import 'widgets/auth_field_error.dart';

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
  final accountFocus = FocusNode();
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmationController = TextEditingController();
  final codeCountdown = VerificationCodeCountdown();
  bool passwordVisible = false;
  bool confirmationVisible = false;

  LoginRegion get region => widget.arguments.region;

  /// 账号那一栏是否已经「交互过」（失焦一次或点过按钮）；见登录页同名字段的说明。
  bool accountTouched = false;

  String get _invalidAccountMessage =>
      region == LoginRegion.domestic ? '请输入正确的 11 位手机号' : '请输入正确的邮箱';

  @override
  void initState() {
    super.initState();
    accountController = TextEditingController(text: widget.arguments.account);
    codeCountdown.addListener(_refreshCountdown);
    // 账号变化要重画：号码/邮箱改对了，下面那行校验提示要跟着消失。
    accountController.addListener(_refreshCountdown);
    accountFocus.addListener(_handleAccountFocusChange);
  }

  void _handleAccountFocusChange() {
    if (accountFocus.hasFocus) return;
    if (accountController.text.trim().isEmpty) return;
    if (!mounted || accountTouched) return;
    setState(() => accountTouched = true);
  }

  /// 输入框下面那行提示；null 表示不画。
  String? get _accountError {
    if (!accountTouched) return null;
    final account = accountController.text.trim();
    if (account.isEmpty) return null;
    if (AuthValidator.isValidAccount(account, region)) return null;
    return _invalidAccountMessage;
  }

  /// 账号不合法时同时给 toast 和输入框下面那行常驻提示。
  bool _rejectInvalidAccount() {
    if (AuthValidator.isValidAccount(accountController.text, region)) {
      return false;
    }
    setState(() => accountTouched = true);
    showAppMessage(context, _invalidAccountMessage, tone: AppMessageTone.error);
    return true;
  }

  @override
  void dispose() {
    accountController.dispose();
    accountFocus.dispose();
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
    // 2026-09-10 起按钮不再按账号格式置灰：灰按钮点不动也不说话，用户只会以为页面坏了。
    if (_rejectInvalidAccount()) return;
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
    if (_rejectInvalidAccount()) return;
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
      // 键盘避让：`resizeToAvoidBottomInset: false` 让页面保持整屏高度不被压缩
      // （压缩会让整页跳一下），改由滚动区自己在底部让出键盘那么高的一段——焦点
      // 落到输入框时 Flutter 会把光标滚进可视区，于是输入框正好停在键盘上方。
      // 这是表单页的通行做法；只靠默认的 resize 在「内容本来就放得下一屏」时不会
      // 产生可滚动区间，输入框照样被键盘盖住。
      resizeToAvoidBottomInset: false,
      appBar: AppPageHeader(
        title: widget.arguments.title,
        leading: const AppBackButton(),
      ),
      background: AppPageBackground.account,
      body: SingleChildScrollView(
        // 键盘避让，见登录页同处注释。
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(28, AppSpacing.xxxl, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PasswordField(
                controller: accountController,
                focusNode: accountFocus,
                errorText: _accountError,
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
                  // 只在「正忙」和「倒计时中」置灰；账号格式不对不再置灰，
                  // 点得动才给得出提示，见 `_rejectInvalidAccount`。
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
    this.focusNode,
    this.errorText,
  });

  final TextEditingController controller;
  final String hintText;
  final Widget prefixIcon;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool readOnly;
  final Widget? suffix;
  final FocusNode? focusNode;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    // 校验提示画在胶囊外面，不用 `InputDecoration.errorText`：那会把提示塞进 56 的
    // 固定高度里，胶囊本身被压扁。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildField(),
        AuthFieldError(message: errorText),
      ],
    );
  }

  Widget _buildField() {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
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
