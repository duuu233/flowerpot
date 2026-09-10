import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../domain/auth_validator.dart';
import 'verification_code_countdown.dart';
import 'widgets/auth_asset_icon.dart';
import 'widgets/auth_field_error.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final accountController = TextEditingController();
  final accountFocus = FocusNode();
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmationController = TextEditingController();
  final codeCountdown = VerificationCodeCountdown();
  bool passwordVisible = false;
  bool confirmationVisible = false;
  bool accepted = false;

  /// 手机号那一栏是否已经「交互过」（失焦一次或点过按钮）；见登录页同名字段的说明。
  bool accountTouched = false;

  static const _invalidAccountMessage = '请输入正确的 11 位手机号';

  @override
  void initState() {
    super.initState();
    codeCountdown.addListener(_refreshCountdown);
    // 手机号变化要重画：号码改对了，下面那行校验提示要跟着消失。
    accountController.addListener(_refreshCountdown);
    accountFocus.addListener(_handleAccountFocusChange);
  }

  void _refreshCountdown() {
    if (mounted) setState(() {});
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
    if (AuthValidator.isValidAccount(account, LoginRegion.domestic)) {
      return null;
    }
    return _invalidAccountMessage;
  }

  /// 号码不合法时同时给 toast 和输入框下面那行常驻提示。
  bool _rejectInvalidAccount() {
    if (AuthValidator.isValidAccount(
      accountController.text,
      LoginRegion.domestic,
    )) {
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

  Future<void> _sendCode() async {
    if (codeCountdown.active) return;
    // 2026-09-10 起按钮不再按号码格式置灰：灰按钮点不动也不说话，用户只会以为页面坏了。
    if (_rejectInvalidAccount()) return;
    final result = await FlowerpotScope.of(context).sendCode(
      account: accountController.text,
      region: LoginRegion.domestic,
      type: 1,
    );
    if (!mounted) return;
    if (result.success) codeCountdown.start();
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
    if (_rejectInvalidAccount()) return;
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
      // 键盘避让：`resizeToAvoidBottomInset: false` 让页面保持整屏高度不被压缩
      // （压缩会让整页跳一下），改由滚动区自己在底部让出键盘那么高的一段——焦点
      // 落到输入框时 Flutter 会把光标滚进可视区，于是输入框正好停在键盘上方。
      // 这是表单页的通行做法；只靠默认的 resize 在「内容本来就放得下一屏」时不会
      // 产生可滚动区间，输入框照样被键盘盖住。
      resizeToAvoidBottomInset: false,
      appBar: const AppPageHeader(title: '注册账号', leading: AppBackButton()),
      background: AppPageBackground.account,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            // 键盘避让，见登录页同处注释。
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(28, AppSpacing.xxxl, 28, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _RegisterField(
                    controller: accountController,
                    focusNode: accountFocus,
                    errorText: _accountError,
                    hintText: '请输入手机号',
                    iconAsset: AppAssets.phoneIcon,
                    keyboardType: TextInputType.phone,
                    // 只收 11 位数字：`TextInputType.phone` 的键盘上还有 + - ( )，
                    // 不挡住就能输进一个必然被拒的号码。
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _RegisterField(
                    controller: codeController,
                    hintText: '请输入验证码',
                    iconAsset: AppAssets.verificationCodeIcon,
                    keyboardType: TextInputType.number,
                    suffix: _RegisterCodeButton(
                      // 只在「正忙」和「倒计时中」置灰；号码格式不对不再置灰，
                      // 点得动才给得出提示，见 `_rejectInvalidAccount`。
                      busy: state.busy || codeCountdown.active,
                      label: codeCountdown.label,
                      onPressed: _sendCode,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _RegisterField(
                    controller: passwordController,
                    hintText: '请输入密码',
                    iconAsset: AppAssets.passwordIcon,
                    iconSize: 20,
                    keyboardType: TextInputType.visiblePassword,
                    obscureText: !passwordVisible,
                    suffix: IconButton(
                      key: const Key('register-password-visibility'),
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
                  _RegisterField(
                    controller: confirmationController,
                    hintText: '请确认密码',
                    iconAsset: AppAssets.confirmPasswordIcon,
                    keyboardType: TextInputType.visiblePassword,
                    obscureText: !confirmationVisible,
                    suffix: IconButton(
                      key: const Key('register-confirmation-visibility'),
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
    required this.iconAsset,
    required this.keyboardType,
    this.iconSize = 24,
    this.obscureText = false,
    this.suffix,
    this.inputFormatters,
    this.focusNode,
    this.errorText,
  });

  final TextEditingController controller;
  final String hintText;
  final String iconAsset;
  final double iconSize;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
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
        inputFormatters: inputFormatters,
        obscureText: obscureText,
        style: AppTypography.body,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
            fontSize: 15,
          ),
          prefixIcon: AuthAssetIcon(assetPath: iconAsset, size: iconSize),
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

class _RegisterCodeButton extends StatelessWidget {
  const _RegisterCodeButton({
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
