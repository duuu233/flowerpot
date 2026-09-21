import 'dart:async';

import 'package:flutter/services.dart';

import 'tuya_config.dart';
import 'tuya_history_codec.dart';
import 'tuya_memorial_codec.dart';
import 'tuya_models.dart';
import 'tuya_raw.dart';

/// 显式国家码优先；缺省时按区域回落到国内 86 / 海外 1。
String _resolveCountryCode(LoginRegion region, String? override) {
  final explicit = override?.trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  return region == LoginRegion.domestic ? '86' : '1';
}

abstract class TuyaRepository {
  factory TuyaRepository.create() => MethodChannelTuyaRepository();

  Future<bool> initialize();
  Future<AppUser?> restoreSession();
  Future<void> sendVerificationCode({
    required String account,
    required String countryCode,
    required int type,
  });
  Future<AppUser> login({
    required String account,
    required String credential,
    required LoginRegion region,
    required bool verificationCode,
  });

  /// 涂鸦自有账号体系登录：用 APP 后端下发的内部编号 [uid] 与配套密码登录，
  /// 涂鸦侧没有该账号时自动注册。
  ///
  /// 国内账号走的是这条路而不是 [login]：后端返回的 `userNo`（形如
  /// `GA7593223`）不是手机号，拿它调手机号登录会被涂鸦回 `USER_PASSWD_WRONG`，
  /// 文案上看起来却像密码错，很容易把排查方向带偏。
  Future<AppUser> loginWithUid({
    required String uid,
    required String password,
    required String countryCode,
  });

  Future<AppUser> register({
    required String account,
    required String password,
    required String code,
    required LoginRegion region,
  });
  Future<void> resetPassword({
    required String account,
    required String newPassword,
    required String code,
    required LoginRegion region,
  });
  Future<void> updateNickname(String nickname);
  Future<void> logout();
  Future<void> deleteAccount();
  Future<List<SmartPlanterDevice>> getDevices();
  Future<SmartPlanterDevice> pair(PairingRequest request);

  /// Fetches and caches a provisioning token ahead of [pair].
  ///
  /// Only AP mode needs this called explicitly, and it has to happen while the
  /// phone is still on a network with internet access: joining the device's
  /// hotspot cuts off the cloud, and [pair] would otherwise try to fetch the
  /// token from there and fail. The token stays in the native layer.
  Future<void> prepareActivatorToken();

  /// 由 App 直接连上设备热点，省掉「去系统设置连 Wi-Fi」那一步。
  ///
  /// 给了 [ssid] 就精确连它；只给 [prefix] 时由系统列出匹配的热点让用户挑。
  /// 返回是否连上并把进程流量绑了过去。Android 9 及以下不支持，抛
  /// `hotspot_join_unsupported`，调用方据此回落到手动引导。
  Future<bool> joinDeviceHotspot({String? ssid, String? prefix});

  /// 释放上面那条连接，让手机回到原来的网络。
  ///
  /// 配网失败后必须调：热点连接和进程网络绑定都是原生层的状态，不释放的话
  /// 进程会一直绑在一个没有互联网的网络上，之后所有云端调用都失败。没有连接
  /// 在跑时调用也安全，什么都不做。
  Future<void> leaveDeviceHotspot();

  /// 中止进行中的配网：停掉 activator，释放设备热点连接与进程网络绑定。
  ///
  /// 进行中的 [pair] 会以 `pair_cancelled` 失败返回，而不是等满超时。没有配网
  /// 在跑时调用也安全。用户中途退出配网页、或 Dart 侧等待超时时调用。
  Future<void> cancelPairing();

  /// 当前使用的涂鸦家庭 id。设备列表按家庭查，家庭对不上就会是空的。
  Future<String> currentHomeId();

  /// 这几台设备此刻的在线标志，**读 SDK 本地缓存，不发网络请求**。
  ///
  /// 在线状态由涂鸦 SDK 的 MQTT 心跳维护：设备掉线 → 云端判定 → 推给 SDK →
  /// SDK 更新 `DeviceBean` 并回调 `onStatusChanged`。**回调那一路会漏**——App 切到
  /// 后台、MQTT 断开重连期间发生的变化不会补发，于是页面就停在上一次的状态
  /// （2026-09-12 产品反馈「设备关机了，App 还显示在线」）。
  ///
  /// bean 本身是准的，所以前台按秒级把它读回来兜底。查不到的设备不出现在返回值里。
  Future<Map<String, bool>> deviceOnlineStates(List<String> deviceIds);

  /// 固定这次会话使用的家庭 id。
  ///
  /// 家庭是涂鸦账号下的东西，和设备、和 APP 后端都没有关系：只要账号没变，就该
  /// 一直用同一个家庭，而不是每次登录重新从家庭列表里挑。App 把第一次解析到的
  /// 家庭按账号记在本地，之后每次会话开始就用这个方法钉给原生。
  Future<void> useHome(String homeId);

  /// 本账号的家庭名标记（`YS-<userNo>`）。
  ///
  /// 家庭 id 由涂鸦分配、App 造不出来，但**家庭名**是我们说了算的：建家时用这个
  /// 名字，之后从家庭列表里认领时优先认名字对上的那个。这样"哪个家庭属于这个
  /// 账号"不再依赖列表顺序，也不需要后端加字段。
  Future<void> useHomeTag(String tag);

  /// Nearby access points, used before provisioning to check that the phone is
  /// on 2.4 GHz and — in AP mode — that the device hotspot is up.
  /// 读一次附近网络。
  ///
  /// [refresh] = true 时**主动发起一次系统扫描**再等结果——这条路受 Android 的
  /// 配额限制（前台每 2 分钟 4 次）。false 时只读系统的扫描缓存，**不受配额限制、
  /// 也不必等**：系统自己（连接管理、其它应用、设置页）也在扫，缓存会被它们刷新。
  /// 搜索页据此「30 秒一次真扫 + 2 秒一次读缓存」，比只靠真扫快得多。
  Future<WifiScan> scanWifi({bool refresh = true});


  Future<void> publishDps(String deviceId, Map<int, Object> dps);
  Future<void> renameDevice(String deviceId, String name);
  Future<void> removeDevice(String deviceId, {required bool resetFactory});

  /// 一条曲线的点。
  ///
  /// [date] 只对日视图有意义：2026-09-17 起日包一次带 7 天，报表按用户选中的那天
  /// 取。不传就是最新那天（状态页那条曲线要的就是它）。
  Future<List<double>> getHistory(
    String deviceId,
    SensorMetric metric,
    ReportRange range, {
    DateTime? date,
  });

