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

  /// Accept any non-empty phone and code.
  ///
  /// The demo flow has to reach the app without a real SMS code. A real SDK
  /// login is still attempted first, so a real account keeps a real session;
  /// only a rejection falls back to the demo backend, and the user is told so.
  /// Must be turned off before a production release.
  static final bool acceptAnyVerificationCode = true;
}
