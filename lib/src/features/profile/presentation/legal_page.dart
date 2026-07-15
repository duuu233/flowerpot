import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../shared/shared.dart';

class LegalPage extends StatelessWidget {
  const LegalPage({required this.privacy, super.key});

  final bool privacy;

  @override
  Widget build(BuildContext context) {
    final title = privacy ? '隐私政策' : '用户协议';
    final sections = privacy ? _privacy : _agreement;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        '更新日期：2026-07-15  ·  生效日期：2026-07-15',
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                    const SizedBox(height: 24),
                    for (final section in sections) ...<Widget>[
                      Text(
                        section.$1,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 7),
                      Text(section.$2),
                      const SizedBox(height: 20),
                    ],
                    const Text(
                      '说明：正式上架前应由法务根据实际主体、服务器区域、第三方 SDK 清单和联系方式审定本文。',
                      style: TextStyle(color: AppColors.danger, fontSize: 12),
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

  static const _privacy = <(String, String)>[
    (
      '一、我们收集的信息',
      '为完成账号登录、设备配网和智能花盆服务，我们会在获得授权后处理账号标识、设备标识、网络信息、位置、传感器数据以及用户主动上传的头像和图片。',
    ),
    (
      '二、设备与涂鸦服务',
      '设备配网、控制、状态上报、分享和固件升级由涂鸦 Smart Life App SDK 提供。正式发布版本将展示完整的第三方 SDK 信息与数据处理规则。',
    ),
    ('三、权限使用', '位置、蓝牙、相册、相机和通知权限只在相应功能需要时申请；拒绝非必要权限不影响浏览本地内容。'),
    ('四、数据安全', '我们采用访问控制、传输加密和最小权限原则保护数据，并根据业务部署区域落实跨境与本地化要求。'),
    ('五、用户权利', '您可以查阅、更正或删除基本信息，解绑设备，或通过“设置—注销账号”申请删除账号。'),
  ];

  static const _agreement = <(String, String)>[
    ('一、服务内容', '智能花盆 App 提供账号、设备配网与管理、传感器数据展示、设备控制、分享、OTA 和养护建议等服务。'),
    ('二、账号安全', '请妥善保管账号与验证码，不得利用服务实施破坏设备、网络或他人合法权益的行为。'),
    ('三、设备数据', '传感器数据仅用于辅助养护，不构成农业、医疗或安全领域的专业结论；异常情况请结合实际植物状态判断。'),
    ('四、服务变更', '因设备固件、云服务或法律政策变化，我们可能更新功能和条款，并在重要变更时进行提示。'),
    ('五、责任限制', '因断网、停电、设备不当使用或第三方平台不可用造成的服务中断，将在法律允许范围内合理处理。'),
  ];
}
