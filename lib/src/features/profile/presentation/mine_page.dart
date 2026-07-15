import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final user = state.user;
    final avatar = user?.avatarUrl;
    return AppBackground(
      warm: true,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
          children: <Widget>[
            Text('我的', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 20),
            GlassCard(
              onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
              color: AppColors.ink,
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.lime,
                    backgroundImage: avatar != null && File(avatar).existsSync()
                        ? FileImage(File(avatar))
                        : null,
                    child: avatar == null
                        ? const Icon(
                            Icons.person_rounded,
                            size: 32,
                            color: AppColors.ink,
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          user?.nickname ?? '植物守护者',
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.account ?? '',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white60,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatCard(
                    value: '${state.devices.length}',
                    label: '智能花盆',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    value: '${state.animations.length}',
                    label: '定制图片',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            SettingGroup(
              children: <Widget>[
                SettingTile(
                  icon: Icons.manage_accounts_outlined,
                  title: '基本信息',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
                ),
                SettingTile(
                  icon: Icons.settings_outlined,
                  title: '设置',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.settings),
                ),
                SettingTile(
                  icon: Icons.help_outline_rounded,
                  title: '帮助与常见问题',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.help),
                ),
                SettingTile(
                  icon: Icons.info_outline_rounded,
                  title: '关于我们',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.about),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                state.sdkReady && !state.demoMode
                    ? 'Tuya Smart Life SDK 已连接'
                    : '智能花盆 1.0 · ${state.demoMode ? '体验模式' : 'SDK 待配置'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => GlassCard(
    child: Column(
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 3),
        Text(label),
      ],
    ),
  );
}
