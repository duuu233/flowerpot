import CoreBluetooth
import Flutter
import NetworkExtension
import UIKit

#if canImport(ThingSmartHomeKit)
import ThingSmartHomeKit
#endif
// 蓝牙扫描与双模配网（ThingSmartBLEManager / ThingSmartBLEWifiActivator）所在的模块，
// 由 ThingSmartHomeKit 依赖带进来。单独判断：模块不在时蓝牙方法如实报不可用，不影响其余功能编译。
#if canImport(ThingSmartBLEKit)
import ThingSmartBLEKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var tuyaBridge: FlowerpotTuyaBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FlowerpotTuyaBridge") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.common.yikaltd/tuya",
      binaryMessenger: registrar.messenger()
    )
    let bridge = FlowerpotTuyaBridge()
    tuyaBridge = bridge
    channel.setMethodCallHandler(bridge.handle)
    // One-way channel for what the device reports on its own; mirrored by
    // `TuyaConfig.eventChannelName` and by the Android bridge.
    FlutterEventChannel(
      name: "com.common.yikaltd/tuya_events",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(bridge)
  }
}

final class FlowerpotTuyaBridge: NSObject {
  /// Dart's end of the event channel, or nil while nothing is listening.
  fileprivate var eventSink: FlutterEventSink?

  #if canImport(ThingSmartHomeKit)
  private let homeManager = ThingSmartHomeManager()
  private var currentHome: ThingSmartHome?
  private var pairingResult: FlutterResult?

  /// Devices with this bridge set as their delegate, keyed by device id.
  ///
  /// `ThingSmartDevice.delegate` is weak and the SDK does not retain the
  /// instance, so dropping it here would silently stop the reports.
  private var watched: [String: ThingSmartDevice] = [:]

  /// 正在升级、但不在 [watched] 里的设备实例，按 deviceId 缓存。
  ///
  /// 和 [watched] 是同一个道理，只是更容易踩：升级要跑几分钟，而
  /// `upgradeFirmware` 一返回，方法里临时 new 出来的那个 `ThingSmartDevice`
  /// 就没人引用了——delegate 是 weak，实例一释放，`firmwareUpgradeProgress`
  /// 和成败回调就再也不来，界面上表现成进度条停着不动。所以升级期间把它留在
  /// 这里，出终态或收尾时才放。
  private var upgrading: [String: ThingSmartDevice] = [:]

  /// Last provisioning token and when it was fetched. Never handed to Dart:
  /// it is a short-lived cloud credential and the debug console logs whatever
  /// it receives.
  private var activatorToken: String?
  private var activatorTokenAt: Date?

  /// 由 App 发起连接的设备热点名，配网结束或取消时据此删掉临时配置。
  private var joinedHotspotSsid: String?

  /// Tuya issues provisioning tokens with a 10-minute validity; 8 leaves room
  /// for the user to switch networks and for the activator's handshake.
  private static let activatorTokenTTL: TimeInterval = 8 * 60

  // MARK: 蓝牙发现与双模配网的状态

  /// 只用来读系统蓝牙状态和弹授权框；扫描、连接都交给涂鸦 SDK 自己的蓝牙管理。
  fileprivate var bluetoothCentral: CBCentralManager?
  /// 等蓝牙状态定下来（不再是 unknown / resetting）的调用方。
  fileprivate var bluetoothStateWaiters: [BluetoothStateWaiter] = []

  /// 本轮扫到的设备（SDK 的 `ThingBLEAdvModel`），按 uuid 存。查产品信息、配网都按 uuid 取回。
  /// 存成 NSObject：字段一律按需安全读取，不依赖这一版 SDK 的属性名都对得上。
  fileprivate var bleScanned: [String: NSObject] = [:]
  fileprivate var bleScanning = false
  /// 每开一轮加一；旧一轮的到时回调据此作废，不会把新一轮标成已结束。
  fileprivate var bleScanRound = 0
  /// 本轮发现回调的次数，随事件带给 Dart（`BleDevice.seq`）。
  fileprivate var bleSeq = 0

  /// 正在等结果的那次 pairBleDevice。和 AP 的 [pairingResult] 分开：两套 activator、两套回调。
  fileprivate var blePairingResult: FlutterResult?
  /// 双模配网兜底超时：SDK 的回调没来（签名对不上或设备没回话）时，不让 Dart 一直挂着。
  fileprivate var blePairingWatchdog: DispatchWorkItem?
  #endif

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(ThingSmartHomeKit)
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "initialize": initialize(result)
    case "currentUser": currentUser(result)
    case "sendVerificationCode": sendCode(args, result)
    case "login": login(args, result)
    case "loginWithUid": loginWithUid(args, result)
    case "register": register(args, result)
    case "resetPassword": resetPassword(args, result)
    case "updateNickname": updateNickname(args, result)
    case "logout": logout(result)
    case "cancelAccount": cancelAccount(result)
    case "getDevices": withHome(result) { [weak self] home in self?.loadDevices(home, result) }
    case "deviceSnapshot":
      let id = args["deviceId"] as? String ?? ""
      watchDevice(id)
      result(watched[id].flatMap { deviceSnapshot($0) })
    case "deviceOnlineStates":
      let ids = args["deviceIds"] as? [String] ?? []
      var states: [String: Bool] = [:]
      for id in ids {
        watchDevice(id)
        if let device = watched[id] ?? ThingSmartDevice(deviceId: id),
           let model = device.deviceModel {
          states[id] = model.isOnline
        }
      }
      result(states)
    case "scanWifi": scanWifi(result)
    case "currentHomeId": withHome(result) { home in result(String(home.homeModel.homeId)) }
    // Dart 侧按账号记住上次用过的家庭，会话一开始钉回来：家庭属于涂鸦账号，不该
    // 每次登录重新从列表里挑。
    case "setHomeId": setHome(args, result)
    case "setHomeTag":
      homeTag = (args["tag"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      result(nil)
    case "prepareActivatorToken": prepareActivatorToken(result)
    // ThingActivatorMode 是 ObjC 的 NS_ENUM，运行时拿不到常量名，没法像 Android
    // 那样让 SDK 自己报一遍。要确认 iOS 支不支持双模只能查平台文档。
    case "joinDeviceHotspot": joinDeviceHotspot(args, result)
    case "leaveDeviceHotspot": leaveDeviceHotspot(result)
    case "cancelPairing": cancelPairing(result)
    case "pairWifiDevice": pairWifi(args, result)
    // 蓝牙发现 + 双模配网（凭据经蓝牙交给设备，不碰设备热点）。返回结构与 Android 一致，
    // Dart 侧同一套解析，见 TuyaRepository.bleProbe / startBleScan / pairBleDevice。
    case "ensureBlePermissions": ensureBlePermissions(result)
    case "openAppSettings": openAppSettings(result)
    case "bleProbe": bleProbe(result)
    case "startBleScan": startBleScan(args, result)
    case "stopBleScan":
      stopBleScanning()
      result(nil)
    case "disconnectBleDevice": disconnectBleDevice(result)
    case "queryDeviceProductInfo": queryBleProductInfo(args, result)
    // 设备自报 Wi-Fi 列表 iOS 暂未接：扫描结果里 supportWifiList 恒为 false，Dart 不会调到这里，
    // 用户在下一页手动输入 Wi-Fi 名（会预填手机当前连接的网络）。
    case "queryDeviceConfigState":
      sdkError(result, code: "ble_wifi_list_unsupported", message: "iOS 端暂不支持读取设备扫到的 Wi-Fi 列表，请手动输入 Wi-Fi 名称")
    case "pairBleDevice": pairBleDevice(args, result)
    case "publishDps": publishDps(args, result)
    case "renameDevice": renameDevice(args, result)
    case "removeDevice": removeDevice(args, reset: false, result)
    case "resetFactory": removeDevice(args, reset: true, result)
    case "getStatistics": sdkError(result, code: "service_configuration_required", message: "请在涂鸦平台开通设备数据统计服务")
    // The iOS Home SDK shares to an account (ThingSmartDeviceShare), not to a
    // link: there is no iOS counterpart to the Expansion SDK call Android uses
    // here. Wiring it up needs the share screen to collect a recipient first.
    case "createShareLink": sdkError(result, code: "share_service_unavailable", message: "iOS 端设备分享需按账号分享，请先在分享页填写接收账号")
    case "checkFirmware": checkFirmware(args, result)
    case "startFirmwareUpgrade": startFirmwareUpgrade(args, result)
    case "uploadAnimation": sdkError(result, code: "product_protocol_required", message: "图片同步需要设备 PID 对应的文件传输协议")
    default: result(FlutterMethodNotImplemented)
    }
    #else
    result(FlutterError(
      code: "sdk_unavailable",
      message: "请将 ThingSmartCryption 安全组件放入 ios/TuyaSDK 后执行 pod install",
      details: nil
    ))
    #endif
  }

