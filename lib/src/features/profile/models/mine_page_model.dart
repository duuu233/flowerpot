import '../../../tuya/tuya_models.dart';

enum MineMenuKind {
  personalInfo,
  accountSecurity,
  deviceSettings,
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
    this.badge = false,
  });

  final MineMenuKind kind;
  final String label;
  final String? trailingValue;

  /// 行尾的小红点。目前只有「关于YSplanter」用：后端说有新版本时点亮。
  final bool badge;
}

class MinePageModel {
  const MinePageModel({
    required this.nickname,
    required this.avatarPath,
    required this.menuItems,
  });

  /// [feedbackEmail] 来自后台「基础信息配置」（`/Client/Basic/getBasicData` 的
  /// 平台邮箱字段，见 `BackendBasicData.contact`）。后台没配或还没拉到时这一行
  /// 不显示邮箱，也就没有可复制的内容。
  factory MinePageModel.fromUser(
    AppUser? user, {
    String? feedbackEmail,
    bool hasAppUpdate = false,
  }) {
    final email = feedbackEmail?.trim();
    return MinePageModel(
      nickname: user?.nickname.trim().isNotEmpty == true
          ? user!.nickname.trim()
          : '用户',
      avatarPath: user?.avatarUrl,
      menuItems: <MineMenuItem>[
        const MineMenuItem(kind: MineMenuKind.personalInfo, label: '个人信息'),
        const MineMenuItem(
          kind: MineMenuKind.accountSecurity,
          label: '账号与安全',
        ),
        const MineMenuItem(kind: MineMenuKind.deviceSettings, label: '设备设置'),
        MineMenuItem(
          kind: MineMenuKind.feedback,
          label: '意见反馈',
          trailingValue: email == null || email.isEmpty ? null : email,
        ),
        const MineMenuItem(kind: MineMenuKind.privacyPolicy, label: '隐私政策'),
        const MineMenuItem(kind: MineMenuKind.userAgreement, label: '用户协议'),
        MineMenuItem(
          kind: MineMenuKind.about,
          label: '关于YSplanter',
          badge: hasAppUpdate,
        ),
      ],
    );
  }

  final String nickname;
  final String? avatarPath;
  final List<MineMenuItem> menuItems;
}
