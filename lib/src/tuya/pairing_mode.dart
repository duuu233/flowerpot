/// 配网方式的**运行时开关**（2026-09-11 产品要求：做一个 EZ 模式先测，原来的 AP 备着，
/// 不行就切回去）。
///
/// ## 两种方式的本质区别
///
/// - [PairingMode.ez]（快连 / SmartConfig）：**手机全程留在路由器上**，App 把 Wi-Fi 凭据以
///   802.11 报文广播出去，设备在空中接收。**不需要连接设备热点 ⇒ 不会出现任何系统 UI。**
///   代价：要求手机连的就是那个 **2.4GHz** 目标网络，且对路由器/手机的兼容性要求更高。
/// - [PairingMode.ap]（热点 / AP-cfg）：手机要先连上设备自己开的热点，再通过它下发凭据。
///   成功率高、兼容性好，但 Android 10+ 上 App 连热点**必然弹一次系统入网授权框**
///   （`WifiNetworkSpecifier`，关不掉、不能代点）。
///
/// ## 为什么是运行时开关而不是编译常量
///
/// 产品要在**同一个包**里把两种都测一遍再定，所以做成页面上可切换的。
/// 定下来之后应当删掉这个开关、只留选中的那一种。
///
/// ⚠️ 这是**测试用开关**，正式包里也可见。定稿前不要依赖它的默认值做任何判断。
enum PairingMode {
  /// 快连：不连热点、零系统 UI。
  ez,

  /// 热点：要连设备热点，Android 10+ 会弹一次系统授权框。
  ap;

  /// 界面上的名字。
  String get label => switch (this) {
    PairingMode.ez => 'EZ 快连',
    PairingMode.ap => 'AP 热点',
  };

  /// 一句话说明，画在选择器下面。
  String get hint => switch (this) {
    PairingMode.ez =>
      '手机留在当前 Wi-Fi 上，直接把密码广播给设备。全程没有系统弹框，'
          '但要求手机连的就是那个 2.4GHz 网络。',
    PairingMode.ap =>
      '先把手机连到设备热点再下发密码。成功率更高，但连热点时系统会弹一次确认框。',
  };

  /// 传给原生桥接的模式名（与 `PairingRequest.mode` 一致）。
  String get wire => switch (this) {
    PairingMode.ez => 'ez',
    PairingMode.ap => 'ap',
  };
}

/// 当前选中的配网方式。
///
/// 默认 [PairingMode.ez]——产品这一轮要测的就是它；测不通再在页面上切回
/// [PairingMode.ap]（那是 git 里最后一版能配网成功的方式）。
abstract final class PairingModeSwitch {
  static PairingMode current = PairingMode.ez;
}