  #if canImport(ThingSmartHomeKit)
  private func initialize(_ result: @escaping FlutterResult) {
    let key = Bundle.main.object(forInfoDictionaryKey: "THING_SMART_APPKEY") as? String ?? ""
    let secret = Bundle.main.object(forInfoDictionaryKey: "THING_SMART_APPSECRET") as? String ?? ""
    guard !key.isEmpty, !secret.isEmpty, !key.contains("$(") else {
      sdkError(result, code: "credentials_missing", message: "请在 ios/Flutter/Tuya.xcconfig 配置涂鸦密钥")
      return
    }
    ThingSmartSDK.sharedInstance()?.start(withAppKey: key, secretKey: secret)
    #if DEBUG
    ThingSmartSDK.sharedInstance()?.debugMode = true
    #endif
    result(true)
  }

  private func currentUser(_ result: @escaping FlutterResult) {
    guard let user = ThingSmartUser.sharedInstance(), user.isLogin else {
      result(nil)
      return
    }
    result(userMap(user))
  }

  private func sendCode(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let account = args["account"] as? String ?? ""
    let country = args["countryCode"] as? String ?? "86"
    let type = args["type"] as? Int ?? 2
    let user = ThingSmartUser.sharedInstance()
    let region = user?.getDefaultRegion(withCountryCode: country)
    user?.sendVerifyCode(
      withUserName: account,
      region: region,
      countryCode: country,
      type: type,
      success: { result(nil) },
      failure: { error in self.fail(result, error) }
    )
  }

  private func login(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let account = args["account"] as? String ?? ""
    let credential = args["credential"] as? String ?? ""
    let country = args["countryCode"] as? String ?? "86"
    let email = args["email"] as? Bool ?? false
    let codeLogin = args["verificationCode"] as? Bool ?? false
    let success: () -> Void = { [weak self] in
      guard let self, let user = ThingSmartUser.sharedInstance() else { return }
      result(self.userMap(user))
    }
    let failure: (Error?) -> Void = { error in self.fail(result, error) }
    if email {
      ThingSmartUser.sharedInstance()?.login(byEmail: country, email: account, password: credential, success: success, failure: failure)
    } else if codeLogin {
      ThingSmartUser.sharedInstance()?.login(withMobile: account, countryCode: country, code: credential, success: success, failure: failure)
    } else {
      ThingSmartUser.sharedInstance()?.login(byPhone: country, phoneNumber: account, password: credential, success: success, failure: failure)
    }
  }

  /// 自有账号体系登录：APP 后端下发内部编号与配套密码，涂鸦侧据此登录，
  /// 账号不存在时自动注册。国内账号走这条路，不是 `login`。
  private func loginWithUid(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let uid = args["uid"] as? String ?? ""
    let password = args["password"] as? String ?? ""
    let country = args["countryCode"] as? String ?? "86"
    ThingSmartUser.sharedInstance()?.loginOrRegister(
      withCountryCode: country,
      uid: uid,
      password: password,
      createHome: true,
      success: { [weak self] _ in
        guard let self, let user = ThingSmartUser.sharedInstance() else { return }
        result(self.userMap(user))
      },
      failure: { error in self.fail(result, error) }
    )
  }

  private func register(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let account = args["account"] as? String ?? ""
    let password = args["password"] as? String ?? ""
    let code = args["code"] as? String ?? ""
    let country = args["countryCode"] as? String ?? "86"
    let email = args["email"] as? Bool ?? false
    let success: () -> Void = { [weak self] in
      guard let self, let user = ThingSmartUser.sharedInstance() else { return }
      result(self.userMap(user))
    }
    let failure: (Error?) -> Void = { error in self.fail(result, error) }
    if email {
      ThingSmartUser.sharedInstance()?.register(byEmail: country, email: account, password: password, code: code, success: success, failure: failure)
    } else {
      ThingSmartUser.sharedInstance()?.register(byPhone: country, phoneNumber: account, password: password, code: code, success: success, failure: failure)
    }
  }

  private func resetPassword(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let account = args["account"] as? String ?? ""
    let password = args["newPassword"] as? String ?? ""
    let code = args["code"] as? String ?? ""
    let country = args["countryCode"] as? String ?? "86"
    let email = args["email"] as? Bool ?? false
    let success: () -> Void = { result(nil) }
    let failure: (Error?) -> Void = { error in self.fail(result, error) }
    if email {
      ThingSmartUser.sharedInstance()?.resetPassword(
        byEmail: country,
        email: account,
        newPassword: password,
        code: code,
        success: success,
        failure: failure
      )
    } else {
      ThingSmartUser.sharedInstance()?.resetPassword(
        byPhone: country,
        phoneNumber: account,
        newPassword: password,
        code: code,
        success: success,
        failure: failure
      )
    }
  }

  private func updateNickname(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let nickname = args["nickname"] as? String ?? ""
    ThingSmartUser.sharedInstance()?.updateNickname(
      nickname,
      success: { result(nil) },
      failure: { error in self.fail(result, error) }
    )
  }

  private func logout(_ result: @escaping FlutterResult) {
    ThingSmartUser.sharedInstance()?.loginOut({ [weak self] in
      self?.endSession()
      result(nil)
    }, failure: { error in self.fail(result, error) })
  }

  private func cancelAccount(_ result: @escaping FlutterResult) {
    ThingSmartUser.sharedInstance()?.cancelAccount({ [weak self] in
      self?.endSession()
      result(nil)
    }, failure: { error in self.fail(result, error) })
  }

  /// The devices and the home belong to the account that is going away.
  private func endSession() {
    stopBleScanning()
    finishBlePairing(with: FlutterError(code: "pair_cancelled", message: "账号已退出", details: nil))
    releaseDeviceListeners()
    currentHome = nil
    activatorToken = nil
    activatorTokenAt = nil
  }

