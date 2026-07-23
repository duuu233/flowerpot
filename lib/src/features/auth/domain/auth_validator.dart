import '../../../tuya/tuya_models.dart';

class AuthValidationException implements Exception {
  const AuthValidationException(this.message);

  final String message;
}

abstract final class AuthValidator {
  static final RegExp _mobilePattern = RegExp(r'^1[3-9]\d{9}$');
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String account(String value, LoginRegion region) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const AuthValidationException('请先填写账号');
    }
    final valid = region == LoginRegion.domestic
        ? _mobilePattern.hasMatch(normalized)
        : _emailPattern.hasMatch(normalized);
    if (!valid) {
      throw AuthValidationException(
        region == LoginRegion.domestic ? '手机号格式不正确' : '邮箱格式不正确',
      );
    }
    return normalized;
  }

  static String credential(String value, {required bool verificationCode}) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw AuthValidationException(verificationCode ? '请输入验证码' : '请输入密码');
    }
    return normalized;
  }

  static String code(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const AuthValidationException('请输入验证码');
    }
    return normalized;
  }

  static String password(String value, {int minimumLength = 8}) {
    if (value.length < minimumLength) {
      throw AuthValidationException('密码至少需要 $minimumLength 位');
    }
    return value;
  }
}