  /// 历史 DP 的**到货情况**，给联调日志框用。
  ///
  /// 报表和状态页的曲线只有一个数据源：设备自己上报的 131–139 这九条 raw DP
  /// （云端统计服务要付费订阅，这个账号没有）。所以"没有历史记录"只可能是
  /// ①设备压根没报这条 DP ②报了但解不出来。这个方法把每条的原始长度和解出的
  /// 点数都吐出来，一眼分得清是哪一种。
  ///
  /// 返回**按指标分组**的一句话，例如
  /// `waterLevel → 日 DP131 hex 99字节/96点 · 周 DP132 无 · 月 DP133 无`。
  Future<Map<String, String>> historyDiagnostics(String deviceId);

  /// 设备快照里这几条 DP 的**原始上报值**，给状态页进页面时的联调日志用。
  ///
  /// 和 [historyDiagnostics] 同一个出发点：页面上看到的数是解析过、可能还兜过底的
  /// （没上报时水位是 0、状态按 App 阈值推），只看页面分不清「设备报的就是这个」
  /// 还是「设备根本没报」。这里原样返回快照里的值：
  /// - 返回 null：本次会话还没拉到这台设备的快照；
  /// - 某个标识符对应 null：设备没报过这条 DP。
  Future<Map<String, Object?>?> reportedDps(
    String deviceId,
    List<String> identifiers,
  );
  /// 涂鸦**消息中心**里某台设备的消息（排查用，2026-09-18 起；2026-09-20 改成按设备取）。
  ///
  /// [deviceId] 就是涂鸦的 `msgSrcId`，**必填**；[msgType] 是消息类型枚举名，
  /// 只有三个取值：`MSG_REPORT`（设备 / 告警类上报，默认）、`MSG_FAMILY`、`MSG_NOTIFY`。
  ///
  /// ⚠️ **必须按设备取**（产品口径 2026-09-20）：安卓走
  /// `IThingMessage#getMessageListByMsgSrcId(offset, limit, MessageType, msgSrcId, callback)`；
  /// 标准的 `getMessageList` 是**聚合**结果，按它分页拿不到某台设备的全量消息，
  /// 之前就是拿它调的，打出来的东西明显不对。原生侧因此**不会**退回聚合接口。
  ///
  /// ⚠️ **iOS 不是同名方法**：那边是 `ThingSmartMessage` 的
  /// `fetchEncryptMessageDetailListWithListRequestModel:success:failure:`（带请求模型），
  /// 本轮 iOS 桥接未接——调用会走下面的 MissingPluginException 分支如实返回。
  ///
  /// 原生把每条消息 bean 的所有无参 getter 原样 dump 上来，页面上的调试板直接打印。
  /// **不做字段映射**：一映射就把要查的东西盖住了。`MessageBean` 上确实有类型字段
  /// （`msgType` / `msgTypeContent`，另有 `msgCode` / `alarmType` / `extendParams`），
  /// 后台配的「推送等级」落在哪个字段要真机跑一次才知道。
  ///
  /// 返回结构：`{ok, instance?, method?, msgType?, msgSrcId?, count?, totalCount?,
  /// items?: List<Map>, diagnostic: List<String>, code?, message?}`。
  /// **永远不抛错**——查不到也要把「试过什么、看到什么」带回去。
  Future<Map<String, Object?>> deviceMessages({
    required String deviceId,
    String msgType,
    int offset,
    int limit,
  });

  /// 设备**操作日志（DP 上报历史）**（排查用，2026-09-20）。
  ///
  /// 和消息中心是两个入口：消息中心给的是推送消息，这条才是「日志」——
  /// 安卓 `ThingHomeSdk.getRequestInstance().queryDeviceOperateLogs(...)`
  /// （解包核对在 `IThingSmartRequest` 上，回调泛型是 `String`，也就是原样一段 JSON）；
  /// iOS 对应 `ThingSmartDevice#queryDeviceOperateLogWithDpIds:offset:limit:startTime:endTime:isASC:`。
  ///
  /// ⚠️ 七个参数的顺序官方没给，原生按「设备 ID、dpIds、offset、limit、开始、结束、排序」传，
  /// **返回的 JSON 原样上来**，由页面打印——对不对看真机那一趟的报文。
  /// [dpIds] 用逗号分隔，空串表示不限。
  ///
  /// 返回结构：`{ok, instance?, method?, raw?: String, diagnostic: List<String>, code?, message?}`。
  Future<Map<String, Object?>> deviceOperateLogs({
    required String deviceId,
    String dpIds,
    int offset,
    int limit,
    String startTime,
    String endTime,
    String sort,
  });

  /// 消息中心**按时间窗**取一页（诊断用，2026-09-21）。
  ///
  /// 按设备取（[deviceMessages]）和按类型取都**没有时间参数**——整个 `IThingMessage` 上带时间的
  /// 只有 `getMessageList(int offset, int limit, long startTime, long endTime, cb)` 这一条，
  /// 而它是**聚合**口径（不分设备、不分类型）。所以这条只当诊断：后台在某个时间段看得到消息时，
  /// 用它回答「那一段里 App 这边能看见什么」。取数照旧走按设备那条。
  ///
  /// [startTime] / [endTime] 传**毫秒**（Dart 这边统一毫秒）；原生换算后**先按秒调**
  /// （2026-09-21 真机实测 SDK 这条的单位是秒），回空再按毫秒兜底，实际被接受的单位写在 `unit` 里。给了 [deviceId] 时返回里还会有 `matchedForDevice`
  /// （这一页里有几条是它的）。
  Future<Map<String, Object?>> messagesByTime({
    required int startTime,
    required int endTime,
    String deviceId,
    int offset,
    int limit,
  });

  Future<String> createShareLink(String deviceId);
  Future<FirmwareUpdate?> checkFirmware(String deviceId);
  Future<void> startFirmwareUpgrade(String deviceId);
  Future<void> uploadAnimation(String deviceId, AnimationAsset asset);

  /// Changes the devices push on their own: DP reports, online state and
  /// unbinds that happened elsewhere.
  ///
  /// A broadcast stream — several screens may listen at once — that stays
  /// silent rather than failing on a platform whose bridge does not push yet.
  Stream<DeviceUpdate> get deviceUpdates;

  /// 固件升级进度。和 [deviceUpdates] 走同一条事件通道，同样在没有推送能力的
  /// 平台上保持静默而不是抛错。
  Stream<OtaProgress> get otaUpdates;

  /// 配网过程中的**原生日志行**，原样转上来。
  ///
  /// 产品不看 logcat（「你把日志直接打印到页面上，我截图给你」），所以这些行要能画到
  /// 界面上。内容是原生 `trace()` 打的那几行：`ap query: begin` / `activator=…` /
  /// `builder ok` / `wifi before` / `handed to SDK…` / `success|error … wifi now` /
  /// `pairing step: …`。
  Stream<String> get pairingLogs;