  /// 本账号的家庭名标记（`YS-<userNo>`）。家庭 id 只能由涂鸦分配，但名字是我们
  /// 能定的：建家时用它，认领时优先认它，这样同一个账号在任何手机上都落到同一个
  /// 家庭。
  private var homeTag: String?

  private func setHome(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let text = args["homeId"] as? String, let id = Int64(text),
          let home = ThingSmartHome(homeId: id) else {
      // 传空或不可用的值 = 作废当前固定的家庭，下次调用重新按涂鸦的列表解析。
      currentHome = nil
      result(nil)
      return
    }
    currentHome = home
    result(nil)
  }

  private func withHome(_ result: @escaping FlutterResult, ready: @escaping (ThingSmartHome) -> Void) {
    if let currentHome {
      ready(currentHome)
      return
    }
    queryHome(result, retry: true, ready: ready)
  }

  /// 空列表先重查一次再建家：一次瞬时的空返回会给账号留下一个永久的空家庭，
  /// 下次登录挑到它就是「设备全没了」。
  private func queryHome(
    _ result: @escaping FlutterResult,
    retry: Bool,
    ready: @escaping (ThingSmartHome) -> Void
  ) {
    homeManager.getHomeList(success: { [weak self] homes in
      guard let self else { return }
      if (homes ?? []).isEmpty, retry {
        self.queryHome(result, retry: false, ready: ready)
        return
      }
      // 家庭列表的顺序在两次登录之间并不保证一致，取 `first` 会让同一个账号这次
      // 读到 A 家的设备、下次读到 B 家（B 家往往是缓存为空时自动建出来的空家），
      // 表现就是「重新登录后设备全没了」。按 homeId 从小到大取，最早建的那个通常
      // 就是设备所在的家庭，而且每次登录选到的都一样。
      // 名字对上本账号标记的排最前，其余按 homeId 从小到大——前者平手时也要有个
      // 稳定顺序，否则又回到「每次登录挑到不同家庭」。
      let tag = self.homeTag
      let ordered = (homes ?? []).sorted { left, right in
        let leftTagged = tag != nil && left.name == tag
        let rightTagged = tag != nil && right.name == tag
        if leftTagged != rightTagged { return leftTagged }
        return left.homeId < right.homeId
      }
      if let model = ordered.first, let home = ThingSmartHome(homeId: model.homeId) {
        print("[flowerpot] home picked \(model.homeId) (\(model.name ?? "")) of \(ordered.count) homes, tag=\(tag ?? "-")")
        self.currentHome = home
        ready(home)
      } else {
        self.homeManager.addHome(
          // 用本账号的标记当家庭名，下次登录就能按名字认回来。
          withName: tag ?? "我的花园",
          geoName: "",
          rooms: [],
          latitude: 0,
          longitude: 0,
          success: { homeId in
            guard let home = ThingSmartHome(homeId: homeId) else { return }
            self.currentHome = home
            ready(home)
          },
          failure: { error in self.fail(result, error) }
        )
      }
    }, failure: { error in self.fail(result, error) })
  }

  private func loadDevices(_ home: ThingSmartHome, _ result: @escaping FlutterResult) {
    home.getDetailWithSuccess({ [weak self] _ in
      guard let self else { return }
      let devices = home.deviceList ?? []
      // The snapshot below is a point in time; the delegates registered here
      // are what keep it current afterwards.
      self.watchDevices(devices.map { $0.devId ?? "" })
      result(devices.map(self.deviceMap))
    }, failure: { error in self.fail(result, error) })
  }

  private func pairWifi(_ args: [String: Any], _ result: @escaping FlutterResult) {
    // 复用预取的令牌——AP 配网能成立全靠这一步：跑到这里时手机已经连在设备热点
    // 上，云端不可达。EZ 全程连在路由器上，走的就是下面这条回落路径。
    if let token = freshActivatorToken() {
      startActivator(args, result, token: token)
      return
    }
    withHome(result) { [weak self] home in
      self?.fetchActivatorToken(home, result) { token in
        self?.startActivator(args, result, token: token)
      }
    }
  }

  private func startActivator(
    _ args: [String: Any],
    _ result: @escaping FlutterResult,
    token: String
  ) {
    guard let activator = ThingSmartActivator.sharedInstance() else {
      sdkError(result, code: "sdk_unavailable", message: "无法获取配网实例")
      return
    }
    // 上一次配网还没回话就又来了一次：先把旧的了结。直接覆盖 pairingResult 的话
    // 旧那次的 FlutterResult 永远不会被调用，Dart 侧的 Future 就永远挂着。
    finishPairing(with: FlutterError(code: "pair_cancelled", message: "被新的配网请求取代", details: nil))
    pairingResult = result
    activator.delegate = self
    // **AP 是唯一的配网模式。** EZ 真机实测设备不支持，2026-09-11 整条删掉，Dart 侧
    // 也不再下发 `mode`——原来那句 `args["mode"] == "ez" ? EZ : AP` 留着是个陷阱：
    // 字段没了之后它恒真走 AP 没错，但读一个不存在的键会让人以为还能切模式。
    activator.startConfigWiFi(
      ThingActivatorModeAP,
      ssid: args["ssid"] as? String ?? "",
      password: args["password"] as? String ?? "",
      token: token,
      timeout: 120
    )
  }

  private func publishDps(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["deviceId"] as? String,
          let dps = args["dps"] as? [String: Any],
          let device = ThingSmartDevice(deviceId: id) else {
      sdkError(result, code: "bad_args", message: "设备参数错误")
      return
    }
    device.publishDps(dps, success: { result(nil) }, failure: { error in self.fail(result, error) })
  }

  private func renameDevice(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["deviceId"] as? String,
          let name = args["name"] as? String,
          let device = ThingSmartDevice(deviceId: id) else {
      sdkError(result, code: "bad_args", message: "设备参数错误")
      return
    }
    device.renameDevice(withName: name, success: { result(nil) }, failure: { error in self.fail(result, error) })
  }

  private func removeDevice(_ args: [String: Any], reset: Bool, _ result: @escaping FlutterResult) {
    guard let id = args["deviceId"] as? String, let device = ThingSmartDevice(deviceId: id) else {
      sdkError(result, code: "bad_args", message: "设备参数错误")
      return
    }
    if reset {
      device.resetFactory({ result(nil) }, failure: { error in self.fail(result, error) })
    } else {
      device.remove({ result(nil) }, failure: { error in self.fail(result, error) })
    }
  }

  /// 了结进行中的配网：停掉 activator，把 [value] 回给等着的那次 pairWifiDevice。
  /// 没有配网在跑时什么都不做。
  private func finishPairing(with value: Any?) {
    guard let callback = pairingResult else { return }
    pairingResult = nil
    ThingSmartActivator.sharedInstance()?.stopConfigWiFi()
    ThingSmartActivator.sharedInstance()?.delegate = nil
    callback(value)
  }

  /// 中止进行中的配网并释放热点配置。没有配网在跑时也安全。
  private func cancelPairing(_ result: @escaping FlutterResult) {
    finishPairing(with: FlutterError(code: "pair_cancelled", message: "配网已被中止", details: nil))
    finishBlePairing(with: FlutterError(code: "pair_cancelled", message: "配网已被中止", details: nil))
    removeHotspotConfiguration()
    result(nil)
  }

