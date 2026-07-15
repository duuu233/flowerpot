import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final account = TextEditingController();
  final code = TextEditingController();
  final password = TextEditingController();
  LoginRegion region = LoginRegion.domestic;

  @override
  void dispose() {
    account.dispose();
    code.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('创建账号')),
      body: AppBackground(
        warm: true,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              Text('欢迎加入', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 8),
              const Text('建立你的植物档案，让照顾变得简单。'),
              const SizedBox(height: 26),
              SegmentedButton<LoginRegion>(
                segments: const <ButtonSegment<LoginRegion>>[
                  ButtonSegment(
                    value: LoginRegion.domestic,
                    label: Text('手机号'),
                  ),
                  ButtonSegment(value: LoginRegion.overseas, label: Text('邮箱')),
                ],
                selected: <LoginRegion>{region},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => region = value.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: account,
                decoration: InputDecoration(
                  labelText: region == LoginRegion.domestic ? '手机号' : '邮箱',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: '验证码',
                  suffixIcon: TextButton(
                    onPressed: state.busy
                        ? null
                        : () async {
                            final result = await state.sendCode(
                              account: account.text,
                              region: region,
                              type: 1,
                            );
                            if (context.mounted) {
                              showAppMessage(
                                context,
                                result.message,
                                success: result.success,
                              );
                            }
                          },
                    child: const Text('发送'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '设置密码（至少 8 位）'),
              ),
              const SizedBox(height: 24),
              LoadingButton(
                label: '完成注册',
                loading: state.busy,
                onPressed: () async {
                  final result = await state.register(
                    account: account.text,
                    password: password.text,
                    code: code.text,
                    region: region,
                  );
                  if (!context.mounted) return;
                  showAppMessage(
                    context,
                    result.message,
                    success: result.success,
                  );
                  if (result.success) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      AppRoutes.shell,
                      (_) => false,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
