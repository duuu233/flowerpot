class LoginPasswordPageModel {
  const LoginPasswordPageModel({
    required this.maskedAccount,
    this.minimumLength = 8,
    this.maximumLength = 20,
  });

  factory LoginPasswordPageModel.fromAccount(String account) {
    return LoginPasswordPageModel(maskedAccount: _maskAccount(account.trim()));
  }

  final String maskedAccount;
  final int minimumLength;
  final int maximumLength;

  String get lengthAdvice => '密码长度为$minimumLength-$maximumLength位字符';

  bool hasValidLength(String password) {
    return password.length >= minimumLength && password.length <= maximumLength;
  }

  static String _maskAccount(String account) {
    if (RegExp(r'^\d{11}$').hasMatch(account)) {
      return '${account.substring(0, 3)}****${account.substring(7)}';
    }

    final at = account.indexOf('@');
    if (at > 0 && at < account.length - 1) {
      final name = account.substring(0, at);
      final visibleName = name.length == 1
          ? name
          : '${name.substring(0, 1)}***${name.substring(name.length - 1)}';
      return '$visibleName${account.substring(at)}';
    }

    if (account.length > 7) {
      return '${account.substring(0, 3)}****${account.substring(account.length - 4)}';
    }
    return account.isEmpty ? '未绑定账号' : account;
  }
}
