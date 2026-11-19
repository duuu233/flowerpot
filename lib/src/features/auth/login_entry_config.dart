/// Which login entries the login page offers.
///
/// These are product-stage switches, not build modes: each option is hidden
/// because the platform parameters behind it do not exist yet, and turning one
/// back on should be a one-line change once they do. They are `final` rather
/// than `const` so a disabled branch is not folded away as dead code.
abstract final class LoginEntryConfig {
  /// Password login. Hidden while the flow is verification-code only.
  static final bool passwordLogin = false;

  /// WeChat quick login. Hidden on iOS and Android (2026-11-19 产品：先隐藏、
  /// 代码保留); its open-platform parameters are still pending.
  static final bool wechatLogin = false;

  /// Alipay quick login. Hidden until the open-platform app is registered.
  static final bool alipayLogin = false;

  /// 「其他登录方式」分隔线与快捷登录那一行：一个快捷登录都没开时整块不画。
  static bool get anySocialLogin => wechatLogin || alipayLogin;
}
