import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../core/config/debug_tools_config.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../../preview/preview_config.dart';
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
    codeLogin = widget.initialCodeLogin;
    codeCountdown.addListener(_refreshCountdown);
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

  Future<void> _login() async {
    if (!accepted) {
      showAppMessage(context, '请先阅读并同意用户协议与隐私政策', tone: AppMessageTone.error);
      return;
    }
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
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
    if (result.success) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.shell, (_) => false);
    }
  }

  Future<void> _sendCode() async {
    if (codeCountdown.active) return;
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

  Future<void> _enterDemo() async {
    final result = await FlowerpotScope.of(
      context,
    ).enterDemo(seedDevice: !StaticPreviewConfig.enabled);
    if (!mounted) return;
    if (result.success) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.shell, (_) => false);
    } else {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
    }
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
                maxWidth: 375,
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
                        padding: const EdgeInsets.symmetric(horizontal: 20),
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
                          onRegister: () =>
                              Navigator.pushNamed(context, AppRoutes.register),
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
                          onDemo: state.busy ? null : _enterDemo,
                          onSdkDebug: DebugToolsConfig.enabled
                              ? () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.tuyaDebug,
                                )
                              : null,
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
    required this.onRegister,
    required this.onAgreement,
    required this.onPrivacy,
    required this.onForgotPassword,
    required this.onWechat,
    required this.onAlipay,
    required this.onDemo,
    required this.onSdkDebug,
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
  final VoidCallback onRegister;
  final VoidCallback onAgreement;
  final VoidCallback onPrivacy;
  final VoidCallback onForgotPassword;
  final VoidCallback onWechat;
  final VoidCallback onAlipay;
  final VoidCallback? onDemo;

  /// Null in release builds that did not opt into the SDK console, which also
  /// hides the entry.
  final VoidCallback? onSdkDebug;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const Key('login-panel'),
      painter: _LoginPanelBackgroundPainter(codeLogin: codeLogin),
      child: Column(
        children: <Widget>[
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      '没有账户？',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    InkWell(
                      onTap: onRegister,
                      child: Text(
                        '去注册',
                        style: AppTypography.body.copyWith(
                          color: AppColors.brandPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                const _OtherLoginDivider(),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _SocialButton(
                      label: '微信登录',
                      assetPath: AppAssets.wechatLoginIcon,
                      onTap: onWechat,
                    ),
                    const SizedBox(width: 32),
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
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: onDemo,
                      icon: const Icon(Icons.eco_outlined, size: 18),
                      label: const Text('体验模式'),
                    ),
                    // This button swaps the live bridge for the mock backend at
                    // runtime, which is otherwise invisible inside a
                    // TUYA_ENABLED build.
                    const MockDataBadge(label: '切到假数据'),
                    if (onSdkDebug != null)
                      TextButton.icon(
                        key: const Key('tuya-debug-entry'),
                        onPressed: onSdkDebug,
                        icon: const Icon(Icons.bug_report_outlined, size: 18),
                        label: const Text('涂鸦 SDK 联调'),
                      ),
                  ],
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
          Expanded(
            child: _LoginTab(
              label: '密码登录',
              selected: !codeLogin,
              onTap: () => onChanged(false),
            ),
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
  const _LoginPanelBackgroundPainter({required this.codeLogin});

  static const double _cornerRadius = AppRadius.md;
  static const double _tabHeight = 44;

  final bool codeLogin;

  @override
  void paint(Canvas canvas, Size size) {
    final panelBounds = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_cornerRadius),
    );
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
      oldDelegate.codeLogin != codeLogin;
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
  });

  final TextEditingController controller;
  final String hintText;
  final String iconAsset;
  final double iconSize;
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
          prefixIcon: AuthAssetIcon(assetPath: iconAsset, size: iconSize),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 56,
            minHeight: 48,
          ),
          suffixIcon: suffix,
          filled: true,
          fillColor: const Color(0xFFF7F7F7),
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
