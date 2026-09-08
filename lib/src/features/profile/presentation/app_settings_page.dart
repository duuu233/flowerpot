import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
// 只引这两个文件而不是整个 design_system：后者也导出一个 showAppMessage，
// 和本页用的 shared 版签名不同，整包导入会变成二义引用。
import '../../../design_system/widgets/dialogs/app_option_dialog.dart';
import '../../../design_system/widgets/feedback/app_confirm_dialog.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';
import '../../auth/presentation/password_page.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
            children: <Widget>[
              SettingGroup(
                children: <Widget>[
                  SettingTile(
                    icon: Icons.password_rounded,
                    title: '修改密码',
                    subtitle: '通过验证码验证账号',
                    onTap: () {
                      final account = state.user?.account ?? '';
                      Navigator.pushNamed(
                        context,
                        AppRoutes.password,
                        arguments: PasswordArguments(
                          account: account,
                          region: account.contains('@')
                              ? LoginRegion.overseas
                              : LoginRegion.domestic,
                        ),
                      );
                    },
                  ),
                  SettingTile(
                    icon: Icons.language_rounded,
                    title: '语种设置',
                    subtitle: state.languageCode == 'zh' ? '简体中文' : 'English',
                    onTap: () => _language(context),
                  ),
                  SettingTile(
                    icon: Icons.notifications_active_outlined,
                    title: '消息通知',
                    trailing: Switch(
                      value: state.notificationsEnabled,
                      onChanged: state.setNotifications,
                    ),
                  ),
                  SettingTile(
                    icon: Icons.system_update_rounded,
                    title: 'App 升级',
                    subtitle: '当前 1.0.0',
                    onTap: () => showAppMessage(context, '当前已是最新版本'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingGroup(
                children: <Widget>[
                  SettingTile(
                    icon: Icons.privacy_tip_outlined,
                    title: '隐私政策',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.privacy),
                  ),
                  SettingTile(
                    icon: Icons.description_outlined,
                    title: '用户协议',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.agreement),
                  ),
                  SettingTile(
                    icon: Icons.info_outline_rounded,
                    title: '关于我们',
                    onTap: () => Navigator.pushNamed(context, AppRoutes.about),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: state.busy ? null : () => _logout(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                child: const Text('退出登录'),
              ),
              TextButton(
                onPressed: state.busy ? null : () => _cancelAccount(context),
                child: const Text(
                  '注销账号',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _language(BuildContext context) async {
    final state = FlowerpotScope.of(context);
    final selected = await showAppOptionDialog<String>(
      context,
      title: '语言',
      selected: state.languageCode,
      // 语言列表由 AppLanguage 枚举生成：以后加语种只改枚举，这一页不用动。
      options: <AppOption<String>>[
        for (final language in AppLanguage.values)
          AppOption<String>(value: language.code, label: language.label),
      ],
    );
    if (selected != null) {
      await state.setLanguage(selected);
    }
  }

  Future<void> _logout(BuildContext context) async {
    final result = await FlowerpotScope.of(context).logout();
    if (!context.mounted) return;
    if (result.success) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.auth, (_) => false);
    } else {
      showAppMessage(context, result.message, success: false);
    }
  }

  Future<void> _cancelAccount(BuildContext context) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '确认注销账号？',
      message: '注销后将无法恢复账号资料。设备请先完成解绑或转移。',
      confirmLabel: '确认注销',
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );
    if (!confirmed || !context.mounted) return;
    final result = await FlowerpotScope.of(context).deleteAccount();
    if (!context.mounted) return;
    if (result.success) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.auth, (_) => false);
    }
  }
}
