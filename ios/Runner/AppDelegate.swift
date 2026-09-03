import Flutter
import NetworkExtension
import UIKit

#if canImport(ThingSmartHomeKit)
import ThingSmartHomeKit
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
    case "scanWifi": scanWifi(result)
    case "prepareActivatorToken": prepareActivatorToken(result)
    // ThingActivatorMode 是 ObjC 的 NS_ENUM，运行时拿不到常量名，没法像 Android
    // 那样让 SDK 自己报一遍。要确认 iOS 支不支持双模只能查平台文档。
    case "listActivatorModes": sdkError(result, code: "unsupported_on_ios", message: "iOS 端无法枚举配网模式常量，请查涂鸦 iOS 文档")
    case "joinDeviceHotspot": joinDeviceHotspot(args, result)
    case "leaveDeviceHotspot": leaveDeviceHotspot(result)
    case "cancelPairing": cancelPairing(result)
    case "pairWifiDevice": pairWifi(args, result)
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
    releaseDeviceListeners()
    currentHome = nil
    activatorToken = nil
    activatorTokenAt = nil
  }

  private func withHome(_ result: @escaping FlutterResult, ready: @escaping (ThingSmartHome) -> Void) {
    if let currentHome {
      ready(currentHome)
      return
    }
    homeManager.getHomeList(success: { [weak self] homes in
      guard let self else { return }
      if let model = homes?.first, let home = ThingSmartHome(homeId: model.homeId) {
        self.currentHome = home
        ready(home)
      } else {
        self.homeManager.addHome(
          withName: "我的花园",
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
    // EZ 默认，AP 兜底；两者都走同一条 startConfigWiFi。
    let mode = (args["mode"] as? String) == "ez" ? ThingActivatorModeEZ : ThingActivatorModeAP
    activator.startConfigWiFi(
      mode,
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
    device.getFirmwareUpgradeInfo({ [device] models in
      // One model per upgradable component; upgradeStatus 1 is "an update is
      // waiting". Anything else means there is nothing to offer.
      let pending = models?.first { $0.upgradeStatus == 1 }
      result(pending?.version)
    }, failure: { [weak self, device] error in self?.fail(result, error) })
  }

  private func startFirmwareUpgrade(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["deviceId"] as? String, let device = otaDevice(id) else {
      sdkError(result, code: "bad_args", message: "设备参数错误")
      return
    }
    // The upgrade is started per component, and the component type only comes
    // from the upgrade info, so it is read first.
    device.getFirmwareUpgradeInfo({ [weak self] models in
      guard let self else { return }
      guard let pending = models?.first(where: { $0.upgradeStatus == 1 }) else {
        self.releaseOta(id)
        self.sdkError(result, code: "firmware_up_to_date", message: "当前固件已是最新版本")
        return
      }
      device.upgradeFirmware(
        pending.type,
        // 只回答"已发起"：下载和烧录之后几分钟的进度、成败都从 delegate 走
        // 事件通道，和 Android 一致。
        success: { result(nil) },
        failure: { error in
          self.releaseOta(id)
          self.fail(result, error)
        }
      )
    }, failure: { [weak self] error in
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
    device.delegate = nil
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
    emitOta(id, "running", percent: Int((progress * 100).rounded()))
  }

  func deviceFirmwareUpgradeSuccess(_ device: ThingSmartDevice, type: Int) {
    guard let id = device.deviceModel?.devId else { return }
    emitOta(id, "success")
    // 升级结束，实例可以放了；下次检查会重新建。
    DispatchQueue.main.async { [weak self] in self?.releaseOta(id) }
  }

  func deviceFirmwareUpgradeFailure(_ device: ThingSmartDevice, type: Int) {
    guard let id = device.deviceModel?.devId else { return }
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
