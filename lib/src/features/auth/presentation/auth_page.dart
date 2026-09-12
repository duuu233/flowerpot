import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../domain/auth_validator.dart';
import '../login_entry_config.dart';
import 'password_page.dart';
import 'verification_code_countdown.dart';
import 'widgets/auth_asset_icon.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.initialCodeLogin = true});

  final bool initialCodeLogin;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final accountController = TextEditingController();
  final credentialController = TextEditingController();
  final codeCountdown = VerificationCodeCountdown();
  late bool codeLogin;
  bool passwordVisible = false;
  bool accepted = false;

  @override
  void initState() {
    super.initState();
    codeLogin = LoginEntryConfig.passwordLogin ? widget.initialCodeLogin : true;
    codeCountdown.addListener(_refreshCountdown);
    // 手机号变化要重画：号码是否合法会影响这一页的其它状态。
    accountController.addListener(_refreshCountdown);
  }

  @override
  void dispose() {
    accountController.dispose();
    credentialController.dispose();
    codeCountdown.dispose();
    super.dispose();
  }

  void _refreshCountdown() {
    if (mounted) setState(() {});
  }

  static const _invalidAccountMessage = '请输入正确的 11 位手机号';

  /// 号码不合法时弹一条 toast 并让调用方当场 return。
  ///
  /// 2026-09-10 产品口径：**登录页只要 toast，输入框下面那行常驻提示去掉**——
  /// 这一页只有手机号一栏要校验，toast 已经说清楚了，再挂一行红字是重复。
  /// （注册页与找回密码页仍保留那行提示，它们的表单更长。）
  bool _rejectInvalidAccount() {
    if (AuthValidator.isValidAccount(
      accountController.text,
      LoginRegion.domestic,
    )) {
      return false;
    }
    showAppMessage(context, _invalidAccountMessage, tone: AppMessageTone.error);
    return true;
  }

  Future<void> _login() async {
    if (!accepted) {
      showAppMessage(context, '请先阅读并同意用户协议与隐私政策', tone: AppMessageTone.error);
      return;
    }
    if (accountController.text.trim().isEmpty ||
        credentialController.text.trim().isEmpty) {
      showAppMessage(
        context,
        codeLogin ? '请输入手机号和验证码' : '请输入手机号和密码',
        tone: AppMessageTone.error,
      );
      return;
    }
    // 号码格式不对就别送到后端去换一句一样的红字了，当场说清楚。
    if (_rejectInvalidAccount()) return;
    final state = FlowerpotScope.of(context);
    final result = await state.login(
      account: accountController.text,
      credential: credentialController.text,
      region: LoginRegion.domestic,
      verificationCode: codeLogin,
    );
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success
          ? AppMessageTone.success
          : AppMessageTone.error,
    );
    if (result.success) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.shell, (_) => false);
    }
  }

  Future<void> _sendCode() async {
    if (codeCountdown.active) return;
    // 2026-09-10 起按钮不再按号码格式置灰：灰按钮点不动、也不说话，用户只会以为页面坏了。
    // 现在照常可点，号码不合法就在这里挡下来——短信仍然不会发出去，但用户拿得到一句话。
    if (_rejectInvalidAccount()) return;
    final result = await FlowerpotScope.of(context).sendCode(
      account: accountController.text,
      region: LoginRegion.domestic,
      type: 2,
    );
    if (!mounted) return;
    if (result.success) codeCountdown.start();
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    return AppPageScaffold(
      useSafeArea: false,
      background: AppPageBackground.account,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ResponsiveContent(
                padding: EdgeInsets.zero,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 82),
                      const Center(child: _BrandLogo()),
                      const SizedBox(height: 18),
                      const Center(child: _BrandTitle()),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '登录账号，连接和管理你的智能设备',
                        textAlign: TextAlign.center,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.pageMargin,
                        ),
                        child: _LoginPanel(
                          accountController: accountController,
                          credentialController: credentialController,
                          codeLogin: codeLogin,
                          accepted: accepted,
                          passwordVisible: passwordVisible,
                          busy: state.busy,
                          codeCountdown: codeCountdown,
                          onModeChanged: (value) => setState(() {
                            codeLogin = value;
                            passwordVisible = false;
                            credentialController.clear();
                          }),
                          onPasswordVisibilityChanged: () => setState(
                            () => passwordVisible = !passwordVisible,
                          ),
                          onAcceptedChanged: (value) =>
                              setState(() => accepted = value),
                          onSendCode: _sendCode,
                          onLogin: _login,
                          onAgreement: () =>
                              Navigator.pushNamed(context, AppRoutes.agreement),
                          onPrivacy: () =>
                              Navigator.pushNamed(context, AppRoutes.privacy),
                          onForgotPassword: () => Navigator.pushNamed(
                            context,
                            AppRoutes.password,
                            arguments: PasswordArguments(
                              account: accountController.text.trim(),
                              region: LoginRegion.domestic,
                            ),
                          ),
                          onWechat: () => showAppMessage(
                            context,
                            '微信开放平台参数待配置',
                            tone: AppMessageTone.info,
                          ),
                          onAlipay: () => showAppMessage(
                            context,
                            '支付宝开放平台参数待配置',
                            tone: AppMessageTone.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.accountController,
    required this.credentialController,
    required this.codeLogin,
    required this.accepted,
    required this.passwordVisible,
    required this.busy,
    required this.codeCountdown,
    required this.onModeChanged,
    required this.onPasswordVisibilityChanged,
    required this.onAcceptedChanged,
    required this.onSendCode,
    required this.onLogin,
    required this.onAgreement,
    required this.onPrivacy,
    required this.onForgotPassword,
    required this.onWechat,
    required this.onAlipay,
  });

  final TextEditingController accountController;
  final TextEditingController credentialController;
  final bool codeLogin;
  final bool accepted;
  final bool passwordVisible;
  final bool busy;
  final VerificationCodeCountdown codeCountdown;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onPasswordVisibilityChanged;
  final ValueChanged<bool> onAcceptedChanged;
  final VoidCallback onSendCode;
  final VoidCallback onLogin;
  final VoidCallback onAgreement;
  final VoidCallback onPrivacy;
  final VoidCallback onForgotPassword;
  final VoidCallback onWechat;
  final VoidCallback onAlipay;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const Key('login-panel'),
      painter: _LoginPanelBackgroundPainter(
        codeLogin: codeLogin,
        tabbed: LoginEntryConfig.passwordLogin,
      ),
      child: Column(
        children: <Widget>[
          // With password login switched off there is only one mode, so the
          // two-tab strip is skipped entirely rather than showing one label
          // beside an empty half. It stays in place for when the mode returns.
          if (LoginEntryConfig.passwordLogin)
            _LoginTabs(codeLogin: codeLogin, onChanged: onModeChanged),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 32, 8, 0),
            child: Column(
              children: <Widget>[
                _LoginField(
                  controller: accountController,
                  hintText: '请输入手机号',
                  iconAsset: AppAssets.phoneIcon,
                  keyboardType: TextInputType.phone,
                  // 手机号只可能是 11 位数字。`TextInputType.phone` 的键盘上还有
                  // `+ - ( ) *`，不挡住的话用户能输进去一个必然被拒的号码。
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                ),
                const SizedBox(height: 22),
                _LoginField(
                  controller: credentialController,
                  hintText: codeLogin ? '请输入验证码' : '请输入密码',
                  iconAsset: codeLogin
                      ? AppAssets.verificationCodeIcon
                      : AppAssets.passwordIcon,
                  iconSize: codeLogin ? 24 : 20,
                  keyboardType: codeLogin
                      ? TextInputType.number
                      : TextInputType.visiblePassword,
                  obscureText: !codeLogin && !passwordVisible,
                  suffix: codeLogin
                      ? _SendCodeButton(
                          // 只在「正忙」和「倒计时中」置灰。号码格式不对不再置灰：
                          // 点得动才给得出提示，见 `_rejectInvalidAccount`。
                          busy: busy || codeCountdown.active,
                          label: codeCountdown.label,
                          onPressed: onSendCode,
                        )
                      : IconButton(
                          key: const Key('password-visibility-toggle'),
                          tooltip: passwordVisible ? '隐藏密码' : '显示密码',
                          onPressed: onPasswordVisibilityChanged,
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
                if (!codeLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 34,
                      child: TextButton(
                        key: const Key('forgot-password-link'),
                        onPressed: onForgotPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.only(left: 8, right: 12),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: AppTypography.body.copyWith(fontSize: 14),
                        ),
                        child: const Text('忘记密码?'),
                      ),
                    ),
                  ),
                SizedBox(height: codeLogin ? 30 : 6),
                FilledButton(
                  onPressed: busy ? null : onLogin,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: AppColors.brandPrimary,
                    foregroundColor: AppColors.surface,
                    shape: const StadiumBorder(),
                    textStyle: AppTypography.pageTitle.copyWith(
                      color: AppColors.surface,
                    ),
                  ),
                  child: busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.surface,
                          ),
                        )
                      : const Text('登录'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '输入验证码即登录，未注册手机将自动创建账户',
                  textAlign: TextAlign.center,
                  style: AppTypography.smallBody.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 34),
                const _OtherLoginDivider(),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (LoginEntryConfig.wechatLogin)
                      _SocialButton(
                        label: '微信登录',
                        assetPath: AppAssets.wechatLoginIcon,
                        onTap: onWechat,
                      ),
                    if (LoginEntryConfig.wechatLogin &&
                        LoginEntryConfig.alipayLogin)
                      const SizedBox(width: 32),
                    if (LoginEntryConfig.alipayLogin)
                      _SocialButton(
                        label: '支付宝登录',
                        assetPath: AppAssets.alipayLoginIcon,
                        onTap: onAlipay,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _AgreementRow(
                  accepted: accepted,
                  onChanged: onAcceptedChanged,
                  onAgreement: onAgreement,
                  onPrivacy: onPrivacy,
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginTabs extends StatelessWidget {
  const _LoginTabs({required this.codeLogin, required this.onChanged});

  final bool codeLogin;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _LoginTab(
              label: '验证码登录',
              selected: codeLogin,
              onTap: () => onChanged(true),
            ),
          ),
          // The panel keeps its two-column shape so the notch behind the tab
          // still reads correctly with password login hidden.
          Expanded(
            child: LoginEntryConfig.passwordLogin
                ? _LoginTab(
                    label: '密码登录',
                    selected: !codeLogin,
                    onTap: () => onChanged(false),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _LoginTab extends StatelessWidget {
  const _LoginTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              label,
              style: AppTypography.status.copyWith(
                color: selected
                    ? AppColors.brandPrimary
                    : AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AnimatedContainer(
              duration: AppDurations.fast,
              width: selected ? 20 : 0,
              height: 4,
              decoration: const BoxDecoration(
                color: AppColors.brandPrimary,
                borderRadius: AppRadius.full,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginPanelBackgroundPainter extends CustomPainter {
  const _LoginPanelBackgroundPainter({
    required this.codeLogin,
    required this.tabbed,
  });

  static const double _cornerRadius = AppRadius.md;
  static const double _tabHeight = 44;

  final bool codeLogin;

  /// Whether the panel carries the two-tab strip. Without it the notched
  /// surface has nothing to point at, so the panel is a plain card.
  final bool tabbed;

  @override
  void paint(Canvas canvas, Size size) {
    final panelBounds = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_cornerRadius),
    );
    if (!tabbed) {
      canvas.drawRRect(panelBounds, Paint()..color = AppColors.surface);
      return;
    }
    canvas.drawRRect(panelBounds, Paint()..color = const Color(0x66FFFFFF));
    canvas.drawPath(_selectedSurface(size), Paint()..color = AppColors.surface);
    canvas.drawRRect(
      panelBounds,
      Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  Path _selectedSurface(Size size) {
    final width = size.width;
    final height = size.height;
    final slopeStart = width / 2 - 15;
    final slopeEnd = width / 2 + 11;

    if (codeLogin) {
      return Path()
        ..moveTo(_cornerRadius, 0)
        ..lineTo(slopeStart, 0)
        ..cubicTo(
          slopeStart + 10,
          0,
          slopeEnd - 7,
          _tabHeight,
          slopeEnd,
          _tabHeight,
        )
        ..lineTo(width - _cornerRadius, _tabHeight)
        ..quadraticBezierTo(
          width,
          _tabHeight,
          width,
          _tabHeight + _cornerRadius,
        )
        ..lineTo(width, height - _cornerRadius)
        ..quadraticBezierTo(width, height, width - _cornerRadius, height)
        ..lineTo(_cornerRadius, height)
        ..quadraticBezierTo(0, height, 0, height - _cornerRadius)
        ..lineTo(0, _cornerRadius)
        ..quadraticBezierTo(0, 0, _cornerRadius, 0)
        ..close();
    }

    return Path()
      ..moveTo(width - _cornerRadius, 0)
      ..lineTo(width - slopeStart, 0)
      ..cubicTo(
        width - slopeStart - 10,
        0,
        width - slopeEnd + 7,
        _tabHeight,
        width - slopeEnd,
        _tabHeight,
      )
      ..lineTo(_cornerRadius, _tabHeight)
      ..quadraticBezierTo(0, _tabHeight, 0, _tabHeight + _cornerRadius)
      ..lineTo(0, height - _cornerRadius)
      ..quadraticBezierTo(0, height, _cornerRadius, height)
      ..lineTo(width - _cornerRadius, height)
      ..quadraticBezierTo(width, height, width, height - _cornerRadius)
      ..lineTo(width, _cornerRadius)
      ..quadraticBezierTo(width, 0, width - _cornerRadius, 0)
      ..close();
  }

  @override
  bool shouldRepaint(_LoginPanelBackgroundPainter oldDelegate) =>
      oldDelegate.codeLogin != codeLogin || oldDelegate.tabbed != tabbed;
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.hintText,
    required this.iconAsset,
    required this.keyboardType,
    this.iconSize = 24,
    this.obscureText = false,
    this.suffix,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hintText;
  final String iconAsset;
  final double iconSize;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
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
          prefixIcon: AuthAssetIcon(
            assetPath: iconAsset,
            size: iconSize,
            // Nudged right so the glyph sits centred over the field's rounded
            // left edge rather than hugging it.
            offsetX: 2,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 56,
            minHeight: 48,
          ),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.fieldFill,
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

class _SendCodeButton extends StatelessWidget {
  const _SendCodeButton({
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

class _OtherLoginDivider extends StatelessWidget {
  const _OtherLoginDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Spacer(),
        const SizedBox(width: 60, child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            '其他登录方式',
            style: AppTypography.compactBody.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 60, child: Divider()),
        const Spacer(),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.assetPath,
    required this.onTap,
  });

  final String label;
  final String assetPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Image.asset(
          assetPath,
          key: ValueKey<String>('auth-social-icon:$assetPath'),
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class _AgreementRow extends StatelessWidget {
  const _AgreementRow({
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

class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'YSplanter 品牌图标',
      child: Image.asset(
        AppAssets.appLogo,
        key: const Key('auth-app-logo'),
        width: 76,
        height: 76,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'YSplanter',
      child: Image.asset(
        AppAssets.ysplanterWordmark,
        key: const Key('auth-wordmark'),
        width: 210,
        height: 47,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}
