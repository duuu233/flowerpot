import '../../../tuya/tuya_models.dart';

class AccountSecurityPageModel {
  const AccountSecurityPageModel({
    required this.phone,
    required this.passwordStatus,
    required this.forgotPasswordHint,
  });

  factory AccountSecurityPageModel.fromUser(AppUser? user) {
    final account = user?.account.trim() ?? '';
    return AccountSecurityPageModel(
      phone: _maskedPhone(account),
      passwordStatus: account.isEmpty ? '未设置' : '已设置',
      forgotPasswordHint: '通过验证码重置',
    );
  }

  final String phone;
  final String passwordStatus;
  final String forgotPasswordHint;

  static String _maskedPhone(String account) {
    if (RegExp(r'^\d{11}$').hasMatch(account)) {
      return '${account.substring(0, 3)}****${account.substring(7)}';
    }
    if (account.isEmpty || account.contains('@')) return '未绑定手机';
    return account;
  }
}
