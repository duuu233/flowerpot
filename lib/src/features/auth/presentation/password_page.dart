import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';

class PasswordArguments {
  const PasswordArguments({
    this.account = '',
    this.region = LoginRegion.domestic,
  });

  final String account;
  final LoginRegion region;
}

class PasswordPage extends StatefulWidget {
  const PasswordPage({required this.arguments, super.key});

  final PasswordArguments arguments;

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  late final TextEditingController account;
  final code = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  late LoginRegion region;

  @override
  void initState() {
    super.initState();
    account = TextEditingController(text: widget.arguments.account);
    region = widget.arguments.region;
  }

  @override
  void dispose() {
    account.dispose();
    code.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (password.text != confirmation.text) {
      showAppMessage(context, '两次输入的密码不一致', success: false);
      return;
    }
    final state = FlowerpotScope.of(context);
    final result = await state.resetPassword(
      account: account.text,
      newPassword: password.text,
      code: code.text,
      region: region,
    );
    if (!mounted) return;
    showAppMessage(context, result.message, success: result.success);
    if (result.success) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.auth, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final lockedAccount = widget.arguments.account.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('重置密码')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
            children: <Widget>[
              const PlantIllustration(size: 106),
              const SizedBox(height: 16),
              Text('设置新密码', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text(
                '验证码类型固定为密码重置（type 3），手机号与邮箱会分别调用涂鸦对应接口。',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 24),
              if (!lockedAccount) ...<Widget>[
                SegmentedButton<LoginRegion>(
                  segments: const <ButtonSegment<LoginRegion>>[
                    ButtonSegment(
                      value: LoginRegion.domestic,
                      label: Text('手机号'),
                    ),
                    ButtonSegment(
                      value: LoginRegion.overseas,
                      label: Text('邮箱'),
                    ),
                  ],
                  selected: <LoginRegion>{region},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => setState(() {
                    region = value.first;
                    account.clear();
                  }),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: account,
                readOnly: lockedAccount,
                keyboardType: region == LoginRegion.domestic
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: region == LoginRegion.domestic ? '手机号' : '邮箱',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '验证码',
                  prefixIcon: const Icon(Icons.shield_outlined),
                  suffixIcon: TextButton(
                    onPressed: state.busy
                        ? null
                        : () async {
                            final result = await state.sendCode(
                              account: account.text,
                              region: region,
                              type: 3,
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
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新密码（至少 6 位）',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmation,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '再次输入新密码',
                  prefixIcon: Icon(Icons.lock_reset_rounded),
                ),
              ),
              const SizedBox(height: 24),
              LoadingButton(
                label: '更新密码',
                loading: state.busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
