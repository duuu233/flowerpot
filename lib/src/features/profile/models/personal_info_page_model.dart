import '../../../tuya/tuya_models.dart';

class PersonalInfoPageModel {
  const PersonalInfoPageModel({
    required this.nickname,
    required this.phone,
    required this.accountId,
    required this.avatarPath,
  });

  factory PersonalInfoPageModel.fromUser(AppUser? user) {
    return PersonalInfoPageModel(
      nickname: user?.nickname.trim().isNotEmpty == true
          ? user!.nickname.trim()
          : '用户',
      phone: _maskedPhone(user?.account ?? ''),
      accountId: user?.id.trim().isNotEmpty == true ? user!.id.trim() : '—',
      avatarPath: user?.avatarUrl,
    );
  }

  final String nickname;
  final String phone;
  final String accountId;
  final String? avatarPath;

  PersonalInfoPageModel copyWith({
    String? nickname,
    String? phone,
    String? accountId,
    String? avatarPath,
  }) {
    return PersonalInfoPageModel(
      nickname: nickname ?? this.nickname,
      phone: phone ?? this.phone,
      accountId: accountId ?? this.accountId,
      avatarPath: avatarPath ?? this.avatarPath,
    );
  }

  static String _maskedPhone(String account) {
    final value = account.trim();
    if (RegExp(r'^\d{11}$').hasMatch(value)) {
      return '${value.substring(0, 3)}****${value.substring(7)}';
    }
    if (value.isEmpty || value.contains('@')) return '未绑定手机';
    return value;
  }
}
