import '../../../tuya/tuya_models.dart';

/// 「我的」页菜单项。
///
/// ⚠️ 2026-09-21 产品要求**去掉「设备设置」**：它是为「刚配网还没选植物时够不到解绑」
/// 加的备用入口，现在设备列表就是首页，设备设置从各台设备自己的页面进。
enum MineMenuKind {
  personalInfo,
  accountSecurity,
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

  /// 行尾的小红点。目前只有「关于东方金穗」用：后端说有新版本时点亮。
  final bool badge;
}

class MinePageModel {
  const MinePageModel({
    required this.nickname,
    required this.avatarPath,
    required this.menuItems,
  });

  /// [feedbackEmail] 来自后台「系统设置」里配的平台邮箱（`/Client/Basic/getBasicData`
  /// 返回的 `platformEmail`，见 `BackendBasicData.platformEmail`）。后台没配或还没拉到时
  /// 这一行不显示邮箱，也就没有可复制的内容。
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
        MineMenuItem(
          kind: MineMenuKind.feedback,
          label: '意见反馈',
          trailingValue: email == null || email.isEmpty ? null : email,
        ),
        const MineMenuItem(kind: MineMenuKind.privacyPolicy, label: '隐私政策'),
        const MineMenuItem(kind: MineMenuKind.userAgreement, label: '用户协议'),
        MineMenuItem(
          kind: MineMenuKind.about,
          label: '关于东方金穗',
          badge: hasAppUpdate,
        ),
      ],
    );
  }

  final String nickname;
  final String? avatarPath;
  final List<MineMenuItem> menuItems;
}
