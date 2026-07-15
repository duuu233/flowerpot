import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../shared/shared.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String query = '';

  static const faq = <(String, String)>[
    ('为什么设备搜索不到？', '确认花盆指示灯正在闪烁、手机已连接 2.4 GHz Wi-Fi，并允许蓝牙和定位权限。热点模式通常有更高的成功率。'),
    ('土壤湿度多少需要浇水？', '不同植物目标值不同。App 会根据已选植物显示建议，建议同时观察几天趋势，避免按单次读数重复浇水。'),
    ('PPFD 和 DLI 有什么区别？', 'PPFD 是当前有效光强；DLI 是全天有效光照累计，更适合按周或月评估光照是否充足。'),
    ('分享用户需要重新配网吗？', '不需要。设备所有者生成分享链接后，接收方登录即可查看获授权的设备信息。'),
    ('OTA 升级时要注意什么？', '保持花盆充电、在线且网络稳定。升级期间不要断电或恢复出厂设置。'),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = faq
        .where((item) => item.$1.contains(query) || item.$2.contains(query))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('帮助与常见问题')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              TextField(
                onChanged: (value) => setState(() => query = value.trim()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: '搜索问题',
                ),
              ),
              const SizedBox(height: 18),
              GlassCard(
                padding: EdgeInsets.zero,
                child: ExpansionPanelList.radio(
                  elevation: 0,
                  expandedHeaderPadding: EdgeInsets.zero,
                  dividerColor: const Color(0xFFE4EAE4),
                  children: <ExpansionPanelRadio>[
                    for (var index = 0; index < filtered.length; index++)
                      ExpansionPanelRadio(
                        value: filtered[index].$1,
                        headerBuilder: (_, _) => ListTile(
                          leading: const Icon(
                            Icons.help_outline_rounded,
                            color: AppColors.leaf,
                          ),
                          title: Text(
                            filtered[index].$1,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        body: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: Text(filtered[index].$2),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