  /// App 自己连设备热点。
  ///
  /// 需要 Hotspot Configuration entitlement：Apple 开发者后台为 App ID 开启
  /// Hotspot Configuration，并在 entitlements 文件里加
  /// `com.apple.developer.networking.HotspotConfiguration`。没有时 `apply` 会以
  /// 错误返回，这里报 `hotspot_join_unsupported`，Dart 侧据此回落到引导用户去
  /// 系统设置手动连接，而不是静默失败。
  private func joinDeviceHotspot(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let ssid = args["ssid"] as? String ?? ""
    let prefix = args["prefix"] as? String ?? ""
    let configuration: NEHotspotConfiguration
    if !ssid.isEmpty {
      configuration = NEHotspotConfiguration(ssid: ssid)
    } else if #available(iOS 13.0, *), !prefix.isEmpty {
      configuration = NEHotspotConfiguration(ssidPrefix: prefix)
    } else {
      sdkError(result, code: "hotspot_join_unsupported", message: "需要设备热点名称才能发起连接")
      return
    }
    // 只连这一次：配网完成后设备会关掉热点，不能让系统记住它以后自动重连。
    configuration.joinOnce = true
    let joined = ssid.isEmpty ? prefix : ssid
    NEHotspotConfigurationManager.shared.apply(configuration) { [weak self] error in
      DispatchQueue.main.async {
        guard let self else { return }
        guard let error = error as NSError? else {
          self.joinedHotspotSsid = joined
          result(true)
          return
        }
        // NS_ERROR_ENUM 在 Swift 里是带 Code 的结构体，按原始码比较最不挑 SDK 版本。
        let hotspotError = error.domain == NEHotspotConfigurationErrorDomain
        if hotspotError, error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
          // 手机本来就连在这个热点上，不算失败。
          self.joinedHotspotSsid = joined
          result(true)
        } else if hotspotError, error.code == NEHotspotConfigurationError.userDenied.rawValue {
          self.sdkError(result, code: "hotspot_join_cancelled", message: "已取消连接设备热点")
        } else {
          // 缺 entitlement、系统不支持等都到这里；Dart 侧回落到手动引导。
          self.sdkError(
            result,
            code: "hotspot_join_unsupported",
            message: "iOS 无法由 App 连接热点（\(error.code)）：\(error.localizedDescription)"
          )
        }
      }
    }
  }

  private func leaveDeviceHotspot(_ result: @escaping FlutterResult) {
    removeHotspotConfiguration()
    result(nil)
  }

  /// 删掉由 App 加的临时热点配置。joinOnce 的配置本就不持久，这里只是保险。
  private func removeHotspotConfiguration() {
    guard let ssid = joinedHotspotSsid else { return }
    joinedHotspotSsid = nil
    NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
  }

  /// The network the phone is on. The list is always empty on iOS: there is no
  /// public API to scan for nearby access points, so provisioning asks the
  /// user to pick the network in Settings instead of offering a list.
  ///
  /// Reading even the current SSID needs the "Access WiFi Information"
  /// capability and location permission; without them this reports nothing
  /// rather than failing.
  private func scanWifi(_ result: @escaping FlutterResult) {
    guard #available(iOS 14.0, *) else {
      result(currentNetwork(nil))
      return
    }
    NEHotspotNetwork.fetchCurrent { network in
      DispatchQueue.main.async { result(self.currentNetwork(network?.ssid)) }
    }
  }

  /// The shape `WifiScan` decodes. The band is unknown on iOS, so the app
  /// falls back to "频段未知" instead of claiming 2.4 GHz.
  private func currentNetwork(_ ssid: String?) -> [String: Any?] {
    return [
      "networks": [Any](),
      "current": ssid,
      "currentFrequency": nil,
    ]
  }

  /// Fetches a provisioning token and caches it, without starting anything.
  ///
  /// AP mode needs this as its own step: once the phone joins the device's
  /// hotspot it has no route to the cloud, so the token has to be obtained
  /// while it is still on the router.
  private func prepareActivatorToken(_ result: @escaping FlutterResult) {
    withHome(result) { [weak self] home in
      self?.fetchActivatorToken(home, result) { _ in result(nil) }
    }
  }

  private func fetchActivatorToken(
    _ home: ThingSmartHome,
    _ result: @escaping FlutterResult,
    ready: @escaping (String) -> Void
  ) {
    ThingSmartActivator.sharedInstance()?.getTokenWithHomeId(
      home.homeModel.homeId,
      success: { [weak self] token in
        guard let token else {
          self?.sdkError(result, code: "token_missing", message: "配网令牌获取失败")
          return
        }
        self?.activatorToken = token
        self?.activatorTokenAt = Date()
        ready(token)
      },
      failure: { [weak self] error in self?.fail(result, error) }
    )
  }

  /// A cached token that is still inside its validity window.
  private func freshActivatorToken() -> String? {
    guard let token = activatorToken, let at = activatorTokenAt else { return nil }
    return Date().timeIntervalSince(at) < Self.activatorTokenTTL ? token : nil
  }

  private func checkFirmware(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["deviceId"] as? String, let device = ThingSmartDevice(deviceId: id) else {
      sdkError(result, code: "bad_args", message: "设备参数错误")
      return
    }
    // 闭包显式捕获 device：回调是异步的，不捕获的话实例可能在云端回话之前就被
    // ARC 释放，结果既不 success 也不 failure。
    device.getFirmwareUpgradeInfo({ [weak self, device] models in
      self?.otaLog(id, "checkFirmware → \(models?.count ?? 0) 条：\(FlowerpotTuyaBridge.otaModels(models))")
      // One model per upgradable component; upgradeStatus 1 is "an update is
      // waiting", 2 is "upgrading" and 5 is "waiting for the device to wake".
      // 2/5 是已经在跑的升级（例如升级中途关掉 App 后重开）：报 inProgress，Dart 只
      // 接回、不重新发起，与 Android 一致。此前只认 1，升级中会被当成「已是最新」。
      // 新版本和当前版本都从同一条记录取，避免把两个组件的版本号并排显示。
      let pending = models?.first(where: { $0.upgradeStatus == 1 })
      let running = models?.first(where: { $0.upgradeStatus == 2 || $0.upgradeStatus == 5 })
      if let model = pending ?? running {
        result([
          "version": model.version,
          "currentVersion": model.currentVersion,
          "componentType": model.type,
          "inProgress": pending == nil,
          // 平台配的升级方式：0 提醒 / 2 强制 / 3 检测，与 Android 一致。
          "upgradeType": model.upgradeType,
        ])
      } else {
        result(nil)
      }
    }, failure: { [weak self, device] error in
      self?.otaLog(id, "checkFirmware 失败 \(FlowerpotTuyaBridge.otaError(error))")
      self?.fail(result, error)
    })
  }

  private func startFirmwareUpgrade(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["deviceId"] as? String, let device = otaDevice(id) else {
      sdkError(result, code: "bad_args", message: "设备参数错误")
      return
    }
    // The upgrade is started per component, and the component type only comes
    // from the upgrade info, so it is read first.
    let targetVersion = (args["targetVersion"] as? String)?
      .trimmingCharacters(in: .whitespaces) ?? ""
    let expectedComponent = (args["componentType"] as? NSNumber)?.intValue
    otaLog(id, "startFirmwareUpgrade target=\(targetVersion) component=\(expectedComponent.map { String($0) } ?? "nil")")
    device.getFirmwareUpgradeInfo({ [weak self] models in
      guard let self else { return }
      self.otaLog(id, "getFirmwareUpgradeInfo → \(models?.count ?? 0) 条：\(FlowerpotTuyaBridge.otaModels(models))")
      let matching = (models ?? []).filter {
        (targetVersion.isEmpty || $0.version == targetVersion) &&
          (expectedComponent == nil || $0.type == expectedComponent)
      }
      if matching.first(where: { $0.upgradeStatus == 1 }) == nil,
        matching.contains(where: { $0.upgradeStatus == 2 || $0.upgradeStatus == 5 })
      {
        // 接回已经在跑的升级：留住实例和 delegate 收进度，绝不重新下发。
        self.otaLog(id, "接回进行中的升级，不重新下发")
        result(nil)
        self.emitOta(id, "running")
        return
      }
      guard let pending = matching.first(where: { $0.upgradeStatus == 1 }) else {
        self.otaLog(id, "匹配 \(matching.count) 条，没有待升级的，按已是最新返回")
        self.releaseOta(id)
        self.sdkError(result, code: "firmware_up_to_date", message: "当前固件已是最新版本")
        return
      }
      self.otaLog(id, "调用 SDK upgradeFirmware(type=\(pending.type))")
      device.upgradeFirmware(
        pending.type,
        // 只回答"已发起"：下载和烧录之后几分钟的进度、成败都从 delegate 走
        // 事件通道，和 Android 一致。
        success: {
          self.otaLog(id, "upgradeFirmware 已受理")
          result(nil)
        },
        failure: { error in
          self.otaLog(id, "upgradeFirmware 失败 \(FlowerpotTuyaBridge.otaError(error))")
          self.releaseOta(id)
          self.fail(result, error)
        }
      )
    }, failure: { [weak self] error in
      self?.otaLog(id, "getFirmwareUpgradeInfo 失败 \(FlowerpotTuyaBridge.otaError(error))")
      self?.releaseOta(id)
      self?.fail(result, error)
    })
  }

  /// 升级期间用的设备实例：已经在监听的那台直接复用（它的 delegate 已经是
  /// 自己），否则新建一台、设上 delegate 并留住引用。
  private func otaDevice(_ deviceId: String) -> ThingSmartDevice? {
    if let device = watched[deviceId] ?? upgrading[deviceId] { return device }
    guard !deviceId.isEmpty, let device = ThingSmartDevice(deviceId: deviceId) else {
      return nil
    }
    device.delegate = self
    upgrading[deviceId] = device
    return device
  }

  /// 放掉升级用的实例。[watched] 里那台不归这里管：它还要继续收 DP 上报。
  private func releaseOta(_ deviceId: String) {
    guard let device = upgrading.removeValue(forKey: deviceId) else { return }
    otaLog(deviceId, "释放升级用设备实例")
    device.delegate = nil
  }

  /// OTA 原始日志：转给 Dart 写进手机上的 OTA 调试文件（`OtaDebugLog`，2026-10-26）。
  /// 只记录 SDK 给了什么、桥接据此做了什么，不改升级逻辑；用户包由 Dart 侧总闸丢弃。
  fileprivate func otaLog(_ deviceId: String, _ line: String) {
    emit(["type": "otaLog", "deviceId": deviceId, "line": line])
  }

  fileprivate static func otaModels(_ models: [ThingSmartFirmwareUpgradeModel]?) -> String {
    (models ?? []).map {
      "{type=\($0.type) version=\($0.version ?? "nil") current=\($0.currentVersion ?? "nil") " +
        "upgradeStatus=\($0.upgradeStatus) upgradeType=\($0.upgradeType)}"
    }.joined(separator: ", ")
  }

  fileprivate static func otaError(_ error: Error?) -> String {
    guard let nsError = error as NSError? else { return "error=nil" }
    return "domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription) userInfo=\(nsError.userInfo)"
  }

  /// Keeps a delegate registered for exactly [deviceIds].
  private func watchDevices(_ deviceIds: [String]) {
    let wanted = Set(deviceIds.filter { !$0.isEmpty })
    // Snapshot the keys: unwatchDevice mutates the dictionary being read.
    for id in Array(watched.keys) where !wanted.contains(id) {
      unwatchDevice(id)
    }
    wanted.forEach(watchDevice)
  }

  /// Subscribes to one device's reports.
  ///
  /// This is the SDK's own push channel: with the account logged in and the
  /// home loaded, the SDK keeps the MQTT/LAN link up and calls the delegate
  /// for every DP the device reports. Nothing here polls.
  private func watchDevice(_ deviceId: String) {
    guard !deviceId.isEmpty, watched[deviceId] == nil,
          let device = ThingSmartDevice(deviceId: deviceId) else { return }
    device.delegate = self
    watched[deviceId] = device
  }

  private func unwatchDevice(_ deviceId: String) {
    guard let device = watched.removeValue(forKey: deviceId) else { return }
    device.delegate = nil
  }

  fileprivate func releaseDeviceListeners() {
    watched.values.forEach { $0.delegate = nil }
    watched.removeAll()
    upgrading.values.forEach { $0.delegate = nil }
    upgrading.removeAll()
  }

  /// DP ids arrive as dictionary keys of either type depending on the
  /// transport; Dart reads them as strings.
  fileprivate func dpMap(_ dps: [AnyHashable: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (key, value) in dps { out["\(key)"] = value }
    return out
  }

  fileprivate func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.eventSink?(event) }
  }

  fileprivate func deviceSnapshot(_ device: ThingSmartDevice) -> [String: Any?]? {
    guard let model = device.deviceModel else { return nil }
    return deviceMap(model)
  }

  private func userMap(_ user: ThingSmartUser) -> [String: Any?] {
    return [
      "uid": user.uid,
      "nickname": user.nickname,
      "account": user.userName,
      "avatarUrl": user.headIconUrl,
    ]
  }

  private func deviceMap(_ device: ThingSmartDeviceModel) -> [String: Any?] {
    return [
      "deviceId": device.devId,
      "productId": device.productId,
      "name": device.name,
      "online": device.isOnline,
      "activeTime": device.activeTime,
      "mac": device.uuid,
      // 固件版本用 verSw；Android 侧曾经错取协议版本 pv，两端现在都用同一个字段。
      "firmwareVersion": device.verSw,
      "dps": device.dps,
    ]
  }

  private func fail(_ result: @escaping FlutterResult, _ error: Error?) {
    let nsError = error as NSError?
    sdkError(result, code: nsError.map { String($0.code) } ?? "sdk_error", message: error?.localizedDescription ?? "涂鸦 SDK 调用失败")
  }

  private func sdkError(_ result: @escaping FlutterResult, code: String, message: String) {
    result(FlutterError(code: code, message: message, details: nil))
  }
  #endif
}

