import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../shared/shared.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于我们')),
    body: AppBackground(
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: <Widget>[
            const Center(child: PlantIllustration(size: 180)),
            Center(
              child: Text(
                '智能花盆',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'Version 1.0.0 (1)',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 24),
            const GlassCard(
              child: Text(
                '我们希望把复杂的光照、水分和环境数据，变成简单、温和、可以马上行动的养护建议。让每一株植物都被看见，也让忙碌生活里多一点生长的节奏。',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.7),
              ),
            ),
            const SizedBox(height: 16),
            const SettingGroup(
              children: <Widget>[
                SettingTile(
                  icon: Icons.mail_outline_rounded,
                  title: '联系我们',
                  subtitle: 'support@flowerpot.example',
                ),
                SettingTile(
                  icon: Icons.language_rounded,
                  title: '官方网站',
                  subtitle: 'www.flowerpot.example',
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