  /// BLE 发现是否可用：包里有没有蓝牙模块、手机有没有 BLE、蓝牙开没开。
  ///
  /// 调 [startBleScan] 之前先问一次——不可用时页面要**直说是哪一种**，而不是默默
  /// 扫不出来让用户以为设备坏了。
  Future<BleAvailability> bleProbe();

  /// 开一轮 BLE 扫描。扫到的设备**逐台**从 [bleDevices] 推上来，不等扫完。
  ///
  /// 这条路的意义是绕开 Android 的 Wi-Fi 扫描配额（前台每 2 分钟 4 次 `startScan`）
  /// ——「搜索不及时」的根就在那里。双模设备一上电就在广播 BLE，通常一两秒就能扫到。
  Future<void> startBleScan({Duration timeout});

  /// 停掉 BLE 扫描。没在扫时调用也安全。
  ///
  /// **每条离开搜索页的路径都要调**：扫描回调握着 Activity，而且在真的耗电。
  Future<void> stopBleScan();

  /// 双模第②步：问设备要**它自己扫到的** Wi-Fi 列表。
  ///
  /// 原生走 `IMultiModeActivator.queryDeviceConfigState(MultiModeQueryBuilder, …)`——
  /// builder 直接吃 BLE 扫到的那个 `ScanDeviceBean`，SDK 据此建立**本地蓝牙连接**再问
  /// 设备要列表，**不走系统 Wi-Fi scan**，因此与那条 4 次/2 分钟的配额彻底无关。
  ///
  /// [uuid] 来自 [BleDevice.uuid]，原生按它取回自己缓存的 `ScanDeviceBean`。
  /// ⚠️ **先看 [BleDevice.supportWifiList]**：老固件（TuyaOS < 3.6.1）不认这条命令，
  /// 调下去只会让用户干等一次超时。
  Future<List<DeviceWifiNetwork>> queryDeviceWifiList(
    String uuid, {
    Duration timeout,
  });

  /// 双模第③步：**把路由器凭据经蓝牙交给设备**，全程不碰设备的 Wi-Fi 热点。
  ///
  /// 原生走 `IMultiModeActivator.startActivator(MultiModeActivatorBean, …)`。相对 AP
  /// 那条的收益：不用 `WifiNetworkSpecifier` ⇒ **没有系统入网授权框**；不用把手机切到
  /// 一个没有外网的热点上 ⇒ 不用绑进程网络、不用事后还原。
  ///
  /// 令牌照旧要在**还连着路由器**时取好（[prepareActivatorToken]）：它走云端。
  Future<SmartPlanterDevice> pairBleDevice({
    required String uuid,
    required String ssid,
    required String password,
    Duration timeout,
  });

  /// BLE 扫描逐台推上来的设备。同一台会重复出现（信号强度在变），去重交给调用方。
  Stream<BleDevice> get bleDevices;

  /// **当前这一轮** BLE 扫描结束了（到时，或 SDK 自己停了），值是原生给的原因。
  ///
  /// 调用方主动 [stopBleScan] 的那一次不报——那是调用方自己知道的事。重开一轮时，
  /// 上一轮迟到的结束也不报，免得把正在跑的新一轮标成已结束。
  ///
  /// ⚠️ 2026-09-14 之前原生一直在发，Dart 从没接：扫描到时之后状态里仍然记着"在扫"，
  /// 「重新扫描」因此成了空操作。
  Stream<String> get bleScanStops;

  /// **主动弹一次 BLE 所需权限的授权框**，用户答完才返回。
  ///
  /// ⚠️ 必须在 [bleProbe] **之前** await 掉。否则会踩 2026-09-11 那个坑：探测抢在授权框
  /// 被回答之前跑完，`checkSelfPermission` 当然报"未授予"，于是既不扫描、也没人再探一次，
  /// 页面上那句「缺少定位权限」就一直挂着——而用户去系统设置一看，权限明明是给了的
  /// （第二次进 App 就正常，正是这个原因）。
  ///
  /// 权限被拒时抛 `permission_denied`；被点成「拒绝且不再询问」之后系统不再弹框，
  /// 只能靠 [openAppSettings] 把用户送去设置页。
  Future<void> ensureBlePermissions();

  /// 打开本应用的系统设置页（权限被永久拒绝后唯一的出路）。
  Future<void> openAppSettings();

  /// 主动断开与设备的 BLE 连接；[uuid] 为空表示**全断**。
  ///
  /// ⚠️ **这一步直接决定设备还能不能被再次扫到。** BLE 外设**在连接状态下会停止广播**，
  /// 配网中途失败又没断干净的话，设备就一直挂在那条连接上、不再发广播——下一轮扫描
  /// 什么都扫不到（2026-09-11 真机「之前搜得到、配网失败之后就搜不到了」）。
  Future<void> disconnectBleDevice({String uuid});

  /// 按 BLE 扫到的标识去云端查**这台是什么产品**（名称、图标）。
  ///
  /// 原生走 `IThingDeviceActivator.getActivatorDeviceInfo(productId, uuid, mac, …)`。
  /// ⚠️ **云端往返**：调用方必须自己去重并限量，不过滤扫描时附近可能几十台设备。
  Future<BleProductInfo> queryDeviceProductInfo({
    required String productId,
    required String uuid,
    required String mac,
  });
}

class MethodChannelTuyaRepository implements TuyaRepository {
  MethodChannelTuyaRepository({MethodChannel? channel, EventChannel? events})
    : _channel = channel ?? const MethodChannel(TuyaConfig.channelName),
      _events = events ?? const EventChannel(TuyaConfig.eventChannelName);

  final MethodChannel _channel;
  final EventChannel _events;

  /// Last raw device map per device id, as the native side sent it.
  ///
  /// A DP report carries only the points that changed, so it has to be merged
  /// into something; this is that something. Filled by every [_device] decode,
  /// which covers the device list, pairing and the merges themselves.
  final Map<String, Map<Object?, Object?>> _snapshots =
      <String, Map<Object?, Object?>>{};

  /// 原始事件流，只订阅一次后分给下面两个消费者。
  ///
  /// A platform that does not implement the event channel delivers one
  /// MissingPluginException and nothing else. Live updates stay off there
  /// instead of taking every listener down with them.
  late final Stream<Object?> _rawEvents = _events
      .receiveBroadcastStream()
      .handleError((Object _) {});

  @override
  late final Stream<DeviceUpdate> deviceUpdates = _rawEvents
      .map(_deviceUpdate)
      .where((update) => update != null)
      .cast<DeviceUpdate>();

  @override
  late final Stream<OtaProgress> otaUpdates = _rawEvents
      .map(_otaUpdate)
      .where((update) => update != null)
      .cast<OtaProgress>();