/// Everything the planter reports on its own reaches Dart through here.
///
/// `ThingSmartDeviceDelegate` is the iOS counterpart of Android's
/// `IDevListener`; both are fed onto the same event channel in the same shape,
/// so the Dart side has one decoder.
#if canImport(ThingSmartHomeKit)
extension FlowerpotTuyaBridge: ThingSmartDeviceDelegate {
  func device(_ device: ThingSmartDevice, dpsUpdate dps: [AnyHashable: Any]) {
    guard let id = device.deviceModel?.devId else { return }
    let changed = dpMap(dps)
    if !changed.isEmpty { emit(["deviceId": id, "dps": changed]) }
  }

  /// Name, online flag and firmware version live on the model rather than in a
  /// DP, so the whole snapshot goes over.
  func deviceInfoUpdate(_ device: ThingSmartDevice) {
    guard let id = device.deviceModel?.devId, let snapshot = deviceSnapshot(device) else {
      return
    }
    emit(["deviceId": id, "device": snapshot])
  }

  func deviceOnlineUpdate(_ device: ThingSmartDevice) {
    guard let model = device.deviceModel, let id = model.devId else { return }
    emit(["deviceId": id, "online": model.isOnline])
  }

  func deviceRemoved(_ device: ThingSmartDevice) {
    guard let id = device.deviceModel?.devId else { return }
    emit(["deviceId": id, "removed": true])
    DispatchQueue.main.async { [weak self] in self?.unwatchDevice(id) }
  }

