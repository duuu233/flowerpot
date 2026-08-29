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
  ///
  /// 2026-08-29 起关闭：真实短信链路联调时，这个回落会把「验证码校验失败」伪装
  /// 成一次成功登录（只弹一句提示就进演示会话），失败原因看不到。要恢复演示包
  /// 把它改回 `true` 即可。
  static final bool acceptAnyVerificationCode = false;
}