  @override
  late final Stream<String> pairingLogs = _rawEvents
      .map((event) => _stringField(event, 'pairingLog', 'line'))
      .where((line) => line != null && line.isNotEmpty)
      .cast<String>();

  @override
  late final Stream<BleDevice> bleDevices = _rawEvents
      .map(_bleDevice)
      .where((device) => device != null)
      .cast<BleDevice>();

  @override
  late final Stream<String> bleScanStops = _rawEvents
      .where(
        (event) =>
            event is Map && '${event['type'] ?? ''}' == 'bleScanStopped',
      )
      // 不走 `_stringField`：它在字段缺失时返回 null，而原因缺失不该让这条结束事件丢掉。
      .map((event) => '${(event as Map)['reason'] ?? ''}');

  @override
  Future<void> ensureBlePermissions() => _invoke<void>('ensureBlePermissions');

  @override
  Future<void> openAppSettings() => _invoke<void>('openAppSettings');

  @override
  Future<void> disconnectBleDevice({String uuid = ''}) =>
      _invoke<void>('disconnectBleDevice', <String, Object?>{'uuid': uuid});

  @override
  Future<BleProductInfo> queryDeviceProductInfo({
    required String productId,
    required String uuid,
    required String mac,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>(
      'queryDeviceProductInfo',
      <String, Object?>{'productId': productId, 'uuid': uuid, 'mac': mac},
    );
    return raw == null
        ? const BleProductInfo()
        : BleProductInfo.fromMap(raw);
  }

  /// 解析原生的 BLE 事件：`{type: 'bleDevice', uuid, name, rssi, …}`。
  ///
  /// ⚠️ **一条都不丢。**
  ///
  /// 改之前这里写着「没有 uuid 的一律丢掉」——理由是配网要 uuid、画出来也点不动。
  /// 但那是**静默过滤**：广播里没带 uuid 的设备直接消失，页面上显示的是「一台都没扫到」，
  /// 于是「我们把它扔了」被当成了「设备没在广播」，排查方向正好反（2026-09-11 真机
  /// 一直搜不到设备，这是原因之一）。
  ///
  /// 现在全部留下、全部画出来；能不能点由页面按 uuid 是否为空自己决定。
  BleDevice? _bleDevice(Object? event) {
    if (event is! Map) return null;
    if ('${event['type'] ?? ''}' != 'bleDevice') return null;
    return BleDevice.fromMap(event.cast<Object?, Object?>());
  }

  /// 从原生事件里取一个字符串字段：`{type: <type>, <field>: '…'}`。
  String? _stringField(Object? event, String type, String field) {
    if (event is! Map) return null;
    if ('${event['type'] ?? ''}' != type) return null;
    return event[field]?.toString();
  }


  /// 解析原生的 OTA 事件：`{deviceId, ota: {status, percent?, message?, stage?}}`。
  OtaProgress? _otaUpdate(Object? event) {
    if (event is! Map) return null;
    final ota = event['ota'];
    if (ota is! Map) return null;
    final deviceId = '${event['deviceId'] ?? ''}';
    if (deviceId.isEmpty) return null;
    final status = switch ('${ota['status'] ?? ''}') {
      'success' => OtaStatus.success,
      'failed' => OtaStatus.failed,
      'running' => OtaStatus.running,
      _ => null,
    };
    if (status == null) return null;
    final percent = ota['percent'];
    return OtaProgress(
      deviceId: deviceId,
      status: status,
      percent: percent is num ? percent.toInt().clamp(0, 100) : null,
      message: ota['message']?.toString(),
      stage: OtaStage.fromTuya(ota['stage']),
    );
  }

  /// Turns one native event into an update, or null when there is nothing to
  /// report.
  ///
  /// Shape of the event is documented on the Android side's `devListenerProxy`:
  /// always a `deviceId`, plus any of `dps`, `online`, `removed` and `device`.
  DeviceUpdate? _deviceUpdate(Object? event) {
    if (event is! Map) return null;
    final deviceId = '${event['deviceId'] ?? ''}';
    if (deviceId.isEmpty) return null;

    if (event['removed'] == true) {
      _snapshots.remove(deviceId);
      _history.remove(deviceId);
      return DeviceUpdate.removed(deviceId);
    }

    final snapshot = _snapshots[deviceId];
    // A push for a device this session never listed. There is no snapshot to
    // merge into, and inventing one would drop every field the event omits;
    // the next device-list load picks it up in full.
    if (snapshot == null) return null;

    final merged = Map<Object?, Object?>.of(snapshot);
    // A device-info change ships the whole bean, so it lands first and the DP
    // delta is applied on top.
    final device = event['device'];
    if (device is Map) merged.addAll(device);
    final dps = event['dps'];
    // 本次报文带了哪几个 DP。合并之后就分不出来了，所以在合并前先记下来。
    var changed = const <int>{};
    if (dps is Map) {
      final known = merged['dps'];
      merged['dps'] = <Object?, Object?>{
        if (known is Map) ...known,
        ...dps,
      };
      changed = dps.keys
          .map((key) => int.tryParse('$key'))
          .whereType<int>()
          .toSet();
    }
    final online = event['online'];
    if (online is bool) merged['online'] = online;

    return DeviceUpdate.changed(_device(merged), changedDps: changed);
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw TuyaException(error.code, error.message ?? '涂鸦 SDK 调用失败');
    } on MissingPluginException {
      throw const TuyaException('sdk_unavailable', '原生涂鸦 SDK 尚未接入');
    }
  }

  @override
  Future<bool> initialize() async => await _invoke<bool>('initialize') ?? false;

  @override
  Future<AppUser?> restoreSession() async {
    final raw = await _invoke<Map<Object?, Object?>>('currentUser');
    return raw == null ? null : _user(raw);
  }

  @override
  Future<void> sendVerificationCode({
    required String account,
    required String countryCode,
    required int type,
  }) => _invoke<void>('sendVerificationCode', <String, Object?>{
    'account': account,
    'countryCode': countryCode,
    'type': type,
  });

