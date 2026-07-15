import Flutter
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
      name: "com.flowerpot.smart/tuya",
      binaryMessenger: registrar.messenger()
    )
    let bridge = FlowerpotTuyaBridge()
    tuyaBridge = bridge
    channel.setMethodCallHandler(bridge.handle)
  }
}

final class FlowerpotTuyaBridge: NSObject {
  #if canImport(ThingSmartHomeKit)
  private let homeManager = ThingSmartHomeManager()
  private var currentHome: ThingSmartHome?
  private var pairingResult: FlutterResult?
  #endif

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(ThingSmartHomeKit)
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "initialize": initialize(result)
    case "currentUser": currentUser(result)
    case "sendVerificationCode": sendCode(args, result)
    case "login": login(args, result)
    case "register": register(args, result)
    case "resetPassword": resetPassword(args, result)
    case "updateNickname": updateNickname(args, result)
    case "logout": logout(result)
    case "cancelAccount": cancelAccount(result)
    case "getDevices": withHome(result) { [weak self] home in self?.loadDevices(home, result) }
    case "pairWifiDevice": pairWifi(args, result)
    case "publishDps": publishDps(args, result)
    case "renameDevice": renameDevice(args, result)
    case "removeDevice": removeDevice(args, reset: false, result)
    case "resetFactory": removeDevice(args, reset: true, result)
    case "getStatistics": sdkError(result, code: "service_configuration_required", message: "请在涂鸦平台开通设备数据统计服务")
    case "createShareLink": sdkError(result, code: "service_configuration_required", message: "请在涂鸦平台配置设备分享渠道码与通用链接")
    case "checkFirmware", "startFirmwareUpgrade": sdkError(result, code: "ota_configuration_required", message: "请先为产品 PID 配置固件 OTA 通道")
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
    ThingSmartUser.sharedInstance()?.loginOut({ result(nil) }, failure: { error in self.fail(result, error) })
  }

  private func cancelAccount(_ result: @escaping FlutterResult) {
    ThingSmartUser.sharedInstance()?.cancelAccount({ result(nil) }, failure: { error in self.fail(result, error) })
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
    home.getDetailWithSuccess({ _ in
      result(home.deviceList.map(self.deviceMap))
    }, failure: { error in self.fail(result, error) })
  }

  private func pairWifi(_ args: [String: Any], _ result: @escaping FlutterResult) {
    withHome(result) { [weak self] home in
      guard let self, let activator = ThingSmartActivator.sharedInstance() else { return }
      self.pairingResult = result
      activator.delegate = self
      activator.getTokenWithHomeId(home.homeModel.homeId, success: { token in
        let mode = (args["mode"] as? String) == "ez" ? ThingActivatorModeEZ : ThingActivatorModeAP
        activator.startConfigWiFi(
          mode,
          ssid: args["ssid"] as? String ?? "",
          password: args["password"] as? String ?? "",
          token: token,
          timeout: 120
        )
      }, failure: { error in self.fail(result, error) })
    }
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
    if let error {
      fail(callback, error)
    } else if let deviceModel {
      callback(deviceMap(deviceModel))
    } else {
      callback(FlutterError(code: "pair_failed", message: "未发现设备", details: nil))
    }
  }
}
#endif
