import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import 'password_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.initialCodeLogin = true});

  final bool initialCodeLogin;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final accountController = TextEditingController();
  final credentialController = TextEditingController();
  late bool codeLogin;
  bool passwordVisible = false;
  bool accepted = false;

  @override
  void initState() {
    super.initState();
    codeLogin = widget.initialCodeLogin;
  }

  @override
  void dispose() {
    accountController.dispose();
    credentialController.dispose();
    super.dispose();
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
    final result = await FlowerpotScope.of(context).sendCode(
      account: accountController.text,
      region: LoginRegion.domestic,
      type: 2,
    );
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
  }

  Future<void> _enterDemo() async {
    final result = await FlowerpotScope.of(context).enterDemo();
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
      background: AppPageBackground.standard,
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
                      _LoginPanel(
                        accountController: accountController,
                        credentialController: credentialController,
                        codeLogin: codeLogin,
                        accepted: accepted,
                        passwordVisible: passwordVisible,
                        busy: state.busy,
                        onModeChanged: (value) => setState(() {
                          codeLogin = value;
                          passwordVisible = false;
                          credentialController.clear();
                        }),
                        onPasswordVisibilityChanged: () =>
                            setState(() => passwordVisible = !passwordVisible),
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
  });

  final TextEditingController accountController;
  final TextEditingController credentialController;
  final bool codeLogin;
  final bool accepted;
  final bool passwordVisible;
  final bool busy;
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

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
      ),
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
                  icon: Icons.phone_iphone_rounded,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 22),
                _LoginField(
                  controller: credentialController,
                  hintText: codeLogin ? '请输入验证码' : '请输入密码',
                  icon: Icons.verified_user_outlined,
                  keyboardType: codeLogin
                      ? TextInputType.number
                      : TextInputType.visiblePassword,
                  obscureText: !codeLogin && !passwordVisible,
                  suffix: codeLogin
                      ? _SendCodeButton(busy: busy, onPressed: onSendCode)
                      : IconButton(
                          key: const Key('password-visibility-toggle'),
                          tooltip: passwordVisible ? '隐藏密码' : '显示密码',
                          onPressed: onPasswordVisibilityChanged,
                          icon: Icon(
                            passwordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppColors.textTertiary,
                          ),
                        ),
                ),
                if (!codeLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 30,
                      child: TextButton(
                        onPressed: onForgotPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('忘记密码?'),
                      ),
                    ),
                  ),
                SizedBox(height: codeLogin ? 30 : 8),
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
                      color: const Color(0xFF10C800),
                      onTap: onWechat,
                      child: const Icon(
                        Icons.wechat_rounded,
                        color: AppColors.surface,
                        size: 31,
                      ),
                    ),
                    const SizedBox(width: 32),
                    _SocialButton(
                      label: '支付宝登录',
                      color: const Color(0xFF1677FF),
                      onTap: onAlipay,
                      child: const Text(
                        '支',
                        style: TextStyle(
                          color: AppColors.surface,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
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
                TextButton.icon(
                  onPressed: onDemo,
                  icon: const Icon(Icons.eco_outlined, size: 18),
                  label: const Text('体验模式'),
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
      color: selected ? AppColors.surface : AppColors.brandSurface,
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

class _LoginField extends StatelessWidget {
  const _LoginField({
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
  const _SendCodeButton({required this.busy, required this.onPressed});

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
    required this.color,
    required this.onTap,
    required this.child,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: SizedBox.square(dimension: 48, child: Center(child: child)),
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
      child: const SizedBox.square(
        dimension: 76,
        child: CustomPaint(painter: _BrandLogoPainter()),
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Text(
          'YSplanter',
          style: AppTypography.deviceTitle.copyWith(
            color: AppColors.textStrong,
            fontSize: 38,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
        const Positioned(
          right: 35,
          top: -2,
          child: Icon(
            Icons.eco_rounded,
            color: AppColors.brandPrimary,
            size: 18,
          ),
        ),
      ],
    );
  }
}

class _BrandLogoPainter extends CustomPainter {
  const _BrandLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * .2)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFB9E2D7), AppColors.brandPrimary],
        ).createShader(rect),
    );
    final white = Paint()
      ..color = AppColors.surface
      ..strokeWidth = size.width * .075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final stem = Path()
      ..moveTo(size.width * .50, size.height * .66)
      ..lineTo(size.width * .50, size.height * .49)
      ..quadraticBezierTo(
        size.width * .42,
        size.height * .31,
        size.width * .28,
        size.height * .25,
      )
      ..moveTo(size.width * .50, size.height * .49)
      ..quadraticBezierTo(
        size.width * .61,
        size.height * .27,
        size.width * .79,
        size.height * .19,
      );
    canvas.drawPath(stem, white);
    final leftLeaf = Path()
      ..moveTo(size.width * .28, size.height * .25)
      ..quadraticBezierTo(
        size.width * .38,
        size.height * .20,
        size.width * .45,
        size.height * .38,
      )
      ..quadraticBezierTo(
        size.width * .30,
        size.height * .36,
        size.width * .28,
        size.height * .25,
      )
      ..close();
    final rightLeaf = Path()
      ..moveTo(size.width * .79, size.height * .19)
      ..quadraticBezierTo(
        size.width * .75,
        size.height * .38,
        size.width * .55,
        size.height * .41,
      )
      ..quadraticBezierTo(
        size.width * .62,
        size.height * .22,
        size.width * .79,
        size.height * .19,
      )
      ..close();
    canvas.drawPath(leftLeaf, Paint()..color = AppColors.surface);
    canvas.drawPath(rightLeaf, Paint()..color = AppColors.surface);
    final pot = Path()
      ..moveTo(size.width * .33, size.height * .70)
      ..lineTo(size.width * .67, size.height * .70)
      ..lineTo(size.width * .62, size.height * .88)
      ..lineTo(size.width * .38, size.height * .88)
      ..close();
    canvas.drawPath(pot, Paint()..color = AppColors.surface);
    canvas.drawLine(
      Offset(size.width * .30, size.height * .69),
      Offset(size.width * .70, size.height * .69),
      white,
    );
  }

  @override
  bool shouldRepaint(_BrandLogoPainter oldDelegate) => false;
}