  @override
  Future<AppUser> login({
    required String account,
    required String credential,
    required LoginRegion region,
    required bool verificationCode,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>('login', <String, Object?>{
      'account': account,
      'credential': credential,
      'countryCode': region == LoginRegion.domestic ? '86' : '1',
      'verificationCode': verificationCode,
      'email': region == LoginRegion.overseas,
    });
    if (raw == null) throw const TuyaException('empty_user', '登录未返回用户信息');
    return _user(raw);
  }

  @override
  Future<AppUser> loginWithUid({
    required String uid,
    required String password,
    required String countryCode,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>(
      'loginWithUid',
      <String, Object?>{
        'uid': uid,
        'password': password,
        'countryCode': _resolveCountryCode(LoginRegion.domestic, countryCode),
      },
    );
    if (raw == null) throw const TuyaException('empty_user', '登录未返回用户信息');
    return _user(raw);
  }

  @override
  Future<AppUser> register({
    required String account,
    required String password,
    required String code,
    required LoginRegion region,
  }) async {
    final raw =
        await _invoke<Map<Object?, Object?>>('register', <String, Object?>{
          'account': account,
          'password': password,
          'code': code,
          'countryCode': region == LoginRegion.domestic ? '86' : '1',
          'email': region == LoginRegion.overseas,
        });
    if (raw == null) throw const TuyaException('empty_user', '注册未返回用户信息');
    return _user(raw);
  }

  @override
  Future<void> resetPassword({
    required String account,
    required String newPassword,
    required String code,
    required LoginRegion region,
  }) => _invoke<void>('resetPassword', <String, Object?>{
    'account': account,
    'newPassword': newPassword,
    'code': code,
    'countryCode': region == LoginRegion.domestic ? '86' : '1',
    'email': region == LoginRegion.overseas,
  });

  @override
  Future<void> updateNickname(String nickname) =>
      _invoke<void>('updateNickname', <String, Object?>{'nickname': nickname});

  @override
  Future<void> logout() => _invoke<void>('logout');

  @override
  Future<void> deleteAccount() => _invoke<void>('cancelAccount');

  @override
  Future<List<SmartPlanterDevice>> getDevices() async {
    final raw = await _invoke<List<Object?>>('getDevices') ?? <Object?>[];
    final devices = raw
        .whereType<Map<Object?, Object?>>()
        .map(_device)
        .toList();
    // Devices the account no longer owns leave their snapshot and decoded
    // history behind otherwise.
    final owned = devices.map((device) => device.id).toSet();
    _snapshots.removeWhere((id, _) => !owned.contains(id));
    _history.removeWhere((id, _) => !owned.contains(id));
    return devices;
  }

  @override
  Future<SmartPlanterDevice> pair(PairingRequest request) async {
    final raw = await _invoke<Map<Object?, Object?>>(
      'pairWifiDevice',
      <String, Object?>{
        'ssid': request.ssid,
        'password': request.password,
        'homeName': TuyaConfig.defaultHomeName,
      },
    );
    if (raw == null) throw const TuyaException('pair_failed', '配网未返回设备信息');
    return _device(raw);
  }

  @override
  Future<void> prepareActivatorToken() =>
      _invoke<void>('prepareActivatorToken');

  @override
  Future<bool> joinDeviceHotspot({String? ssid, String? prefix}) async =>
      await _invoke<bool>('joinDeviceHotspot', <String, Object?>{
        'ssid': ssid ?? '',
        'prefix': prefix ?? '',
      }) ??
      false;

  @override
  Future<void> leaveDeviceHotspot() => _invoke<void>('leaveDeviceHotspot');

  @override
  Future<void> cancelPairing() => _invoke<void>('cancelPairing');

  @override
  Future<String> currentHomeId() async =>
      await _invoke<String>('currentHomeId') ?? '';

  @override
  Future<Map<String, bool>> deviceOnlineStates(List<String> deviceIds) async {
    if (deviceIds.isEmpty) return const <String, bool>{};
    final raw = await _invoke<Map<Object?, Object?>>('deviceOnlineStates', {
      'deviceIds': deviceIds,
    });
    if (raw == null) return const <String, bool>{};
    return <String, bool>{
      for (final entry in raw.entries)
        if (entry.value is bool) '${entry.key}': entry.value! as bool,
    };
  }

  @override
  Future<void> useHome(String homeId) =>
      _invoke<void>('setHomeId', <String, Object?>{'homeId': homeId});

  @override
  Future<void> useHomeTag(String tag) =>
      _invoke<void>('setHomeTag', <String, Object?>{'tag': tag});


  @override
  Future<WifiScan> scanWifi({bool refresh = true}) async {
    final raw = await _invoke<Map<Object?, Object?>>('scanWifi', <String, Object?>{
      'refresh': refresh,
    });
    if (raw == null) throw const TuyaException('scan_failed', 'Wi-Fi 扫描未返回结果');
    final networks = (raw['networks'] as List<Object?>? ?? <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => WifiNetwork(
            ssid: '${item['ssid'] ?? ''}',
            level: (item['level'] as num?)?.toInt() ?? -100,
            frequency: (item['frequency'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
    return WifiScan(
      networks: networks,
      current: raw['current']?.toString(),
      currentFrequency: (raw['currentFrequency'] as num?)?.toInt(),
      throttled: raw['throttled'] == true,
      ageMs: (raw['ageMs'] as num?)?.toInt(),
    );
  }

  @override
  Future<BleAvailability> bleProbe() async {
    final raw = await _invoke<Map<Object?, Object?>>('bleProbe');
    if (raw == null) {
      return const BleAvailability(
        available: false,
        supported: false,
        enabled: false,
        reason: '这个平台没有实现 BLE 发现',
      );
    }
    return BleAvailability.fromMap(raw);
  }

  @override
  Future<void> startBleScan({
    Duration timeout = const Duration(seconds: 60),
  }) => _invoke<void>('startBleScan', <String, Object?>{
    'timeoutMs': timeout.inMilliseconds,
  });

  @override
  Future<void> stopBleScan() => _invoke<void>('stopBleScan');

  @override
  Future<List<DeviceWifiNetwork>> queryDeviceWifiList(
    String uuid, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final raw = await _invoke<List<Object?>>(
      'queryDeviceConfigState',
      <String, Object?>{'uuid': uuid, 'timeoutMs': timeout.inMilliseconds},
    );
    return (raw ?? <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(DeviceWifiNetwork.fromMap)
        // 空 SSID 是隐藏网络或解析没对上，画出来用户也选不了。
        .where((item) => item.ssid.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<SmartPlanterDevice> pairBleDevice({
    required String uuid,
    required String ssid,
    required String password,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>(
      'pairBleDevice',
      <String, Object?>{
        'uuid': uuid,
        'ssid': ssid,
        'password': password,
        'timeoutMs': timeout.inMilliseconds,
      },
    );
    if (raw == null) throw const TuyaException('pair_failed', '配网未返回设备信息');
    return _device(raw);
  }

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) =>
      _invoke<void>('publishDps', <String, Object?>{
        'deviceId': deviceId,
        'dps': dps.map((key, value) => MapEntry('$key', value)),
      });

  @override
  Future<void> renameDevice(String deviceId, String name) => _invoke<void>(
    'renameDevice',
    <String, Object?>{'deviceId': deviceId, 'name': name},
  );

  @override
  Future<void> removeDevice(String deviceId, {required bool resetFactory}) =>
      _invoke<void>(
        resetFactory ? 'resetFactory' : 'removeDevice',
        <String, Object?>{'deviceId': deviceId},
      );

  /// History decoded from the raw DPs in the most recent [getDevices]
  /// snapshot, keyed by device id.
  ///
  /// The product reports its own history packets, so this no longer calls the
  /// cloud statistics service — which needs a paid platform subscription the
  /// account does not have.
  final Map<String, DeviceHistory> _history = <String, DeviceHistory>{};

  @override
  Future<List<double>> getHistory(
    String deviceId,
    SensorMetric metric,
    ReportRange range, {
    DateTime? date,
  }) async {
    final history = _history[deviceId];
    if (history == null) return const <double>[];
    if (range == ReportRange.day && date != null) {
      return history.daySeries(metric, date);
    }
    return history.series(metric, range);
  }

  @override
  Future<Map<String, String>> historyDiagnostics(String deviceId) async {
    final snapshot = _snapshots[deviceId];
    if (snapshot == null) {
      return <String, String>{'设备': '本次会话还没拉到这台设备的快照'};
    }
    final dps = (snapshot['dps'] as Map<Object?, Object?>?) ??
        <Object?, Object?>{};
    const rangeLabels = <String, String>{
      'day': '日',
      'week': '周',
      'month': '月',
    };
    final report = <String, String>{};
    TuyaConfig.history.forEach((metricKey, ranges) {
      final sampleBytes = TuyaConfig.historySampleBytes[metricKey] ?? 1;
      final parts = <String>[];
      ranges.forEach((rangeName, identifier) {
        final label = rangeLabels[rangeName] ?? rangeName;
        final id = TuyaConfig.dp[identifier];
        final raw = dps['$id'] ?? dps[id];
        if (raw == null) {
          parts.add('$label DP$id 无');
          return;
        }
        final range = ReportRange.values.byName(rangeName);
        final variableLength = TuyaConfig.historyVariableFrames.contains(
          identifier,
        );
        // 编码和字节数一起打：SDK 交上来的是十六进制串（见 TuyaRaw），这里
        // 一眼能看出是不是又按错编码解了——`hex 99字节/96点` 才是日包的正常样子。
        final bytes = TuyaRaw.bytes(raw);
        final size = raw is String || raw is List
            ? '${TuyaRaw.encodingOf(raw)} ${bytes?.length ?? 0}字节'
            : '${raw.runtimeType}';
        // 日包**认的是哪一种帧**必须打出来：7 天帧没有功能点表，App 是按帧长认的
        // （见 `TuyaHistoryCodec.decodeDaily`），认错一种整条曲线就是错位的垃圾
        // 数据，真机上只有这一行能看出来。
        if (range == ReportRange.day) {
          final frames = TuyaHistoryCodec.decodeDaily(
            raw,
            sampleBytes: sampleBytes,
            variableLength: variableLength,
          );
          parts.add('$label DP$id $size/${frames.label}');
          return;
        }
        final decoded = TuyaHistoryCodec.decode(
          raw,
          range: range,
          sampleBytes: sampleBytes,
          variableLength: variableLength,
        );
        parts.add('$label DP$id $size/${decoded.length}点');
      });
      report[metricKey] = parts.join(' · ');
    });
    return report;
  }

  @override
  Future<Map<String, Object?>?> reportedDps(
    String deviceId,
    List<String> identifiers,
  ) async {
    final snapshot = _snapshots[deviceId];
    if (snapshot == null) return null;
    final dps = (snapshot['dps'] as Map<Object?, Object?>?) ??
        <Object?, Object?>{};
    return <String, Object?>{
      for (final identifier in identifiers)
        identifier:
            dps['${TuyaConfig.dp[identifier]}'] ?? dps[TuyaConfig.dp[identifier]],
    };
  }

  @override
  Future<Map<String, Object?>> deviceMessages({
    required String deviceId,
    String msgType = 'MSG_REPORT',
    int offset = 0,
    int limit = 50,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'deviceMessages',
        <String, Object?>{
          'deviceId': deviceId,
          'msgType': msgType,
          'offset': offset,
          'limit': limit,
        },
      );
      if (raw == null) {
        return <String, Object?>{
          'ok': false,
          'diagnostic': <String>['原生侧返回了 null'],
        };
      }
      return raw;
    } on MissingPluginException {
      // iOS 侧没接这个方法：那边的桥接是直接引 SDK 类型写的，本机没有 SDK 包、
      // 也编译不了，与其猜类名把 iOS 构建搞挂，不如在这里如实说明。
      // 接的时候要用的方法名产品已经给了（2026-09-20），照抄下面这行，别再去猜同名的安卓方法。
      return <String, Object?>{
        'ok': false,
        'diagnostic': <String>[
          '本端未接入 deviceMessages：只做了 Android 侧桥接，iOS 待补',
          'iOS 要调的是 ThingSmartMessage 的 '
              'fetchEncryptMessageDetailListWithListRequestModel:success:failure:'
              '（请求模型里带 msgSrcId / 类型 / 分页），不是安卓那个 getMessageListByMsgSrcId',
        ],
      };
    } on PlatformException catch (error) {
      return <String, Object?>{
        'ok': false,
        'code': error.code,
        'message': error.message,
        'diagnostic': <String>['原生抛错：${error.code} ${error.message}'],
      };
    }
  }

  @override
  Future<Map<String, Object?>> deviceOperateLogs({
    required String deviceId,
    String dpIds = '',
    int offset = 0,
    int limit = 20,
    String startTime = '',
    String endTime = '',
    String sort = '',
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'deviceOperateLogs',
        <String, Object?>{
          'deviceId': deviceId,
          'dpIds': dpIds,
          'offset': offset,
          'limit': limit,
          'startTime': startTime,
          'endTime': endTime,
          'sort': sort,
        },
      );
      return raw ??
          <String, Object?>{
            'ok': false,
            'diagnostic': <String>['原生侧返回了 null'],
          };
    } on MissingPluginException {
      return <String, Object?>{
        'ok': false,
        'diagnostic': <String>[
          '本端未接入 deviceOperateLogs：只做了 Android 侧桥接，iOS 待补',
          'iOS 要调的是 ThingSmartDevice 的 '
              'queryDeviceOperateLogWithDpIds:offset:limit:startTime:endTime:isASC:success:failure:',
        ],
      };
    } on PlatformException catch (error) {
      return <String, Object?>{
        'ok': false,
        'code': error.code,
        'message': error.message,
        'diagnostic': <String>['原生抛错：${error.code} ${error.message}'],
      };
    }
  }

  @override
  Future<Map<String, Object?>> messagesByTime({
    required int startTime,
    required int endTime,
    String deviceId = '',
    int offset = 0,
    int limit = 50,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'messagesByTime',
        <String, Object?>{
          'startTime': startTime,
          'endTime': endTime,
          'deviceId': deviceId,
          'offset': offset,
          'limit': limit,
        },
      );
      return raw ??
          <String, Object?>{
            'ok': false,
            'diagnostic': <String>['原生侧返回了 null'],
          };
    } on MissingPluginException {
      return <String, Object?>{
        'ok': false,
        'diagnostic': <String>['本端未接入 messagesByTime：只做了 Android 侧桥接'],
      };
    } on PlatformException catch (error) {
      return <String, Object?>{
        'ok': false,
        'code': error.code,
        'message': error.message,
        'diagnostic': <String>['原生抛错：${error.code} ${error.message}'],
      };
    }
  }

  @override
  Future<String> createShareLink(String deviceId) async =>
      await _invoke<String>('createShareLink', <String, Object?>{
        'deviceId': deviceId,
      }) ??
      '';

  @override
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async =>
      _firmwareUpdate(
        await _invoke<Object>('checkFirmware', <String, Object?>{
          'deviceId': deviceId,
        }),
      );

  /// 桥接回的是 `{version, currentVersion, upgradeType}`；装着旧原生包的机器只回一个版本号
  /// 字符串，那种情况按「只知道新版本」处理，不至于整块功能失效。
  static FirmwareUpdate? _firmwareUpdate(Object? raw) {
    String clean(Object? value) {
      final text = value?.toString().trim() ?? '';
      return text == 'null' ? '' : text;
    }

    if (raw is String) {
      final version = clean(raw);
      return version.isEmpty ? null : FirmwareUpdate(version: version);
    }
    if (raw is! Map) return null;
    final version = clean(raw['version']);
    if (version.isEmpty) return null;
    final current = clean(raw['currentVersion']);
    return FirmwareUpdate(
      version: version,
      currentVersion: current.isEmpty ? null : current,
      upgradeType: FirmwareUpgradeType.fromTuya(raw['upgradeType']),
    );
  }

  @override
  Future<void> startFirmwareUpgrade(String deviceId) => _invoke<void>(
    'startFirmwareUpgrade',
    <String, Object?>{'deviceId': deviceId},
  );

  @override
  Future<void> uploadAnimation(String deviceId, AnimationAsset asset) =>
      _invoke<void>('uploadAnimation', <String, Object?>{
        'deviceId': deviceId,
        'path': asset.path,
        'name': asset.name,
      });

  AppUser _user(Map<Object?, Object?> raw) => AppUser(
    id: '${raw['uid'] ?? raw['id'] ?? ''}',
    nickname: '${raw['nickname'] ?? raw['nickName'] ?? '植物守护者'}',
    account: '${raw['account'] ?? raw['username'] ?? ''}',
    avatarUrl: raw['avatarUrl']?.toString(),
  );

  SmartPlanterDevice _device(Map<Object?, Object?> raw) {
    final dps = (raw['dps'] as Map<Object?, Object?>?) ?? <Object?, Object?>{};

    // DP values arrive keyed by id. Whether that id is a string or a number
    // depends on how the platform channel encoded the map, so try both.
    Object? dp(String identifier) {
      final id = TuyaConfig.dp[identifier];
      return dps['$id'] ?? dps[id];
    }

    int integer(Object? value, int fallback) => switch (value) {
      int value => value,
      num value => value.round(),
      String value => int.tryParse(value) ?? fallback,
      _ => fallback,
    };

    double decimal(Object? value, double fallback) => switch (value) {
      num value => value.toDouble(),
      String value => double.tryParse(value) ?? fallback,
      _ => fallback,
    };

    bool boolean(Object? value, bool fallback) => switch (value) {
      bool value => value,
      String value => value == 'true',
      _ => fallback,
    };

    // Reads a DP the device transmits as an integer multiplied by a power of
    // ten. Sending the raw number straight to the UI is how 24.6 °C turns into
    // 246 °C on the temperature card.
    double scaled(String identifier, double fallback) {
      final value = dp(identifier);
      if (value == null) return fallback;
      final scale = TuyaConfig.dpScale[identifier] ?? 1;
      return decimal(value, fallback * scale) / scale;
    }

    // Joins the two minutes-past-midnight DPs behind a schedule into the
    // `HH:MM-HH:MM` label every settings screen edits.
    String period(
      String startIdentifier,
      String endIdentifier,
      String fallback,
    ) {
      final start = dp(startIdentifier);
      final end = dp(endIdentifier);
      if (start == null || end == null) return fallback;
      final startLabel = TuyaConfig.clockLabel(integer(start, -1));
      final endLabel = TuyaConfig.clockLabel(integer(end, -1));
      if (startLabel == null || endLabel == null) return fallback;
      return '$startLabel-$endLabel';
    }

    // Null when the device has not reported the status DP yet, or reported a
    // value the firmware added after this table was written. Callers fall back
    // to their own thresholds rather than showing a blank.
    T? reported<T>(String identifier, Map<String, T> values) {
      final value = dp(identifier);
      return value == null ? null : values['$value'];
    }

    DeviceHistory decodeHistory() {
      final series = <String, List<double>>{};
      final daily = <String, Map<String, List<double>>>{};
      TuyaConfig.history.forEach((metricKey, ranges) {
        final metric = _historyMetric(metricKey);
        final sampleBytes = TuyaConfig.historySampleBytes[metricKey] ?? 1;
        // 温度、湿度的点位和它们的实时 DP 一样带倍数，画之前先还原成真值。
        final scale = TuyaConfig.historyScale[metricKey];
        List<double> restore(List<double> points) => scale == null
            ? points
            : <double>[for (final point in points) point / scale];
        ranges.forEach((rangeName, identifier) {
          final range = ReportRange.values.byName(rangeName);
          final variableLength = TuyaConfig.historyVariableFrames.contains(
            identifier,
          );
          // 日包 2026-09-17 起一次带 7 天：按天解一份给报表按日期取，同时把**最新
          // 那天**放进 series，状态页和首页那条曲线照旧读它，不用跟着改。
          if (range == ReportRange.day) {
            final frames = TuyaHistoryCodec.decodeDaily(
              dp(identifier),
              sampleBytes: sampleBytes,
              variableLength: variableLength,
            );
            final newest = frames.newest;
            if (newest == null) return;
            daily[metric.name] = <String, List<double>>{
              for (final slice in frames.days)
                slice.dayKey: restore(slice.samples),
            };
            series[DeviceHistory.key(metric, range)] = restore(newest.samples);
            return;
          }
          final decoded = TuyaHistoryCodec.decode(
            dp(identifier),
            range: range,
            sampleBytes: sampleBytes,
            variableLength: variableLength,
          );
          if (decoded.isNotEmpty) {
            series[DeviceHistory.key(metric, range)] = restore(decoded);
          }
        });
      });
      if (series.isEmpty && daily.isEmpty) return DeviceHistory.empty;
      return DeviceHistory(series, daily);
    }

    final batteryStatus = reported(
      'battery_status',
      const <String, BatteryStatus>{
        'shortage': BatteryStatus.shortage,
        'good': BatteryStatus.good,
        'charging': BatteryStatus.charging,
      },
    );
    final status = DeviceStatusReport(
      battery: batteryStatus,
      waterNeeds: reported(
        'water_needs_status',
        const <String, WaterNeedsStatus>{
          'shortage': WaterNeedsStatus.shortage,
          'drinking': WaterNeedsStatus.drinking,
          'watery': WaterNeedsStatus.watery,
        },
      ),
      lighting: reported(
        'lighting_condition',
        const <String, LightingCondition>{
          'shortage': LightingCondition.shortage,
          'good': LightingCondition.good,
          'very_good': LightingCondition.veryGood,
        },
      ),
      temperature: reported(
        'air_temperature_status',
        const <String, ComfortLevel>{
          'cold': ComfortLevel.low,
          'suitable': ComfortLevel.suitable,
          'heat': ComfortLevel.high,
        },
      ),
      humidity: reported('air_humidity_status', const <String, ComfortLevel>{
        'dry': ComfortLevel.low,
        'suitable': ComfortLevel.suitable,
        'damp': ComfortLevel.high,
      }),
    );

    final settings = DeviceControlSettings(
      autoBrightness: boolean(dp('disp_brightness_switch'), true),
      soundInteraction: boolean(dp('voice_interaction_switch'), true),
      soundSensitivity: integer(dp('sound_sensitivity'), 60),
      touchInteraction: boolean(dp('touch_interact_switch'), true),
      touchSensitivity: integer(dp('touch_sense_sensitivity'), 70),
      vibration: boolean(dp('vibration_switch'), true),
      touchKeyVibration: boolean(dp('touch_vib_switch'), true),
      touchPlantVibration: boolean(dp('touch_plant_vib_switch'), true),
      napEnabled: boolean(dp('nap_time_switch'), true),
      napPeriod: period('nap_start_time', 'nap_end_time', '12:30-13:30'),
      nightEnabled: boolean(dp('night_sleep_switch'), true),
      nightPeriod: period(
        'night_sleep_start_time',
        'night_sleep_end_time',
        '23:00-07:00',
      ),
      temperatureUnit:
          _temperatureUnits['${dp('temp_unit_convert')}'] ?? 'celsius',
      clockFormat: '${dp('time_format') ?? '24h'}',
      // 151 defaults to 0 in the export: an unreported device never sleeps.
      standbyEnabled: boolean(dp('standby_switch'), false),
      standbyDelayMinutes: integer(dp('standby_delay'), 30),
      deviceLanguage: _deviceLanguages['${dp('language')}'] ?? 'zh',
      // 163 未上报时按「开」处理，见 DeviceControlSettings.plantDetection。
      plantDetection: boolean(dp('plant_detect_switch'), true),
    );

    final deviceId = '${raw['deviceId'] ?? raw['devId'] ?? ''}';
    final history = decodeHistory();
    _history[deviceId] = history;
    // Kept so the next DP report has a full device to merge into.
    _snapshots[deviceId] = raw;

    final reportedDays = dp('together_days');
    // DP 148 is the firmware the device runs; `getPv` on the device bean is the
    // protocol version, so it is only a fallback.
    final firmware = dp('firmware_version') ?? raw['firmwareVersion'];
    return SmartPlanterDevice(
      id: deviceId,
      productId: '${raw['productId'] ?? raw['pid'] ?? ''}',
      name: '${raw['name'] ?? '智能花盆'}',
      iconUrl: '${raw['iconUrl'] ?? ''}',
      online: boolean(raw['online'], false),
      signal: integer(raw['signal'], 0),
      battery: integer(dp('battery_level'), 0),
      charging: boolean(
        dp('charge_status'),
        batteryStatus == BatteryStatus.charging,
      ),
      boundAt: DateTime.fromMillisecondsSinceEpoch(
        integer(
              raw['activeTime'],
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
            ) *
            1000,
      ),
      plant: PlantProfile.unavailable,
      sensors: SensorSnapshot(
        waterLevel: integer(dp('water_level'), 0),
        soilMoisture: integer(dp('soil_moist'), 0),
        illuminance: integer(dp('light_intensity'), 0),
        ppfd: decimal(dp('light_ppfd_value'), 0),
        par: decimal(dp('light_par_value'), 0),
        airTemperature: scaled('air_temperature', 0),
        relativeHumidity: scaled('air_humidity', 0).round(),
      ),
      settings: settings,
      firmwareVersion: '${firmware ?? '--'}',
      macAddress: '${raw['mac'] ?? '--'}',
      hardwareVersion: '${dp('hardware_version') ?? '--'}',
      plantVariety: '${dp('plant_variety') ?? ''}',
      plantConfirm: PlantConfirmState.fromDp(dp('plant_confirm')),
      // 原始值原样留一份：`fromDp` 会把一切非 1 的都归成 hidden，联调时那样就看不出
      // 设备到底报了什么。写法和上面 plant_variety 一致（没上报过 ⇒ 空串）。
      plantConfirmRaw: '${dp('plant_confirm') ?? ''}',
      deviceStatus: '${dp('device_status') ?? ''}',
      reportedDays: reportedDays == null ? null : integer(reportedDays, 0),
      status: status,
      history: history,
      birthday: TuyaMemorialCodec.decodeFixedDate(dp('memorial_birthday')),
      weddingDay: TuyaMemorialCodec.decodeFixedDate(dp('memorial_wedding')),
      lastOperationResult: '${dp('op_result') ?? ''}',
    );
  }

  /// `temp_unit_convert` enum value back to the label the settings sheet uses.
  static final Map<String, String> _temperatureUnits = <String, String>{
    for (final entry in TuyaConfig.temperatureUnits.entries)
      entry.value: entry.key,
  };

  /// `language` (153) enum value back to the app's own `zh`/`en` code.
  static final Map<String, String> _deviceLanguages = <String, String>{
    for (final entry in TuyaConfig.deviceLanguages.entries)
      entry.value: entry.key,
  };

  /// `TuyaConfig.history` 的键换成图表用的指标。表里没有的键归到照度是历史遗留，
  /// 2026-09-16 加温度、湿度时改成逐个列出——再落到 `_` 上，新指标会被悄悄画成
  /// 光照曲线。
  static SensorMetric _historyMetric(String key) => switch (key) {
    'waterLevel' => SensorMetric.waterLevel,
    'soilMoisture' => SensorMetric.soilMoisture,
    'temperature' => SensorMetric.temperature,
    'humidity' => SensorMetric.humidity,
    _ => SensorMetric.light,
  };
}

class TuyaException implements Exception {
  const TuyaException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