  // 固件升级要跑几分钟，方法通道只回答"已发起"，进度和成败走这里，形状和
  // Android 的 emitOta 一致。这几个都是 delegate 的可选方法：SDK 若换了签名
  // 只会静默不回调，不会编译失败，届时版本号仍由 deviceInfoUpdate 兜底刷新。
  func device(_ device: ThingSmartDevice, firmwareUpgradeProgress type: Int, progress: Double) {
    guard let id = device.deviceModel?.devId else { return }
    otaLog(id, "delegate firmwareUpgradeProgress type=\(type) progress=\(progress)")
    emitOta(id, "running", percent: Int((progress * 100).rounded()))
  }

  func deviceFirmwareUpgradeSuccess(_ device: ThingSmartDevice, type: Int) {
    guard let id = device.deviceModel?.devId else { return }
    otaLog(id, "delegate deviceFirmwareUpgradeSuccess type=\(type)")
    emitOta(id, "success")
    // 升级结束，实例可以放了；下次检查会重新建。
    DispatchQueue.main.async { [weak self] in self?.releaseOta(id) }
  }

  func deviceFirmwareUpgradeFailure(_ device: ThingSmartDevice, type: Int) {
    guard let id = device.deviceModel?.devId else { return }
    otaLog(id, "delegate deviceFirmwareUpgradeFailure type=\(type)")
    emitOta(id, "failed", message: "固件升级失败")
    DispatchQueue.main.async { [weak self] in self?.releaseOta(id) }
  }

  private func emitOta(
    _ deviceId: String,
    _ status: String,
    percent: Int? = nil,
    message: String? = nil
  ) {
    var ota: [String: Any] = ["status": status]
    if let percent { ota["percent"] = percent }
    if let message { ota["message"] = message }
    emit(["deviceId": deviceId, "ota": ota])
  }
}
#endif

extension FlowerpotTuyaBridge: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

#if canImport(ThingSmartHomeKit)
extension FlowerpotTuyaBridge: ThingSmartActivatorDelegate {
  func activator(
    _ activator: ThingSmartActivator!,
    didReceiveDevice deviceModel: ThingSmartDeviceModel!,
    error: Error!
  ) {
    guard let callback = pairingResult else { return }
    pairingResult = nil
    activator.stopConfigWiFi()
    activator.delegate = nil
    // 成功时设备已经关掉热点，失败时 Dart 侧也会再调一次 leaveDeviceHotspot；
    // 这里先删一遍，两边都不依赖对方。
    removeHotspotConfiguration()
    if let error {
      fail(callback, error)
    } else if let deviceModel {
      // Tokens are single-use; keeping this one would make the next attempt
      // fail with a stale-token error.
      activatorToken = nil
      activatorTokenAt = nil
      watchDevice(deviceModel.devId ?? "")
      callback(deviceMap(deviceModel))
    } else {
      callback(FlutterError(code: "pair_failed", message: "未发现设备", details: nil))
    }
  }
}
#endif

// MARK: - 蓝牙发现与双模配网

/// 等蓝牙状态的一个调用方。到时和状态更新谁先到算谁，只回一次。
final class BluetoothStateWaiter {
  private var ready: ((CBManagerState) -> Void)?

  init(_ ready: @escaping (CBManagerState) -> Void) {
    self.ready = ready
  }

  func fire(_ state: CBManagerState) {
    guard let callback = ready else { return }
    ready = nil
    callback(state)
  }
}

