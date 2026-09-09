/// Which login entries the login page offers.
///
/// These are product-stage switches, not build modes: each option is hidden
/// because the platform parameters behind it do not exist yet, and turning one
/// back on should be a one-line change once they do. They are `final` rather
/// than `const` so a disabled branch is not folded away as dead code.
abstract final class LoginEntryConfig {
  /// Password login. Hidden while the flow is verification-code only.
  static final bool passwordLogin = false;

  /// WeChat quick login. Still shown, its open-platform parameters are pending.
  static final bool wechatLogin = true;

  /// Alipay quick login. Hidden until the open-platform app is registered.
  static final bool alipayLogin = false;

}
