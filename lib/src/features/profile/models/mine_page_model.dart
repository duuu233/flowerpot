import '../../../tuya/tuya_models.dart';

enum MineMenuKind {
  personalInfo,
  accountSecurity,
  helpCenter,
  feedback,
  privacyPolicy,
  userAgreement,
  about,
}

class MineMenuItem {
  const MineMenuItem({
    required this.kind,
    required this.label,
    this.trailingValue,
  });

  final MineMenuKind kind;
  final String label;
  final String? trailingValue;
}

class MinePageModel {
  const MinePageModel({
    required this.nickname,
    required this.avatarPath,
    required this.menuItems,
  });

  factory MinePageModel.fromUser(AppUser? user) {
    return MinePageModel(
      nickname: user?.nickname.trim().isNotEmpty == true
          ? user!.nickname.trim()
          : '用户',
      avatarPath: user?.avatarUrl,
      menuItems: const <MineMenuItem>[
        MineMenuItem(kind: MineMenuKind.personalInfo, label: '个人信息'),
        MineMenuItem(kind: MineMenuKind.accountSecurity, label: '账号与安全'),
        MineMenuItem(kind: MineMenuKind.helpCenter, label: '帮助中心'),
        // No feedback channel is wired yet. The trailing value stays short so
        // the row label keeps its width in the fixed Figma panel.
        MineMenuItem(
          kind: MineMenuKind.feedback,
          label: '意见反馈',
          trailingValue: '待配置',
        ),
        MineMenuItem(kind: MineMenuKind.privacyPolicy, label: '隐私政策'),
        MineMenuItem(kind: MineMenuKind.userAgreement, label: '用户协议'),
        MineMenuItem(kind: MineMenuKind.about, label: '关于YSplanter'),
      ],
    );
  }

  final String nickname;
  final String? avatarPath;
  final List<MineMenuItem> menuItems;
}