#if canImport(ThingSmartHomeKit)
/// 系统蓝牙的开关与授权。只读状态、触发授权框，不用它扫描——扫描走涂鸦 SDK，
/// SDK 才认得出涂鸦设备的广播、配网时也只认它自己扫到的设备。
extension FlowerpotTuyaBridge: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let state = central.state
    // unknown / resetting 是过渡态，等下一次更新再回答。
    guard state != .unknown, state != .resetting else { return }
    let waiters = bluetoothStateWaiters
    bluetoothStateWaiters.removeAll()
    waiters.forEach { $0.fire(state) }
  }

  /// 拿到确定的蓝牙状态再回调；[timeout] 秒内没定下来就按当时的状态回。
  ///
  /// 第一次调用会建 CBCentralManager：授权还没问过时，系统此刻弹出蓝牙授权框，
  /// 状态要等用户答完才更新，所以 [ensureBlePermissions] 给的时间长。
  fileprivate func withBluetoothState(
    timeout: TimeInterval,
    _ ready: @escaping (CBManagerState) -> Void
  ) {
    if let central = bluetoothCentral, central.state != .unknown, central.state != .resetting {
      ready(central.state)
      return
    }
    let waiter = BluetoothStateWaiter(ready)
    bluetoothStateWaiters.append(waiter)
    if bluetoothCentral == nil {
      // 不弹「打开蓝牙」的系统提示：蓝牙关着时由页面按 bleProbe 的结果说明。
      bluetoothCentral = CBCentralManager(
        delegate: self,
        queue: nil,
        options: [CBCentralManagerOptionShowPowerAlertKey: false]
      )
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self else { return }
      self.bluetoothStateWaiters.removeAll { $0 === waiter }
      waiter.fire(self.bluetoothCentral?.state ?? .unknown)
    }
  }

  /// 本 App 有没有被允许用蓝牙。iOS 13.1 起是一个独立于开关的授权。
  fileprivate func bluetoothAuthorized(_ state: CBManagerState) -> Bool {
    if state == .unauthorized { return false }
    if #available(iOS 13.1, *) {
      return CBCentralManager.authorization == .allowedAlways
    }
    return true
  }

  /// 弹一次蓝牙授权框并等用户答完。Dart 要求在 bleProbe 之前 await 掉。
  fileprivate func ensureBlePermissions(_ result: @escaping FlutterResult) {
    withBluetoothState(timeout: 60) { [weak self] state in
      guard let self else { return }
      if self.bluetoothAuthorized(state) {
        result(true)
      } else {
        self.sdkError(result, code: "permission_denied", message: "未允许使用蓝牙，请在系统设置中为本应用打开蓝牙权限")
      }
    }
  }

  fileprivate func openAppSettings(_ result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      sdkError(result, code: "open_settings_failed", message: "打不开设置页")
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
  }

  /// 这台手机 / 这个包能不能用蓝牙配网，字段与 Android 的 bleProbe 一致。
  /// iOS 扫蓝牙不需要定位，locationOn / locationPermission 恒为 true。
  fileprivate func bleProbe(_ result: @escaping FlutterResult) {
    let available = bleKitAvailable()
    withBluetoothState(timeout: 3) { [weak self] state in
      guard let self else { return }
      let authorized = self.bluetoothAuthorized(state)
      let supported = state != .unsupported
      let enabled = state == .poweredOn
      let reason: String
      if !available {
        reason = "SDK 蓝牙模块不可用：包里没有 ThingSmartBLEKit"
      } else if !authorized {
        reason = "未允许使用蓝牙，请在系统设置中为本应用打开蓝牙权限"
      } else if !supported {
        reason = "这台手机不支持 BLE"
      } else if !enabled {
        reason = "蓝牙没有打开"
      } else {
        reason = ""
      }
      result([
        "available": available,
        "supported": supported,
        "enabled": enabled,
        "scanPermission": authorized,
        "locationOn": true,
        "locationPermission": true,
        "sdkInt": 0,
        "release": "iOS \(UIDevice.current.systemVersion)",
        "reason": reason,
        "bluetoothState": state.rawValue,
      ])
    }
  }

  /// 按 BLE 扫到的设备结果安全读一个属性：这一版 SDK 没有这个属性时回 nil，不崩。
  fileprivate static func advValue(_ object: NSObject?, _ key: String) -> Any? {
    guard let object, object.responds(to: NSSelectorFromString(key)) else { return nil }
    return object.value(forKey: key)
  }

  fileprivate static func advString(_ object: NSObject?, _ keys: String...) -> String {
    for key in keys {
      if let value = advValue(object, key), !(value is NSNull) {
        let text = "\(value)"
        if !text.isEmpty { return text }
      }
    }
    return ""
  }

  fileprivate static func advNumber(_ object: NSObject?, _ keys: String...) -> NSNumber? {
    for key in keys {
      if let value = advValue(object, key) as? NSNumber { return value }
    }
    return nil
  }

  /// 扫到的一台设备 → Dart `BleDevice.fromMap`。
  ///
  /// 字段按涂鸦 iOS 文档的属性名读（uuid / productId / mac / isActive / bleType），读不到就空着，
  /// 原样 description 放进 raw，真机上一眼能看出 SDK 给了什么。
  /// supportWifiList 恒为 false：iOS 端没接「设备自报 Wi-Fi 列表」，下一页手动输入。
  fileprivate func bleDeviceMap(_ model: NSObject) -> [String: Any] {
    let peripheral = Self.advValue(model, "peripheral") as? NSObject
    let rssi = Self.advNumber(model, "rssi", "RSSI") ?? Self.advNumber(peripheral, "rssi", "RSSI")
    var name = Self.advString(model, "name", "deviceName")
    if name.isEmpty { name = Self.advString(peripheral, "name") }
    return [
      "type": "bleDevice",
      "seq": bleSeq,
      "uuid": Self.advString(model, "uuid"),
      "productId": Self.advString(model, "productId"),
      "mac": Self.advString(model, "mac"),
      "name": name,
      "rssi": rssi?.intValue ?? 0,
      "bound": Self.advNumber(model, "isActive")?.boolValue ?? false,
      "supportWifiList": false,
      "configType": Self.advString(model, "bleType"),
      "flag": 0,
      "raw": model.description,
    ]
  }

  fileprivate func pairingTrace(_ line: String) {
    emit(["type": "pairingLog", "line": line])
  }

  fileprivate func flutterError(_ error: Error?, fallback: String) -> FlutterError {
    let nsError = error as NSError?
    return FlutterError(
      code: nsError.map { String($0.code) } ?? "sdk_error",
      message: error?.localizedDescription ?? fallback,
      details: nil
    )
  }
}

#if canImport(ThingSmartBLEKit)
extension FlowerpotTuyaBridge: ThingSmartBLEManagerDelegate, ThingSmartBLEWifiActivatorDelegate {
  fileprivate func bleKitAvailable() -> Bool { bleManager() != nil }

  // 两个 sharedInstance 在不同 SDK 版本里可能标成可选或非可选，统一收成可选再用。
  fileprivate func bleManager() -> ThingSmartBLEManager? {
    let manager: ThingSmartBLEManager? = ThingSmartBLEManager.sharedInstance()
    return manager
  }

  fileprivate func bleWifiActivator() -> ThingSmartBLEWifiActivator? {
    let activator: ThingSmartBLEWifiActivator? = ThingSmartBLEWifiActivator.sharedInstance()
    return activator
  }

