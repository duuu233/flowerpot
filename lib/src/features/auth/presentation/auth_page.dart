import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';
import 'password_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final accountController = TextEditingController();
  final credentialController = TextEditingController();
  LoginRegion region = LoginRegion.domestic;
  bool codeLogin = true;
  bool accepted = true;

  @override
  void dispose() {
    accountController.dispose();
    credentialController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!accepted) {
      showAppMessage(context, '请先阅读并同意用户协议与隐私政策', success: false);
      return;
    }
    final state = FlowerpotScope.of(context);
    final result = await state.login(
      account: accountController.text,
      credential: credentialController.text,
      region: region,
      verificationCode: codeLogin,
    );
    if (!mounted) return;
    showAppMessage(context, result.message, success: result.success);
    if (result.success) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.shell, (_) => false);
    }
  }

  Future<void> _enterDemo() async {
    final result = await FlowerpotScope.of(context).enterDemo();
    if (!mounted) return;
    if (result.success) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.shell, (_) => false);
    } else {
      showAppMessage(context, result.message, success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Center(child: PlantIllustration(size: 126)),
                    const SizedBox(height: 8),
                    Text(
                      '照顾植物，\n也照顾生活。',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '连接你的智能花盆，随时了解每一片叶子的需要。',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 28),
                    SegmentedButton<LoginRegion>(
                      segments: const <ButtonSegment<LoginRegion>>[
                        ButtonSegment(
                          value: LoginRegion.domestic,
                          label: Text('中国大陆'),
                        ),
                        ButtonSegment(
                          value: LoginRegion.overseas,
                          label: Text('海外地区'),
                        ),
                      ],
                      selected: <LoginRegion>{region},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) => setState(() {
                        region = value.first;
                        codeLogin = region == LoginRegion.domestic;
                        accountController.clear();
                        credentialController.clear();
                      }),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: accountController,
                      keyboardType: region == LoginRegion.domestic
                          ? TextInputType.phone
                          : TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: region == LoginRegion.domestic
                            ? '手机号'
                            : '邮箱',
                        prefixIcon: Icon(
                          region == LoginRegion.domestic
                              ? Icons.phone_iphone_rounded
                              : Icons.alternate_email_rounded,
                        ),
                        prefixText: region == LoginRegion.domestic
                            ? '+86  '
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: credentialController,
                      obscureText: !codeLogin,
                      decoration: InputDecoration(
                        labelText: codeLogin ? '验证码' : '密码',
                        prefixIcon: Icon(
                          codeLogin
                              ? Icons.shield_outlined
                              : Icons.lock_outline_rounded,
                        ),
                        suffixIcon: codeLogin
                            ? TextButton(
                                onPressed: state.busy
                                    ? null
                                    : () async {
                                        final result = await state.sendCode(
                                          account: accountController.text,
                                          region: region,
                                          type: 2,
                                        );
                                        if (context.mounted) {
                                          showAppMessage(
                                            context,
                                            result.message,
                                            success: result.success,
                                          );
                                        }
                                      },
                                child: const Text('获取验证码'),
                              )
                            : null,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        children: <Widget>[
                          if (region == LoginRegion.domestic)
                            TextButton(
                              onPressed: () =>
                                  setState(() => codeLogin = !codeLogin),
                              child: Text(codeLogin ? '使用密码登录' : '使用验证码登录'),
                            ),
                          TextButton(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              AppRoutes.password,
                              arguments: PasswordArguments(
                                account: accountController.text.trim(),
                                region: region,
                              ),
                            ),
                            child: const Text('忘记密码'),
                          ),
                        ],
                      ),
                    ),
                    LoadingButton(
                      label: '登录',
                      loading: state.busy,
                      onPressed: _login,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              AppRoutes.register,
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            child: const Text('创建账号'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: state.busy ? null : _enterDemo,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            icon: const Icon(Icons.eco_outlined, size: 18),
                            label: const Text('体验模式'),
                          ),
                        ),
                      ],
                    ),
                    if (region == LoginRegion.domestic) ...<Widget>[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Row(
                          children: <Widget>[
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                '快捷登录',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _SocialButton(
                            icon: Icons.phone_android_rounded,
                            color: AppColors.ink,
                            onTap: () =>
                                showAppMessage(context, '运营商一键登录参数待配置'),
                          ),
                          const SizedBox(width: 18),
                          _SocialButton(
                            icon: Icons.wechat_rounded,
                            color: const Color(0xFF1AAD19),
                            onTap: () => showAppMessage(context, '微信开放平台参数待配置'),
                          ),
                          const SizedBox(width: 18),
                          _SocialButton(
                            icon: Icons.account_balance_wallet_outlined,
                            color: const Color(0xFF1677FF),
                            onTap: () =>
                                showAppMessage(context, '支付宝开放平台参数待配置'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Checkbox(
                          value: accepted,
                          visualDensity: VisualDensity.compact,
                          onChanged: (value) =>
                              setState(() => accepted = value ?? false),
                        ),
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: 9),
                            child: Text(
                              '我已阅读并同意《用户协议》和《隐私政策》',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .8),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color),
    ),
  );
}