  /// 开一轮扫描，扫到的设备逐台经事件通道推给 Dart（`type = bleDevice`）。
  /// 到时推 `bleScanStopped`；Dart 主动 stopBleScan 的那次不推。
  fileprivate func startBleScan(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let manager = bleManager() else {
      sdkError(result, code: "ble_unavailable", message: "SDK 蓝牙模块不可用")
      return
    }
    stopBleScanning()
    // 新一轮不沿用上一轮扫到的设备（产品口径：按实际搜索展示，不要缓存）。
    bleScanned.removeAll()
    bleSeq = 0
    bleScanRound += 1
    let round = bleScanRound
    let timeoutMs = (args["timeoutMs"] as? NSNumber)?.intValue ?? 60_000
    bleScanning = true
    manager.delegate = self
    // true：开扫前清掉 SDK 上一轮的发现缓存，关机的设备不会再冒出来。
    manager.startListening(true)
    pairingTrace("ble scan: startListening(timeout=\(timeoutMs)ms)")
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) { [weak self] in
      guard let self, self.bleScanning, self.bleScanRound == round else { return }
      self.stopBleScanning()
      self.pairingTrace("ble scan: 到时结束")
      self.emit(["type": "bleScanStopped", "reason": "timeout"])
    }
    result(nil)
  }

  /// 停扫。没在扫时也安全。
  ///
  /// 不清 [bleScanned]，也不让 SDK 清发现缓存（stopListening(false)）：用户点了某一台之后
  /// 页面先停扫再配网，双模配网按 uuid 找的正是这份缓存。
  fileprivate func stopBleScanning() {
    guard bleScanning else { return }
    bleScanning = false
    bleManager()?.stopListening(false)
  }

  /// 设备只有在没被连着时才广播。配网没在跑时停掉双模配网器，把可能留着的蓝牙连接放掉；
  /// 配网进行中不动它，免得把正在下发凭据的那条连接掐断。
  fileprivate func disconnectBleDevice(_ result: @escaping FlutterResult) {
    if blePairingResult == nil {
      bleWifiActivator()?.stopDiscover()
    }
    result(nil)
  }

  /// 按扫到的 uuid + productId 去云端查产品名和图标（搜索页列表上显示用）。
  fileprivate func queryBleProductInfo(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let uuid = args["uuid"] as? String ?? ""
    let productId = args["productId"] as? String ?? ""
    guard let manager = bleManager() else {
      sdkError(result, code: "ble_unavailable", message: "SDK 蓝牙模块不可用")
      return
    }
    manager.queryDeviceInfo(withUUID: uuid, productId: productId, success: { dict in
      let info = (dict as Any) as? [AnyHashable: Any] ?? [:]
      result([
        "name": (info["name"] ?? info["productName"]).map { "\($0)" } ?? "",
        "icon": (info["icon"] ?? info["iconUrl"]).map { "\($0)" } ?? "",
        "productId": productId,
        "raw": "\(info)",
      ])
    }, failure: { [weak self] error in self?.fail(result, error) })
  }

  /// 双模配网：把路由器 SSID / 密码经蓝牙交给设备，设备自己连路由器并注册到云端。
  ///
  /// 涂鸦 iOS 的这条接口按家庭 id 自己取令牌，不用 prepareActivatorToken 预取的那个；
  /// 手机全程连着路由器，不存在 AP 那种「连上热点就没外网」的问题。
  fileprivate func pairBleDevice(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let uuid = args["uuid"] as? String ?? ""
    guard !uuid.isEmpty else {
      sdkError(result, code: "ble_uuid_required", message: "双模配网必须给 BLE 扫到的 uuid")
      return
    }
    guard let model = bleScanned[uuid] else {
      sdkError(result, code: "ble_device_missing", message: "uuid=\(uuid) 不在本轮蓝牙扫描结果里，请重新扫描")
      return
    }
    let productId = Self.advString(model, "productId")
    let ssid = args["ssid"] as? String ?? ""
    let password = args["password"] as? String ?? ""
    // 上一次还没回话就又来一次：先了结旧的，否则旧那次的 Future 永远挂着。
    finishBlePairing(with: FlutterError(code: "pair_cancelled", message: "被新的配网请求取代", details: nil))
    withHome(result) { [weak self] home in
      guard let self else { return }
      guard let activator = self.bleWifiActivator() else {
        self.sdkError(result, code: "sdk_unavailable", message: "无法获取双模配网实例")
        return
      }
      self.blePairingResult = result
      activator.bleWifiDelegate = self
      let homeId = home.homeModel.homeId
      self.pairingTrace("ble pair: startConfigBLEWifiDevice(uuid=\(uuid), pid=\(productId), home=\(homeId))")
      // 超时与 AP 那条一致取 120 秒（Dart 侧 pairBleDevice 默认同样是 120 秒）。
      activator.startConfigBLEWifiDevice(
        withUUID: uuid,
        homeId: homeId,
        productId: productId,
        ssid: ssid,
        password: password,
        timeout: 120,
        success: { [weak self] in self?.pairingTrace("ble pair: 凭据已经蓝牙下发，等设备连云") },
        failure: { [weak self] error in
          guard let self else { return }
          self.pairingTrace("ble pair: 下发失败 \(FlowerpotTuyaBridge.otaError(error))")
          self.finishBlePairing(with: self.flutterError(error, fallback: "蓝牙配网失败"))
        }
      )
      // 兜底：SDK 的结果回调到 130 秒还没来，就按超时了结。
      let watchdog = DispatchWorkItem { [weak self] in
        guard let self, self.blePairingResult != nil else { return }
        self.pairingTrace("ble pair: 130 秒未收到 SDK 结果，按超时结束")
        self.finishBlePairing(with: FlutterError(code: "pair_timeout", message: "蓝牙配网超时，请让设备靠近手机并重启设备后重试", details: nil))
      }
      self.blePairingWatchdog = watchdog
      DispatchQueue.main.asyncAfter(deadline: .now() + 130, execute: watchdog)
    }
  }

  /// 了结进行中的双模配网：停掉配网器，把 [value] 回给等着的那次 pairBleDevice。
  fileprivate func finishBlePairing(with value: Any?) {
    blePairingWatchdog?.cancel()
    blePairingWatchdog = nil
    guard let callback = blePairingResult else { return }
    blePairingResult = nil
    let activator = bleWifiActivator()
    activator?.stopDiscover()
    activator?.bleWifiDelegate = nil
    callback(value)
  }

  // MARK: ThingSmartBLEManagerDelegate

  @objc(didDiscoveryDeviceWithDeviceInfo:)
  func didDiscoveryDevice(withDeviceInfo deviceInfo: ThingBLEAdvModel?) {
    guard bleScanning, let model = deviceInfo else { return }
    bleSeq += 1
    let map = bleDeviceMap(model)
    if let uuid = map["uuid"] as? String, !uuid.isEmpty {
      bleScanned[uuid] = model
    }
    emit(map)
  }

  // MARK: ThingSmartBLEWifiActivatorDelegate

  @objc(bleWifiActivator:didReceiveBLEWifiConfigDevice:error:)
  func bleWifiActivator(
    _ activator: ThingSmartBLEWifiActivator?,
    didReceiveBLEWifiConfigDevice deviceModel: ThingSmartDeviceModel?,
    error: Error?
  ) {
    guard blePairingResult != nil else { return }
    if let error {
      pairingTrace("ble pair: 失败 \(FlowerpotTuyaBridge.otaError(error))")
      finishBlePairing(with: flutterError(error, fallback: "蓝牙配网失败"))
    } else if let deviceModel {
      pairingTrace("ble pair: 成功 devId=\(deviceModel.devId ?? "")")
      // 和 AP 那条一样作废预取的令牌，下次配网重新取。
      activatorToken = nil
      activatorTokenAt = nil
      watchDevice(deviceModel.devId ?? "")
      finishBlePairing(with: deviceMap(deviceModel))
    } else {
      finishBlePairing(with: FlutterError(code: "pair_failed", message: "未发现设备", details: nil))
    }
  }

  /// 设备不在配网状态（例如已静置退出）。
  @objc(bleWifiActivator:notConfigStateWithError:)
  func bleWifiActivator(_ activator: ThingSmartBLEWifiActivator?, notConfigStateWithError error: Error?) {
    guard blePairingResult != nil else { return }
    pairingTrace("ble pair: 设备不在配网状态 \(FlowerpotTuyaBridge.otaError(error))")
    finishBlePairing(with: FlutterError(
      code: "ble_not_config_state",
      message: "设备不在配网状态，请给设备断电重启后重试",
      details: nil
    ))
  }
}
#else
/// 包里没有 ThingSmartBLEKit：蓝牙方法如实报不可用，页面据 bleProbe 的 reason 说明原因。
extension FlowerpotTuyaBridge {
  fileprivate func bleKitAvailable() -> Bool { false }

  fileprivate func startBleScan(_ args: [String: Any], _ result: @escaping FlutterResult) {
    sdkError(result, code: "ble_unavailable", message: "SDK 蓝牙模块不可用：包里没有 ThingSmartBLEKit")
  }

  fileprivate func stopBleScanning() {}

  fileprivate func disconnectBleDevice(_ result: @escaping FlutterResult) { result(nil) }

  fileprivate func queryBleProductInfo(_ args: [String: Any], _ result: @escaping FlutterResult) {
    sdkError(result, code: "ble_unavailable", message: "SDK 蓝牙模块不可用：包里没有 ThingSmartBLEKit")
  }

  fileprivate func pairBleDevice(_ args: [String: Any], _ result: @escaping FlutterResult) {
    sdkError(result, code: "ble_unavailable", message: "SDK 蓝牙模块不可用：包里没有 ThingSmartBLEKit")
  }

  fileprivate func finishBlePairing(with value: Any?) {}
}
#endif
#endif
