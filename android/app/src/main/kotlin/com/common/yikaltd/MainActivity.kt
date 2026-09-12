package com.common.yikaltd

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.Uri
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * AP 热点配网的模式常量，新拼写在前。
 *
 * 涂鸦在 7.x 把 `ActivatorModelEnum` 的常量从 `TY_*` 改成了 `THING_*`——7.5.1 只提供
 * `THING_AP / THING_EZ / THING_4G_GATEWAY / THING_STATIC_IP / THING_QR`，没有任何
 * `TY_*`。旧名留着做兜底，这样桥接对更老的 SDK 包也能用。
 *
 * **只有 AP。** EZ 真机实测设备不支持，双模是为 EZ 准备的，2026-09-11 一起删了。
 */
private val AP_MODE_NAMES = listOf("THING_AP", "TY_AP")

/**
 * How long a cached provisioning token may be reused.
 *
 * Tuya issues them with a 10-minute validity; 8 leaves room for the user to
 * switch networks and for the activator's own handshake.
 */
private const val ACTIVATOR_TOKEN_TTL_MS = 8L * 60 * 1000

/**
 * How long `scanWifi` waits for the results of the sweep it just started.
 *
 * A Wi-Fi scan takes roughly two to four seconds; past that the cache is
 * answered with instead, so a device that refuses to broadcast never leaves
 * the search page spinning.
 */
private const val SCAN_RESULT_WAIT_MS = 5000L

/** Request/response channel; mirrored by `TuyaConfig.channelName`. */
private const val METHOD_CHANNEL = "com.common.yikaltd/tuya"

/**
 * Device-push channel; mirrored by `TuyaConfig.eventChannelName`.
 *
 * Everything the device reports on its own — DP updates, online state, removal
 * — travels here instead of over the method channel, which only ever answers
 * the call the app made.
 */
private const val EVENT_CHANNEL = "com.common.yikaltd/tuya_events"

class MainActivity : FlutterActivity() {
    private lateinit var bridge: TuyaSdkBridge
    private var pendingPair: PendingPair? = null

    /** A provisioning call parked while its permissions are requested. */
    private class PendingPair(
        val call: MethodCall,
        val result: MethodChannel.Result,
        /** Denying any of these makes provisioning impossible. */
        val required: Set<String>,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = TuyaSdkBridge(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler { call, rawResult ->
            // Wrapped up front so the permission-retry path is covered too.
            val result = SingleResult(rawResult)
            val needsWifiPermissions =
                call.method == "pairWifiDevice" || call.method == "scanWifi"
            // BLE 发现要的是另一套权限（Android 12 起蓝牙扫描从定位里独立出来），
            // 拿 Wi-Fi 那套去要会当场少一个 BLUETOOTH_SCAN、扫不出任何东西。
            val needsBlePermissions =
                call.method == "startBleScan" ||
                    call.method == "queryDeviceConfigState" ||
                    call.method == "pairBleDevice" ||
                    call.method == "ensureBlePermissions"
            if ((needsWifiPermissions || needsBlePermissions) &&
                requestPairingPermissions(call, result, forBle = needsBlePermissions)
            ) {
                return@setMethodCallHandler
            }
            bridge.handle(call, result)
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    bridge.attachEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    bridge.attachEventSink(null)
                }
            },
        )
    }

    /**
     * Device listeners outlive the Flutter engine unless they are unregistered:
     * the SDK holds the proxy, the proxy holds this activity.
     */
    override fun onDestroy() {
        // 配网占着的东西也要放：热点请求的回调闭包引用着本 Activity，进程网络绑定
        // 则会让重建后的页面一直没网。
        bridge.releasePairing("pair_cancelled", "页面已销毁，配网中止")
        bridge.releaseDeviceListeners()
        bridge.attachEventSink(null)
        super.onDestroy()
    }

    /**
     * The planter is provisioned over 2.4 GHz Wi-Fi (EZ/AP) and has no BLE
     * pairing, so only Wi-Fi permissions are requested. Asking for
     * BLUETOOTH_SCAN/CONNECT here used to let a reasonable "deny" on a prompt
     * the product never needs block provisioning outright.
     */
    private fun requestPairingPermissions(
        call: MethodCall,
        result: MethodChannel.Result,
        forBle: Boolean = false,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val required = mutableSetOf<String>()
        val requested = mutableSetOf<String>()
        if (forBle) {
            // **BLE 扫描的权限按版本分两套**（2026-09-11 真机扫不到设备之后重排）：
            //
            // - Android 12+（API 31）：BLUETOOTH_SCAN + BLUETOOTH_CONNECT，**外加定位**。
            //   定位这一条是因为清单里**故意没写** `neverForLocation`：带上那个标志虽然能
            //   免掉定位，但系统会把"可能用于推断位置"的广播（iBeacon 这类）从扫描结果里
            //   过滤掉，而待配网设备广播的正是这类数据——结果就是静默扫不到。涂鸦官方口径
            //   同样写着「除非需扫描 iBeacon 类广播」。
            // - Android 11 及以下：没有独立的蓝牙扫描权限，BLE 扫描**一律按定位管**，
            //   FINE 是必需的（COARSE 在 10 之后已经不够）。BLUETOOTH / BLUETOOTH_ADMIN
            //   是 normal 级、装机即授予，不用在这里申请。
            //
            // ⚠️ 光有权限还不够：**系统的"定位服务"开关也必须打开**，否则 BLE 扫描
            // 同样是静默返回空。那一条不是权限、要不到，只能检测并告诉用户（见 `bleProbe`）。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                required += Manifest.permission.BLUETOOTH_SCAN
                // 查设备扫到的 Wi-Fi 列表要真的和设备建一条 BLE 连接，那一步要 CONNECT。
                required += Manifest.permission.BLUETOOTH_CONNECT
            }
            required += Manifest.permission.ACCESS_FINE_LOCATION
            // 一并要上 COARSE：部分 ROM 在 FINE 之外还会看它。
            requested += Manifest.permission.ACCESS_COARSE_LOCATION
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            required += Manifest.permission.NEARBY_WIFI_DEVICES
            // Still asked for: several SDK paths read the current SSID through
            // location, but provisioning is not blocked when it is refused.
            requested += Manifest.permission.ACCESS_FINE_LOCATION
        } else {
            required += Manifest.permission.ACCESS_FINE_LOCATION
        }
        requested += required
        val missing = requested.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) return false
        if (pendingPair != null) {
            result.error("busy", "已有配网权限请求正在进行", null)
            return true
        }
        pendingPair = PendingPair(call, result, required)
        requestPermissions(missing.toTypedArray(), 7101)
        return true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 7101) return
        val pending = pendingPair
        pendingPair = null
        if (pending == null) return
        val deniedRequired = permissions.filterIndexed { index, name ->
            name in pending.required &&
                grantResults.getOrNull(index) != PackageManager.PERMISSION_GRANTED
        }
        if (grantResults.isEmpty() || deniedRequired.isNotEmpty()) {
            pending.result.error(
                "permission_denied",
                // 哪一条被拒了直接列出来：「需要定位权限」这种笼统说法，用户在
                // 设置里根本对不上是哪一项（`PRODUCT_RULES` §4.1 事实在前）。
                "缺少权限：${deniedRequired.joinToString { it.substringAfterLast('.') }}",
                null,
            )
        } else {
            bridge.handle(pending.call, pending.result)
        }
    }
}

/**
 * Guarantees a single reply per call.
 *
 * The provisioning chain reports through several SDK callbacks; if two of them
 * fire, replying twice throws inside the Flutter engine and takes the process
 * down.
 */
private class SingleResult(private val delegate: MethodChannel.Result) :
    MethodChannel.Result {
    private val replied = AtomicBoolean(false)

    override fun success(result: Any?) {
        if (replied.compareAndSet(false, true)) delegate.success(result)
    }

    override fun error(code: String, message: String?, details: Any?) {
        if (replied.compareAndSet(false, true)) {
            delegate.error(code, message, details)
        }
    }

    override fun notImplemented() {
        if (replied.compareAndSet(false, true)) delegate.notImplemented()
    }
}

/**
 * Flutter-to-Tuya adapter. Reflection is deliberate: the app-specific Tuya
 * security component is not committed to source control. Once
 * security-algorithm.aar is placed in app/libs, Gradle links Home SDK 7.5.1
 * and Expansion SDK 7.8.0, and the same implementation starts calling the
 * real classes without source changes.
 *
 * SDK callbacks are never resolved by guessing interface names: every helper
 * looks the target method up first and builds the proxy from the callback
 * parameter type that method actually declares. That keeps the bridge working
 * across SDK versions that rename or split callback interfaces.
 */
private class TuyaSdkBridge(private val activity: FlutterActivity) {
    private var homeId: Long? = null

    /**
     * 本账号的家庭名标记（`YS-<userNo>`），由 Dart 在会话开始时下发。
     *
     * 家庭 id 只能由涂鸦分配，App 造不出来；但家庭**名字**是我们能定的，所以用它
     * 承载「这个家庭属于哪个账号」：建家时用这个名字，从家庭列表认领时优先认它。
     */
    private var homeTag: String? = null
    private var activator: Any? = null

    /**
     * 进行中的 pairWifiDevice 调用的回复句柄。取消、页面销毁或被新请求取代时用它
     * 把 `pair_cancelled` 回给 Dart——不回的话那边的 Future 永远挂着，busy 锁永远
     * 不放，整个 App 都点不动。回复过后置空。
     */
    private var pairingResult: MethodChannel.Result? = null

    /**
     * Last provisioning token and when it was fetched.
     *
     * Kept here and never handed to Dart: it is a short-lived cloud credential
     * and the debug console writes everything it receives into a visible log.
     */
    private var activatorToken: String? = null
    private var activatorTokenAt: Long = 0L

    /** AP 配网期间进程被绑定到的那个 Wi-Fi，用于识别热点何时消失。 */
    private var boundNetwork: Network? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    /** 由 App 发起的设备热点连接请求；释放它系统就会断开那条连接。 */
    private var hotspotCallback: ConnectivityManager.NetworkCallback? = null

    /**
     * 我们当前**自己持有**的那条热点连接对应的 SSID。
     *
     * 为什么要自己记：判断「是不是已经连上了」原先只看 `connectionInfo.ssid`，而那个值
     * 在**没有定位权限**时会返回 `<unknown ssid>`（Android 8.1 起的限制）。读不到就判断成
     * 「还没连」，于是又发一次 `requestNetwork` —— 用户就会看到**第二个**系统确认框。
     * 自己记账不依赖任何权限，也不依赖系统怎么报当前网络。
     */
    private var boundHotspotSsid: String? = null

    /**
     * `IThingDevice` instances that currently hold a registered listener, keyed
     * by device id. Written from the main thread, read from the SDK's callback
     * threads.
     */
    private val watched = ConcurrentHashMap<String, Any>()

    /**
     * 每台设备一个 OTA 实例，按 deviceId 缓存。
     *
     * `newOTAInstance` 每次调用都新建一个 `IThingOta`，而升级要跑几分钟：
     * `startOta` 一返回就把它丢掉的话，App 这边没有任何强引用，注册进去的监听
     * 代理随时可能被回收，进度和成败回调就再也不来了——界面上表现为进度条停在
     * 某个百分比再也不动。所以实例留在这里，直到升级结束或 Activity 销毁时才
     * 调 `onDestroy` 放掉。
     */
    private val otaInstances = ConcurrentHashMap<String, Any>()

    /** Dart's end of [EVENT_CHANNEL], or null while nothing is listening. */
    @Volatile
    private var events: EventChannel.EventSink? = null

    fun attachEventSink(sink: EventChannel.EventSink?) {
        events = sink
    }

    /**
     * Drops every device listener. Safe to call when none are registered.
     *
     * The event sink is left attached: a logout ends the device subscriptions,
     * not Dart's stream, and the next login registers listeners again.
     */
    fun releaseDeviceListeners() {
        watched.keys.toList().forEach(::unwatchDevice)
        otaInstances.keys.toList().forEach(::releaseOta)
        // BLE 扫描的回调代理同样握着本 Activity，而且还在真的耗电。
        stopBleScan()
    }

    /**
     * 放掉一台设备的 OTA 实例，连带 SDK 内部注册的监听。
     *
     * `onDestroy` 在不同 SDK 版本里未必存在，反射失败当成"这个版本不需要显式
     * 释放"处理——这里已经在收尾路径上，抛出去只会盖掉真正要报的东西。
     */
    private fun releaseOta(deviceId: String) {
        val ota = otaInstances.remove(deviceId) ?: return
        runCatching { invoke(ota, "onDestroy") }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "scanWifi") {
                scanWifi(call, result)
                return
            }
             // 释放类调用不依赖 SDK 就绪：SDK 没起来时也可能有残留的热点连接要放。
            if (call.method == "cancelPairing" || call.method == "leaveDeviceHotspot") {
                releasePairing("pair_cancelled", "配网已被中止")
                success(result, null)
                return
            }
            if (!ensureReady(result)) return
            when (call.method) {
                "initialize" -> result.success(true)
                "currentUser" -> currentUser(result)
                "sendVerificationCode" -> sendCode(call, result)
                "login" -> login(call, result)
                "loginWithUid" -> loginWithUid(call, result)
                "register" -> register(call, result)
                "resetPassword" -> resetPassword(call, result)
                "updateNickname" -> updateNickname(call, result)
                "logout" -> userAction("logout", result)
                "cancelAccount" -> userAction("cancelAccount", result)
                "getDevices" -> withHome(result) { home -> loadHomeDevices(home, result) }
                // 只读 SDK 本地缓存里的在线标志，**不发网络请求**。
                //
                // 在线/离线是 SDK 的 MQTT 心跳在维护的：设备掉线，云端判定之后把
                // 状态推给 SDK，SDK 更新 DeviceBean 并回调 onStatusChanged。回调这
                // 一路会漏——App 被切后台、MQTT 断开重连期间的变化不会补发。但
                // **bean 本身是准的**，所以 Dart 侧在前台按秒级把它读回来兜底。
                "deviceOnlineStates" -> {
                    val ids = (call.argument<List<*>>("deviceIds") ?: emptyList<Any?>())
                        .mapNotNull { it?.toString()?.takeIf { id -> id.isNotEmpty() } }
                    val states = HashMap<String, Any?>()
                    for (id in ids) {
                        val bean = deviceBean(id) ?: continue
                        val online = optionalGetter(bean, "getIsOnline")
                            ?: optionalGetter(bean, "isOnline")
                        if (online is Boolean) states[id] = online
                    }
                    success(result, states)
                }
                "prepareActivatorToken" -> prepareActivatorToken(result)
                 "pairWifiDevice" -> pairWifi(call, result)
                 // 设备列表是按家庭查的，家庭对不上就是 0 台，而这在 Dart 侧完全
                // 看不出来——联调页原来显示的「默认家庭」只是个本地常量。
                "currentHomeId" -> withHome(result) { id ->
                    success(result, id.toString())
                }
                // Dart 侧按账号记住上次用过的家庭，会话一开始就钉回来：家庭属于
                // 涂鸦账号，不该每次登录重新从列表里挑。
                "setHomeTag" -> {
                    homeTag = call.argument<String>("tag")?.takeIf { it.isNotBlank() }
                    success(result, null)
                }
                "setHomeId" -> {
                    homeId = call.argument<String>("homeId")?.toLongOrNull()
                    Log.i(TUYA_LOG_TAG, "home pinned to $homeId")
                    success(result, null)
                }
                "joinDeviceHotspot" -> joinDeviceHotspot(call, result)
                "bleProbe" -> bleProbe(result)
                "startBleScan" -> startBleScan(call, result)
                "stopBleScan" -> {
                    stopBleScan()
                    success(result, null)
                }
                // 只为了**触发那次授权框**。真正的权限申请由 `requestPairingPermissions`
                // 在方法通道入口处完成（`needsBlePermissions` 里有它），所以能走到这里
                // 就说明必需权限已经拿到了。
                "ensureBlePermissions" -> success(result, true)
                "queryDeviceProductInfo" -> queryDeviceProductInfo(call, result)
                "disconnectBleDevice" -> {
                    disconnectBleDevice(call.argument<String>("uuid").orEmpty())
                    success(result, null)
                }
                "openAppSettings" -> openAppSettings(result)
                "queryDeviceConfigState" -> bleQueryDeviceWifi(call, result)
                "pairBleDevice" -> pairBleDevice(call, result)
                "publishDps" -> deviceAction(call, result, "publishDps")
                "renameDevice" -> deviceAction(call, result, "renameDevice")
                "removeDevice" -> deviceAction(call, result, "removeDevice")
                "resetFactory" -> deviceAction(call, result, "resetFactory")
                "createShareLink" -> createShareLink(call, result)
                "getStatistics" -> result.error(
                    "service_configuration_required",
                    "设备数据统计服务需要在涂鸦平台开通后配置统计 API",
                    null,
                )
                "checkFirmware" -> checkFirmware(call, result)
                "startFirmwareUpgrade" -> startFirmwareUpgrade(call, result)
                "uploadAnimation" -> result.error(
                    "product_protocol_required",
                    "图片同步需要设备 PID 对应的文件传输协议",
                    null,
                )
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            fail(result, error)
        }
    }

    /**
     * Runs [block] on the main thread and turns any failure into a Flutter
     * error.
     *
     * SDK callbacks arrive on a background thread and outside the try/catch in
     * [handle], so an exception there would reach the thread's default handler
     * and kill the process. The Tuya activator also registers handlers and
     * receivers, which requires a looper thread.
     */
    private fun onMain(result: MethodChannel.Result, block: () -> Unit) {
        activity.runOnUiThread {
            try {
                block()
            } catch (error: Throwable) {
                fail(result, error)
            }
        }
    }

    /**
     * 中止进行中的配网并放掉它占着的一切：activator、App 发起的热点连接、进程
     * 网络绑定。进行中的 pairWifiDevice 以 [code] 失败返回。没有配网在跑时调用
     * 也安全——那就只是清一遍可能残留的网络绑定。
     */
    fun releasePairing(code: String, message: String) {
        val pending = pairingResult
        pairingResult = null
        stopActivator()
        // 双模那条也要停：它和 AP 用的是两个不同的配网器，停一个不影响另一个，
        // 漏停的那个会继续跑满超时、蓝牙连接也一直占着。
        bleScanned.keys.toList().forEach(::stopMultiModeActivator)
        // 兜底全断：设备只有在**没有连接**时才会广播，留着一条就等于让它从此扫不到。
        disconnectBleDevice("")
        pending?.let { error(it, code, message) }
    }

    /**
     * 配网调用的回复包装：无论成功、失败还是异常，回复前先把配网占着的资源放掉。
     *
     * 失败路径太多（查家庭、取令牌、反射找工厂/枚举、`start()` 抛异常、SDK 回调
     * 报错），逐一补 stopActivator 迟早漏一处——漏掉的后果是进程一直绑在设备热点
     * 上、热点请求不释放，之后每一次云端调用都无网失败，直到进程重启。之前
     * 恰好就漏了回调注册之前的那一段。
     */
    private inner class PairingResult(private val delegate: MethodChannel.Result) :
        MethodChannel.Result {
        override fun success(result: Any?) {
            finish()
            delegate.success(result)
        }

        override fun error(code: String, message: String?, details: Any?) {
            finish()
            delegate.error(code, message, details)
        }

        override fun notImplemented() {
            finish()
            delegate.notImplemented()
        }

        private fun finish() {
            if (pairingResult === this) pairingResult = null
            stopActivator()
        }
    }

    /**
     * The SDK is initialized in [FlowerpotApplication]; this only surfaces the
     * recorded reason when that initialization did not complete.
     */
    private fun ensureReady(result: MethodChannel.Result): Boolean {
        if (TuyaSdkInitializer.ensureInitialized(activity.application)) return true
        result.error(
            TuyaSdkInitializer.failureCode ?: "sdk_unavailable",
            TuyaSdkInitializer.failureMessage ?: "涂鸦 SDK 不可用",
            null,
        )
        return false
    }

    /**
     * Lists nearby access points and the network the phone is on.
     *
     * The planter provisions over 2.4 GHz Wi-Fi, so there is nothing to
     * discover before provisioning starts — except in AP mode, where the
     * device raises its own hotspot. Seeing that hotspot is the only reliable
     * pre-pairing proof that the device is in provisioning state, and the
     * current network tells you whether the phone sits on 2.4 GHz at all.
     */
    private fun scanWifi(call: MethodCall, result: MethodChannel.Result) {
        val context = activity.applicationContext
        val wifi = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifi.isWifiEnabled) {
            error(result, "wifi_disabled", "手机 Wi-Fi 未开启，无法扫描")
            return
        }
        // `refresh = false`：只读系统的扫描缓存，**不调 startScan、也不等广播**。
        //
        // 受配额限制的只有 `startScan`（前台每 2 分钟 4 次），读 `scanResults` 不
        // 受限也不耗时。而系统自己——连接管理、设置页、别的应用——同样在扫，缓存会
        // 被它们刷新。所以搜索页「30 秒一次真扫 + 2 秒一次读缓存」比只靠真扫快得多：
        // 设备热点一旦被**任何一次**扫描看到，下一次读缓存（最多 2 秒）就拿到了。
        if (call.argument<Boolean>("refresh") == false) {
            success(result, wifiSnapshot(wifi, throttled = false))
            return
        }
        // Android 9-12 refuse to return scan results while the location
        // toggle is off. From 13 the NEARBY_WIFI_DEVICES grant replaces that
        // requirement, so the check would be a false alarm there.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU &&
            !locationEnabled(context)
        ) {
            error(
                result,
                "location_disabled",
                "系统定位未开启；Android 9-12 扫描 Wi-Fi 必须打开定位开关",
            )
            return
        }
        // `startScan` is asynchronous: reading `scanResults` right after it
        // returns the *previous* sweep. On the search page that list was taken
        // before the user put the planter into pairing mode, so the device
        // hotspot is missing from it and the page reports "no device" while it
        // is right there — the SDK console, pressed a minute later against a
        // refreshed cache, shows it. So wait for the system's own
        // SCAN_RESULTS_AVAILABLE broadcast before answering.
        val replied = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())
        var receiver: BroadcastReceiver? = null
        // `throttled` 决定上层怎么走：被限流时这次答的是**旧缓存**，不是「附近没有设备」。
        val throttled = AtomicBoolean(false)
        val reply = {
            if (replied.compareAndSet(false, true)) {
                receiver?.let { runCatching { context.unregisterReceiver(it) } }
                handler.removeCallbacksAndMessages(null)
                success(result, wifiSnapshot(wifi, throttled.get()))
            }
        }
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                reply()
            }
        }
        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(
                    receiver,
                    filter,
                    Context.RECEIVER_NOT_EXPORTED,
                )
            } else {
                context.registerReceiver(receiver, filter)
            }
        }.onFailure { receiver = null }
        // Throttled since Android 9 (a few scans per two minutes). A refused
        // start never broadcasts, so answer from the cache right away instead
        // of sitting out the timeout.
        val started = runCatching { wifi.startScan() }.getOrDefault(false)
        if (!started) {
            // Android 9 起前台应用每 2 分钟只允许 4 次 startScan，超了就返回 false 且
            // 不再广播。这时 `scanResults` 是上一次真扫的缓存——用户刚开机的设备不在
            // 里面，报「未发现设备」是假的。标出来，让上层改成等配额回来再扫。
            throttled.set(true)
            reply()
            return
        }
        handler.postDelayed({ reply() }, SCAN_RESULT_WAIT_MS)
    }

    /** The scan cache and the current connection, as the Dart `WifiScan`. */
    private fun wifiSnapshot(wifi: WifiManager, throttled: Boolean): Map<String, Any?> {
        val networks = runCatching { wifi.scanResults }
            .getOrDefault(emptyList())
            .filter { !it.SSID.isNullOrBlank() }
            .sortedByDescending { it.level }
            .map { scan ->
                mapOf(
                    "ssid" to scan.SSID,
                    "bssid" to scan.BSSID,
                    "level" to scan.level,
                    "frequency" to scan.frequency,
                )
            }
        val current = runCatching {
            @Suppress("DEPRECATION")
            wifi.connectionInfo?.ssid?.trim('"')
        }.getOrNull()
        val currentFrequency = runCatching {
            @Suppress("DEPRECATION")
            wifi.connectionInfo?.frequency
        }.getOrNull()
        // 缓存有多旧：`ScanResult.timestamp` 是开机以来的微秒数，取最新一条来算。
        // 上层用它判断「这一轮到底扫没扫」，不必只靠 throttled 这一个信号。
        val newest = runCatching { wifi.scanResults }
            .getOrDefault(emptyList())
            .maxOfOrNull { it.timestamp }
        val ageMs = newest?.let { (SystemClock.elapsedRealtime() - it / 1000).coerceAtLeast(0) }
        return mapOf(
            "current" to current?.takeIf { it != "<unknown ssid>" },
            "currentFrequency" to currentFrequency,
            "networks" to networks,
            "throttled" to throttled,
            "ageMs" to ageMs,
        )
    }

    private fun locationEnabled(context: Context): Boolean {
        val manager =
            context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
    }

    // ════════════════ BLE 发现：双模设备的优化路径 ════════════════
    //
    // **为什么加这条。** 「搜索不及时」的根是 Android 的 Wi-Fi 扫描配额——前台每 2 分钟
    // 只允许 4 次 `startScan`，而设备上电到热点广播出来还要几十秒，两头一凑就是搜索页
    // 那段「30 秒真扫 + 2 秒读缓存」的硬扛。**BLE 扫描不受那条配额约束**：双模设备一上
    // 电就在广播 BLE，通常一两秒就能扫到。
    //
    // 拿到 `ScanDeviceBean` 之后还有第二个好处：它的 `flag` 里带着
    // `CombosFlagCapability.SCAN_WIFI` 这一位（固件 TuyaOS ≥ 3.6.1 才有）。置位就说明
    // 设备愿意把**它自己扫到的** Wi-Fi 列表报上来，于是连手机的 Wi-Fi 扫描都不用了：
    // 直接走 BLE 本地连接问它要（[bleQueryDeviceWifi]），彻底绕开配额。
    //
    // ⚠️ **这是一条并行加上去的发现通道，没有替换任何东西。** 设备扫不到 BLE 时搜索页
    // 照旧走 Wi-Fi 热点那条（`scanWifi`），配网本身仍然是 AP 那一条唯一路径。真机验完
    // 才决定要不要收掉其中一条。
    //
    // ⚠️ 反射调用没有编译期保护。这几个类与方法是 2026-09-11 从官方 Maven 下
    // `thingsmart-bluetooth(-api/-business-api) 7.5.1` 解包核对过的，逐个存在：
    // `ThingHomeSdk.getBleOperator()/getBleManager()`、
    // `IThingBleOperator.startLeScan(LeScanSetting, BleScanResponse)/stopLeScan()`、
    // `LeScanSetting$Builder`、`ScanType.SINGLE`、`ScanDeviceBean`、
    // `CombosFlagCapability.SCAN_WIFI/isCapabilityEnable(int,int)`、
    // `ThingHomeSdk.getActivator().newMultiModeActivator()`、
    // `IMultiModeActivator.queryDeviceConfigState(MultiModeQueryBuilder, IThingResultCallback)`、
    // `IMultiModeActivator.startActivator(MultiModeActivatorBean, IMultiModeActivatorListener)`、
    // `IMultiModeActivator.stopActivator(String)`、`MultiModeQueryBuilder$Builder`、
    // `MultiModeActivatorBean`（公有裸字段 ssid/pwd/token/homeId/scanDeviceBean/…）。
    // 核对工具是 `tools/aar_class_dump.py`（不依赖 JDK）。
    //
    // ⚠️ **同一轮里被证伪的名字，不要再有人接回来**：`ActivatorService` /
    // `BLEActivator` / `IDiscovery` / `ActivatorMode` / `DiscoveryMode` 在 7.5.1 的
    // **所有**模块里都是 0 命中——那几个名字属于设备固件侧的 TuyaOS（TKL），不是
    // Android App SDK。App 侧只有两个 BLE 配网入口：`IBleActivator`（纯蓝牙设备，
    // `BleActivatorBean` **没有 ssid/pwd**）与这里用的 `IMultiModeActivator`
    // （Wi-Fi+BLE 双模，`MultiModeActivatorBean` 带 ssid/pwd/token）。花盆是后者。

    /** 正在跑的那个 BLE 扫描回调代理；停扫时必须断开，SDK 否则一直握着它和本 Activity。*/
    private var bleScanner: Any? = null

    /**
     * BLE 扫到的原始 `ScanDeviceBean`，按 uuid 存。
     *
     * **必须留在原生侧。** 双模那两个 API（`queryDeviceConfigState` /
     * `startActivator`）吃的都是这个对象本身——`MultiModeQueryBuilder.setScanDeviceBean(bean)`、
     * `MultiModeActivatorBean.scanDeviceBean`。它过不了方法通道（里面有 `byte[] raw`、
     * `pidRaw` 这些广播原文），所以 Dart 侧只拿 uuid，用的时候回这里取。
     */
    private val bleScanned = ConcurrentHashMap<String, Any>()

    /** 双模配网器，`newMultiModeActivator()` 造一次就留着：`stopActivator` 还要用它。*/
    private var multiModeActivator: Any? = null

    /**
     * `ThingHomeSdk.getActivator().newMultiModeActivator()`。
     *
     * ⚠️ 注意是 `getActivator()`（返回 `IActivator`），**不是** `getActivatorInstance()`
     * （返回 `IThingDeviceActivator`，AP / EZ 那一套在用的）。两个入口并存，名字只差一点。
     */
    private fun multiModeActivator(): Any = multiModeActivator ?: run {
        val activatorApi = invokeStatic(sdkClass(), "getActivator")
            ?: throw IllegalStateException("getActivator() 返回空")
        val created = invoke(activatorApi, "newMultiModeActivator")
            ?: throw IllegalStateException("newMultiModeActivator() 返回空")
        multiModeActivator = created
        created
    }

    /** 取回 BLE 扫到的那个 bean；没扫到过就说清楚，别让上层以为是超时。*/
    private fun scannedBean(uuid: String): Any = bleScanned[uuid]
        ?: throw IllegalStateException("uuid=$uuid 不在本轮 BLE 扫描结果里，请重新扫描")

    private fun bleOperator(): Any = invokeStatic(sdkClass(), "getBleOperator")
        ?: throw IllegalStateException("getBleOperator() 返回空")

    /**
     * 这台手机 / 这个包到底能不能用 BLE。
     *
     * 三种情况分开报，别糅成一个 false：**手机没有 BLE 硬件**、**蓝牙开关关着**、
     * **包里根本没有蓝牙模块**（被裁掉或 SDK 没起来）——处置完全不同，糅在一起
     * 又成了让人猜（`PRODUCT_RULES` §4.1 事实在前）。
     */
    private fun bleProbe(result: MethodChannel.Result) {
        val operator = runCatching { bleOperator() }.getOrElse { cause ->
            success(
                result,
                mapOf(
                    "available" to false,
                    "supported" to false,
                    "enabled" to false,
                    "reason" to "SDK 蓝牙模块不可用：${cause.javaClass.simpleName}: ${cause.message}",
                ),
            )
            return
        }
        val supported =
            runCatching { invoke(operator, "isBleSupported") as? Boolean }.getOrNull() ?: false
        val enabled =
            runCatching { invoke(operator, "isBluetoothOpened") as? Boolean }.getOrNull() ?: false
        // ⚠️ **系统的"定位服务"开关**：Android 6～11 上 BLE 扫描强制要求它打开，
        // 关着的时候扫描**静默返回空**——不报错、不回调，跟"附近没有设备"完全分不开。
        // 12+ 我们又刻意没用 `neverForLocation`（见清单里的说明），所以同样受它影响。
        // 这一条不是权限、申请不来，只能检测出来告诉用户去开。
        val locationOn = runCatching { locationEnabled(activity) }.getOrElse { true }
        // 权限是另一回事：给了才扫得到。这里一并回报，省得"扫不到"时还要猜是哪一层。
        val scanPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val locationPermission =
            activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        success(
            result,
            mapOf(
                "available" to true,
                "supported" to supported,
                "enabled" to enabled,
                // 系统版本决定走哪一套权限模型，排查时必须知道。
                "sdkInt" to Build.VERSION.SDK_INT,
                "release" to Build.VERSION.RELEASE,
                "locationOn" to locationOn,
                "scanPermission" to scanPermission,
                "locationPermission" to locationPermission,
                "reason" to when {
                    !supported -> "这台手机不支持 BLE"
                    !enabled -> "蓝牙没有打开"
                    !scanPermission -> "缺少「附近的设备」权限（BLUETOOTH_SCAN）"
                    !locationPermission -> "缺少定位权限（BLE 扫描需要）"
                    !locationOn -> "系统定位服务没打开（BLE 扫描需要，关着会静默扫不到）"
                    else -> ""
                },
            ),
        )
    }

    /**
     * 开一轮 BLE 扫描，扫到的设备**逐台**推给 Dart（事件通道，`type = bleDevice`）。
     *
     * 不做成「扫完一次性返回」：BLE 的全部价值就在于第一台通常一两秒就出来，攒到
     * 超时再回等于把这个优势原样丢掉。
     */
    private fun startBleScan(call: MethodCall, result: MethodChannel.Result) {
        // 上一轮没停干净就先停：SDK 只保留最后一个回调，旧代理会一直漏在那里。
        stopBleScan()
        val operator = bleOperator()
        val timeout = call.argument<Number>("timeoutMs")?.toLong() ?: 60_000L
        val builder = firstClass("com.thingclips.smart.android.ble.api.LeScanSetting\$Builder")
            .getDeclaredConstructor()
            .apply { isAccessible = true }
            .newInstance()
        invoke(builder, "setTimeout", timeout)
        // 同一台设备允许重复上报：`rssi` 会跟着变，页面按信号排序就需要新值。
        invoke(builder, "setRepeatFilter", false)
        // **ScanType 全加上**（Dart 侧 `PairingGate.showUnfilteredBleScan`，2026-09-11）。
        //
        // 花盆按理是 `SINGLE`（Wi-Fi+BLE 双模的单点设备），正常动线只加它就够。但这一轮
        // 要回答的是**「设备到底在不在广播、广播成什么样」**：万一它报的是别的类型，
        // 只加 SINGLE 就什么都扫不到，而页面上看起来和「设备没开机」一模一样——结论正好
        // 相反。把 SDK 给的类型全加上，扫到什么算什么，让人看见事实再下判断。
        //
        // 只加得上 SDK 真有的那些：`unsupported` 里的名字只打一行日志，不拦路。
        val wanted = listOf("SINGLE", "SINGLE_QR", "NORMAL", "THING_BEACON", "MESH", "SIG_MESH")
        val unsupported = mutableListOf<String>()
        var added = 0
        for (name in wanted) {
            val type = runCatching { bleScanType(name) }.getOrNull()
            if (type == null) {
                unsupported += name
                continue
            }
            invoke(builder, "addScanType", type)
            added++
        }
        if (added == 0) {
            throw IllegalStateException("SDK 的 ScanType 一个都没匹配上：$wanted")
        }
        if (unsupported.isNotEmpty()) {
            trace("ble scan: 这一版 SDK 没有 ${unsupported.joinToString("/")}，已跳过")
        }
        val setting = invoke(builder, "build")
            ?: throw IllegalStateException("LeScanSetting.build() 返回空")
        // `ThingBleScanResponse` 继承 `BleScanResponse`，多出 onScanStart/onScanStop
        // 两个钩子——真机上「到底扫没扫起来」全靠它们，所以优先用它。
        val responseClass = firstClass(
            "com.thingclips.smart.android.ble.api.ThingBleScanResponse",
            "com.thingclips.smart.android.ble.api.BleScanResponse",
        )
        val loader = responseClass.classLoader ?: activity.classLoader
        val proxy = Proxy.newProxyInstance(loader, arrayOf(responseClass)) { self, method, args ->
            when (method.name) {
                "equals" -> self === args?.firstOrNull()
                "hashCode" -> System.identityHashCode(self)
                "toString" -> "TuyaBleScan"
                "onResult" -> {
                    args?.firstOrNull()?.let { bean ->
                        runCatching {
                            val map = bleDeviceMap(bean)
                            // 原始 bean 留下：双模的查询与配网吃的都是它本身。
                            (map["uuid"] as? String)?.takeIf { it.isNotEmpty() }?.let { uuid ->
                                bleScanned[uuid] = bean
                            }
                            emit(map)
                        }.onFailure { cause ->
                            trace("ble scan: 解析设备失败 ${cause.javaClass.simpleName}")
                        }
                    }
                    defaultValue(method.returnType)
                }
                "onScanStart" -> {
                    trace("ble scan: 已开始（SDK 回调 onScanStart）")
                    emit(mapOf("type" to "bleScanStarted"))
                    defaultValue(method.returnType)
                }
                "onScanStop" -> {
                    val reason = args?.firstOrNull()?.toString().orEmpty()
                    trace("ble scan: 已结束（$reason）")
                    emit(mapOf("type" to "bleScanStopped", "reason" to reason))
                    defaultValue(method.returnType)
                }
                else -> defaultValue(method.returnType)
            }
        }
        bleScanner = proxy
        bleCallbackCount.set(0)
        invoke(operator, "startLeScan", setting, proxy)
        trace("ble scan: startLeScan(timeout=${timeout}ms, 类型 $added 种)")
        success(result, null)
    }

    /**
     * 打开本应用的系统设置页。
     *
     * 权限被点成「拒绝」之后，`requestPermissions` 不会再弹框（系统直接回拒绝），
     * 这时能做的只有把用户送到设置页自己开。搜索页在检测到权限缺失时给这颗按钮。
     */
    private fun openAppSettings(result: MethodChannel.Result) {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", activity.packageName, null),
        )
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { activity.startActivity(intent) }
            .onSuccess { success(result, true) }
            .onFailure { cause -> error(result, "open_settings_failed", "打不开设置页：${cause.message}") }
    }

    /**
     * 按 BLE 扫到的标识**去云端查这台是什么产品**（名称、图标）。
     *
     * `IThingDeviceActivator.getActivatorDeviceInfo(productId, uuid, mac, IThingDataCallback)`
     * ——2026-09-11 产品给的思路，解包核对确实存在（不像同一批里那些 `ActivatorService` /
     * `IDiscovery`，那些是设备固件侧 TuyaOS 的命名、App SDK 里 0 命中）。
     *
     * 为什么需要它：BLE 广播里**常常没有名字**，页面上一行只有 `mac + pid + rssi`，人没法
     * 判断哪一台是花盆。拿 pid 去云端换回产品名和图标之后，列表才真的能"看出有没有"。
     *
     * ⚠️ 这是**云端往返**，调用方必须自己去重并限量（见 Dart 侧 `_productInfoBudget`）：
     * 不过滤扫描时附近可能有几十台设备，挨个查会把接口打满、也会拖慢页面。
     */
    private fun queryDeviceProductInfo(call: MethodCall, result: MethodChannel.Result) {
        val activatorApi = invokeStatic(sdkClass(), "getActivatorInstance")
            ?: throw IllegalStateException("无法获取配网实例")
        val productId = call.argument<String>("productId").orEmpty()
        val uuid = call.argument<String>("uuid").orEmpty()
        val mac = call.argument<String>("mac").orEmpty()
        invokeWithCallback(
            activatorApi,
            "getActivatorDeviceInfo",
            productId,
            uuid,
            mac,
            onSuccess = { value ->
                onMain(result) { success(result, productInfoMap(value)) }
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    /**
     * 云端返回的产品信息 → Dart。
     *
     * 字段名按常见写法逐个试，**认不出就把原样 `toString()` 带上**（`raw`）：真机上一眼
     * 能看出这一版 SDK 给的是什么 bean，比在这里猜快得多。
     */
    private fun productInfoMap(value: Any?): Map<String, Any?> {
        if (value == null) return mapOf("raw" to "")
        return mapOf(
            "name" to (
                optionalGetter(value, "getName")
                    ?: optionalGetter(value, "getProductName")
                )?.toString(),
            "icon" to (
                optionalGetter(value, "getIcon")
                    ?: optionalGetter(value, "getIconUrl")
                )?.toString(),
            "productId" to (
                optionalGetter(value, "getProductId")
                    ?: optionalGetter(value, "getPid")
                )?.toString(),
            "raw" to value.toString(),
        )
    }

    /** 停掉 BLE 扫描。没在扫时调用也安全——每条退出路径都会调它。*/
    private fun stopBleScan() {
        if (bleScanner == null) return
        bleScanner = null
        // ⚠️ **不清 `bleScanned`**：用户点了某一台之后页面就会停扫，紧接着要用那个
        // bean 去查列表、去配网。清掉等于自己把下一步的入参删了。它只在下一轮扫描
        // 开始时被新结果覆盖，条目数也就是附近设备数，不会无限涨。
        runCatching { invoke(bleOperator(), "stopLeScan") }.onFailure { cause ->
            Log.w(TUYA_LOG_TAG, "stopLeScan 失败：${cause.javaClass.simpleName}")
        }
    }

    private fun bleScanType(name: String): Any {
        val clazz = firstClass("com.thingclips.smart.android.ble.api.ScanType")
        val constants = (clazz.enumConstants ?: emptyArray()).filterIsInstance<Enum<*>>()
        return constants.firstOrNull { it.name == name }
            ?: throw IllegalStateException(
                "SDK 的 ScanType 没有 $name，可用：" +
                    constants.joinToString { it.name }.ifEmpty { "无" },
            )
    }

    /**
     * `ScanDeviceBean` → Dart。
     *
     * `supportWifiList` 是这条路的关键：只有 `flag` 的 `CombosFlagCapability.SCAN_WIFI`
     * 位置位，设备才愿意把自己扫到的 Wi-Fi 列表报上来（固件 TuyaOS ≥ 3.6.1）。
     *
     * 读不到那个常量时按 **false** 报：宁可回落到手机的 Wi-Fi 扫描，也不要拿一个猜出来
     * 的能力位去调 [bleQueryDeviceWifi]、然后让用户干等一次超时。
     */
    private fun bleDeviceMap(bean: Any): Map<String, Any?> {
        val flag = (optionalGetter(bean, "getFlag") as? Number)?.toInt() ?: 0
        return mapOf(
            "type" to "bleDevice",
            "seq" to bleCallbackCount.incrementAndGet(),
            "id" to optionalGetter(bean, "getId")?.toString(),
            "name" to optionalGetter(bean, "getName")?.toString(),
            "mac" to optionalGetter(bean, "getMac")?.toString(),
            // address 和 mac 是两个字段，**分开报**：双模配网真正拿去连的是 address，
            // 之前把两者合并成一个，address 为空时看不出来。
            "address" to optionalGetter(bean, "getAddress")?.toString(),
            "uuid" to optionalGetter(bean, "getUuid")?.toString(),
            "productId" to optionalGetter(bean, "getProductId")?.toString(),
            "configType" to optionalGetter(bean, "getConfigType")?.toString(),
            "providerName" to optionalGetter(bean, "getProviderName")?.toString(),
            "data" to optionalGetter(bean, "getData")?.toString(),
            "deviceType" to ((optionalGetter(bean, "getDeviceType") as? Number)?.toInt() ?: 0),
            "bound" to (optionalGetter(bean, "getIsbind") as? Boolean ?: false),
            "share" to (optionalGetter(bean, "isShare") as? Boolean ?: false),
            "roam" to (optionalGetter(bean, "isRoam") as? Boolean ?: false),
            "rssi" to ((optionalGetter(bean, "getRssi") as? Number)?.toInt() ?: 0),
            "flag" to flag,
            "supportWifiList" to bleSupportsWifiList(flag),
            // ⚠️ **原样的 `toString()` 一定要带上**：上面这些 getter 是按常见写法猜的，
            // 万一这一版 SDK 的字段名不一样，全都会读成 null 而页面上看不出为什么。
            // 有了 raw，真机上一眼能看到 SDK 到底给了什么。
            "raw" to runCatching { bean.toString() }.getOrElse { "(toString 失败)" },
        )
    }

    /** 本轮 `onResult` 被回调了多少次——**包括我们没能解析的那些**。*/
    private val bleCallbackCount = java.util.concurrent.atomic.AtomicInteger(0)

    private fun bleSupportsWifiList(flag: Int): Boolean = runCatching {
        val clazz = firstClass("com.thingclips.smart.android.ble.api.CombosFlagCapability")
        val bit = clazz.getField("SCAN_WIFI").getInt(null)
        clazz.getMethod(
            "isCapabilityEnable",
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
        ).invoke(null, flag, bit) as? Boolean ?: false
    }.getOrElse { false }

    /**
     * **双模第②步：问设备要它自己扫到的 Wi-Fi 列表。**
     *
     * `IMultiModeActivator.queryDeviceConfigState(MultiModeQueryBuilder, IThingResultCallback)`
     * ——builder 直接吃 BLE 扫到的那个 `ScanDeviceBean`，SDK 据此**建立本地蓝牙连接**再问
     * 设备要列表。两个好处都不是锦上添花：
     *
     * 1. **绕开 Android 的 Wi-Fi 扫描配额**（前台每 2 分钟 4 次 `startScan`）——「搜索不
     *    及时」的根就在那里；
     * 2. **列出来的是设备够得着的网络**。手机在客厅扫到的 5G，窗台上的花盆未必收得到；
     *    让用户从手机的列表里挑，挑中一个设备根本连不上的网络是很常见的失败。
     *
     * ⚠️ **不要和 AP 那个同名方法搞混。** `IThingOptimizedActivator.queryDeviceConfigState(
     * ApQueryBuilder, …)` 是「热点配网新流程」那一条，前提是 SDK 自己去连 **Wi-Fi 热点**，
     * 2026-09-11 真机判死（跑满 45 秒 `207220`，手机始终在路由器上）、整条删掉了。这里这个
     * 是 `MultiModeQueryBuilder`，走的是**蓝牙**，两件事只是重名。
     *
     * ⚠️ 前提是这台设备的 `supportWifiList` 为 true（固件 TuyaOS ≥ 3.6.1）。
     */
    private fun bleQueryDeviceWifi(call: MethodCall, result: MethodChannel.Result) {
        val uuid = call.argument<String>("uuid").orEmpty()
        if (uuid.isEmpty()) {
            error(result, "ble_uuid_required", "查设备 Wi-Fi 列表必须给 BLE 扫到的 uuid")
            return
        }
        val bean = scannedBean(uuid)
        withHome(result) { home ->
            val builder = firstClass(
                "com.thingclips.smart.sdk.bean.MultiModeQueryBuilder\$Builder",
            ).getDeclaredConstructor().apply { isAccessible = true }.newInstance()
            invoke(builder, "setHomeId", home)
            invoke(builder, "setTimeout", call.argument<Number>("timeoutMs")?.toLong() ?: 30_000L)
            invoke(builder, "setScanDeviceBean", bean)
            val query = invoke(builder, "build")
                ?: throw IllegalStateException("MultiModeQueryBuilder.build() 返回空")
            trace("ble wifi: queryDeviceConfigState(uuid=$uuid, home=$home)")
            invokeWithCallback(
                multiModeActivator(),
                "queryDeviceConfigState",
                query,
                onSuccess = { value ->
                    onMain(result) {
                        val list = bleWifiList(value)
                        trace("ble wifi: 设备报回 ${list.size} 个网络")
                        success(result, list)
                    }
                },
                onError = { code, message ->
                    trace("ble wifi: 失败 $code $message")
                    error(result, code, message)
                },
            )
        }
    }

    /**
     * **双模第③步：把路由器凭据经蓝牙交给设备。**
     *
     * `IMultiModeActivator.startActivator(MultiModeActivatorBean, IMultiModeActivatorListener)`。
     *
     * 这一步是整条双模路径真正的收益所在：**全程不碰设备的 Wi-Fi 热点**，于是
     *
     * - 不需要 `WifiNetworkSpecifier` ⇒ **Android 10+ 那个系统入网授权框彻底没有了**；
     * - 不需要先把手机切到一个没有外网的热点上 ⇒ 不用绑进程网络、不用事后还原；
     * - 不需要 Wi-Fi 扫描拿到确切热点名 ⇒ 配额与发现速度彻底脱钩。
     *
     * 令牌照旧要在**还连着路由器**时取好（`prepareActivatorToken`）：它走云端。
     */
    private fun pairBleDevice(call: MethodCall, rawResult: MethodChannel.Result) {
        val uuid = call.argument<String>("uuid").orEmpty()
        if (uuid.isEmpty()) {
            error(rawResult, "ble_uuid_required", "双模配网必须给 BLE 扫到的 uuid")
            return
        }
        val bean = scannedBean(uuid)
        if (pairingResult != null) releasePairing("pair_cancelled", "被新的配网请求取代")
        val result = PairingResult(rawResult)
        pairingResult = result
        val token = freshActivatorToken()
        if (token != null) {
            startMultiModeActivator(call, result, uuid, bean, token)
            return
        }
        withHome(result) { id ->
            fetchActivatorToken(id, result) { fresh ->
                startMultiModeActivator(call, result, uuid, bean, fresh)
            }
        }
    }

    private fun startMultiModeActivator(
        call: MethodCall,
        result: MethodChannel.Result,
        uuid: String,
        bean: Any,
        token: String,
    ) = withHome(result) { home ->
        // ⚠️ **先把家庭详情同步下来再配网**，否则 SDK 内部缓存是空的、`startActivator`
        // 当场 NPE（2026-09-11 真机 `pqppqpd.bdpdqbp:21`）。见 [withHomeDetail]。
        withHomeDetail(home, result) {
            startMultiModeActivatorWithHome(call, result, uuid, bean, token, home)
        }
    }

    /** 并行配网器实例；`stopConfigWifi` 还要用它，造一次就留着。*/
    private var parallelActivator: Any? = null

    /**
     * **双模配网（并行配网器）——涂鸦推荐的那条路。**
     *
     * `IMultiModeParallelActivator`：`config(MultiModeActivatorConfig)` →
     * `appendDevice(ScanDeviceBean)` → `addMultiModeParallelListener(…)` → `startConfigWifi()`。
     *
     * ⚠️ **为什么换成它**：2026-09-11 真机上 `IMultiModeActivator.startActivator(bean, …)`
     * 一调就在 SDK 内部炸 `NullPointerException @ pqppqpd.bdpdqbp:21`。那条路要我们**手工拼出
     * 整个 `MultiModeActivatorBean`**（二十多个字段），拼漏一项就是一次 NPE，而混淆过的栈帧
     * 根本看不出漏了哪一项。涂鸦的排查建议里反复说的「必须先 `appendDevice` 再 start」，
     * 指的正是这套并行 API——解包核对确认 `appendDevice(ScanDeviceBean)` 真实存在。
     *
     * 这条路**把扫到的 `ScanDeviceBean` 整个交回给 SDK**，字段由它自己取，我们只提供这次
     * 配网才知道的 ssid / 密码 / 令牌 / 家庭。没有手工拼 bean，也就没有拼漏的可能。
     *
     * 拿不到并行配网器时回落到旧的 `startActivator(bean, …)`（[startSingleModeActivator]）。
     */
    private fun startMultiModeActivatorWithHome(
        call: MethodCall,
        result: MethodChannel.Result,
        uuid: String,
        bean: Any,
        token: String,
        home: Long,
    ) {
        val ssid = call.argument<String>("ssid").orEmpty()
        val password = call.argument<String>("password").orEmpty()
        val timeout = call.argument<Number>("timeoutMs")?.toLong() ?: 120_000L
        val parallel = runCatching {
            val api = invokeStatic(sdkClass(), "getActivator")
                ?: throw IllegalStateException("getActivator() 返回空")
            invoke(api, "newMultiModeParallelActivator")
        }.getOrNull()
        if (parallel == null) {
            trace("ble pair: 拿不到并行配网器，回落到 startActivator(bean)")
            startSingleModeActivator(call, result, uuid, bean, token, home)
            return
        }
        parallelActivator = parallel

        val configBuilder = firstClass(
            "com.thingclips.smart.sdk.bean.MultiModeActivatorConfig\$Builder",
        ).getDeclaredConstructor().apply { isAccessible = true }.newInstance()
        invoke(configBuilder, "setSsid", ssid)
        invoke(configBuilder, "setPwd", password)
        invoke(configBuilder, "setToken", token)
        // gid 就是家庭 id。
        invoke(configBuilder, "setGid", home)
        invoke(configBuilder, "setTimeout", timeout)
        val config = invoke(configBuilder, "build")
            ?: throw IllegalStateException("MultiModeActivatorConfig.build() 返回空")

        val listenerClass = firstClass(
            "com.thingclips.smart.sdk.api.IMultiModeParallelListener",
        )
        val loader = listenerClass.classLoader ?: activity.classLoader
        val delivered = AtomicBoolean(false)
        val listener = Proxy.newProxyInstance(loader, arrayOf(listenerClass)) { self, method, args ->
            when (method.name) {
                "equals" -> self === args?.firstOrNull()
                "hashCode" -> System.identityHashCode(self)
                "toString" -> "TuyaParallelListener"
                "onStartConfig" -> {
                    trace("ble pair: onStartConfig " + (args?.firstOrNull() ?: ""))
                    defaultValue(method.returnType)
                }
                "onSuccess" -> {
                    if (delivered.compareAndSet(false, true)) {
                        onMain(result) {
                            stopMultiModeActivator(uuid)
                            // 令牌一次性，留着会让下一次报「令牌过期」。
                            activatorToken = null
                            val device = args?.firstOrNull()
                            if (device == null) {
                                error(result, "pair_failed", "配网未返回设备信息")
                            } else {
                                watchDevice(deviceIdOf(device))
                                success(result, deviceMap(device))
                            }
                        }
                    }
                    defaultValue(method.returnType)
                }
                // `onError(String, String, String)`——三个都是字符串，按位置取：
                // 通常是 (uuid, errorCode, errorMsg)。把三个原样拼进消息，别猜。
                "onError" -> {
                    if (delivered.compareAndSet(false, true)) {
                        val texts = args?.map { it?.toString().orEmpty() }.orEmpty()
                        val code = texts.getOrNull(1).orEmpty().ifEmpty { "ble_pair_failed" }
                        val detail = texts.joinToString(" | ")
                        stopMultiModeActivator(uuid)
                        trace("ble pair: onError " + detail)
                        error(result, code, detail)
                    }
                    defaultValue(method.returnType)
                }
                else -> defaultValue(method.returnType)
            }
        }

        trace(
            "ble pair: 并行配网 config(ssid=" + ssid + ", gid=" + home +
                ", timeout=" + timeout + ", token=" + (if (token.isEmpty()) "(空)" else "有") + ")",
        )
        runCatching {
            invoke(parallel, "config", config)
            invoke(parallel, "addMultiModeParallelListener", listener)
            // ⚠️ **先 appendDevice 再 start**——涂鸦排查建议里反复强调的就是这个顺序。
            // 把扫到的 bean 整个交回去，字段由 SDK 自己取。
            invoke(parallel, "appendDevice", bean)
            invoke(parallel, "startConfigWifi")
        }.onFailure { cause ->
            val real = TuyaSdkInitializer.unwrap(cause)
            val frame = real.stackTrace.firstOrNull { item ->
                item.className.startsWith("com.thingclips") ||
                    item.className.startsWith("com.common")
            }
            val where = if (frame == null) {
                ""
            } else {
                " @ " + frame.className.substringAfterLast('.') +
                    "." + frame.methodName + ":" + frame.lineNumber
            }
            trace("ble pair: 并行配网抛异常 " + real.javaClass.simpleName + where)
            stopMultiModeActivator(uuid)
            error(
                result,
                "ble_start_failed",
                "并行配网调用失败：" + real.javaClass.simpleName +
                    (real.message?.let { ": " + it } ?: "") + where,
            )
        }
    }

    /**
     * 旧路：`IMultiModeActivator.startActivator(MultiModeActivatorBean, …)`。
     *
     * 只在拿不到并行配网器时回落到这里。它要手工拼整个 bean，2026-09-11 真机上就是在这一步
     * 炸的 NPE——留着只是为了不把唯一的路堵死。
     */
    private fun startSingleModeActivator(

        call: MethodCall,
        result: MethodChannel.Result,
        uuid: String,
        bean: Any,
        token: String,
        home: Long,
    ) {
        val beanClass = firstClass("com.thingclips.smart.sdk.bean.MultiModeActivatorBean")
        // ⚠️ **必须用吃 `ScanDeviceBean` 的那个构造函数。**
        //
        // 2026-09-11 真机报 `NullPointerException`（约 6.7 秒后）就是这里：原先用无参构造、
        // 只手填了 8 个字段，而这个 bean 还有 `address` / `mac` / `productId` / `deviceType` /
        // `flag` 全留在 null/0 上——SDK 要拿 `address` 去连那条 BLE 链路，一解引用就炸。
        //
        // `MultiModeActivatorBean(ScanDeviceBean)` 是 SDK 给的正道：扫到的那台是什么，
        // 它自己全抄过去。老版本没有这个构造时退回无参 + 逐字段搬。
        val fromScan = runCatching {
            beanClass.getDeclaredConstructor(bean.javaClass.superclass ?: bean.javaClass)
        }.getOrNull() ?: beanClass.constructors.firstOrNull { ctor ->
            ctor.parameterTypes.size == 1 &&
                ctor.parameterTypes[0].isAssignableFrom(bean.javaClass)
        }
        val activatorBean = if (fromScan != null) {
            fromScan.isAccessible = true
            fromScan.newInstance(bean)
        } else {
            trace("ble pair: ⚠️ 没有 MultiModeActivatorBean(ScanDeviceBean)，退回逐字段搬")
            val created = beanClass.getDeclaredConstructor()
                .apply { isAccessible = true }
                .newInstance()
            // 扫到什么就搬什么——少搬一个就是一次 NPE。
            for (name in listOf(
                "uuid", "address", "mac", "productId", "deviceType", "flag",
            )) {
                runCatching {
                    val field = bean.javaClass.getField(name)
                    field.isAccessible = true
                    setField(created, name, field.get(bean))
                }
            }
            setField(created, "scanDeviceBean", bean)
            created
        }
        // 这几项是这次配网才知道的，构造函数抄不到，必须自己填。
        // （字段是公有裸字段、没有 setter，所以直接写字段。）
        setField(activatorBean, "homeId", home)
        setField(activatorBean, "ssid", call.argument<String>("ssid").orEmpty())
        setField(activatorBean, "pwd", call.argument<String>("password").orEmpty())
        setField(activatorBean, "token", token)
        setField(activatorBean, "timeout", call.argument<Number>("timeoutMs")?.toLong() ?: 120_000L)
        // phase1 = 蓝牙那一段（连上设备、把凭据交过去）；剩下的时间留给设备连路由器 +
        // 注册云端。给蓝牙段单独一个短一点的上限，连不上能快点报出来。
        setField(activatorBean, "phase1Timeout", 30_000L)
        // uuid 以扫到的为准；构造函数没抄到时这一行补上。
        if (readField(activatorBean, "uuid").isNullOrEmpty()) {
            setField(activatorBean, "uuid", uuid)
        }
        // ⚠️ **真机实测（2026-09-11）：这台设备 `mac=''`，真正的蓝牙地址在 `address` 上**
        // （`ScanDeviceBean{... mac='', address='D8:FC:92:F4:89:88' ...}`）。
        // 涂鸦不少代码路径拿的是 `mac`，空着就可能一路走到 NPE。两边互相补齐，谁有就用谁。
        val scannedAddress = readField(activatorBean, "address").orEmpty()
            .ifEmpty { readField(bean, "address").orEmpty() }
        val scannedMac = readField(activatorBean, "mac").orEmpty()
            .ifEmpty { readField(bean, "mac").orEmpty() }
        val resolved = scannedMac.ifEmpty { scannedAddress }
        if (resolved.isNotEmpty()) {
            if (scannedMac.isEmpty()) setField(activatorBean, "mac", resolved)
            if (scannedAddress.isEmpty()) setField(activatorBean, "address", resolved)
        }
        // 同理把扫到的这几项补齐：构造函数没抄到时它们会是 null/0，而 SDK 会用它们
        // 决定走哪条协议分支。
        for (name in listOf("productId", "deviceType", "flag")) {
            if (readField(activatorBean, name).isNullOrEmpty()) {
                runCatching {
                    val field = bean.javaClass.getField(name)
                    field.isAccessible = true
                    setField(activatorBean, name, field.get(bean))
                }
            }
        }
        // **String 字段不留 null**：裸 null 的 String 是最典型的 NPE 来源，空串至少不炸。
        for (name in listOf("countryISOCode", "devId", "ip", "dns", "gateway", "subnetMask")) {
            if (readField(activatorBean, name) == null) {
                runCatching { setField(activatorBean, name, "") }
            }
        }
        // **把真正交给 SDK 的那几项打出来**：再出 NPE 时，一眼能看出是哪一项空着，
        // 而不是对着一个光秃秃的 NullPointerException 猜（`PRODUCT_RULES` §4.1）。
        // ⚠️ 别在插值里再套同种引号（`"…${f(x, "y")}…"`）——那会骗过我们自己的静态
        // 检查器（`tools/kt_dangling_refs.py`），2026-09-11 打包失败也栽在同一类写法上。
        // 先拼成变量，再一次性 trace。
        val probed = listOf("uuid", "address", "mac", "productId", "deviceType")
            .joinToString(", ") { name ->
                name + "=" + (readField(activatorBean, name) ?: "(空)")
            }
        val ssidArg = call.argument<String>("ssid").orEmpty()
        val tokenState = if (token.isEmpty()) "(空)" else "有"
        trace(
            "ble pair: startActivator(home=" + home + ", " + probed +
                ", ssid=" + ssidArg + ", token=" + tokenState + ")",
        )
        // **把真正交给 SDK 的那个 bean 整个打出来。** 上面那串 probed 只挑了几项，
        // 再出 NPE 时想知道的往往是"还有哪一项是 null"——原样的 toString 才答得上。
        trace("ble pair: bean=" + runCatching { activatorBean.toString() }.getOrElse { "(toString 失败)" })
        val listenerClass = firstClass("com.thingclips.smart.sdk.api.IMultiModeActivatorListener")
        val loader = listenerClass.classLoader ?: activity.classLoader
        val delivered = AtomicBoolean(false)
        val listener = Proxy.newProxyInstance(loader, arrayOf(listenerClass)) { self, method, args ->
            when (method.name) {
                "equals" -> self === args?.firstOrNull()
                "hashCode" -> System.identityHashCode(self)
                "toString" -> "TuyaMultiModeListener"
                "onSuccess" -> {
                    if (delivered.compareAndSet(false, true)) {
                        onMain(result) {
                            stopMultiModeActivator(uuid)
                            // 令牌是一次性的，留着会让下一次配网报「令牌过期」。
                            activatorToken = null
                            val device = args?.firstOrNull()
                            if (device == null) {
                                error(result, "pair_failed", "配网未返回设备信息")
                            } else {
                                watchDevice(deviceIdOf(device))
                                success(result, deviceMap(device))
                            }
                        }
                    }
                    defaultValue(method.returnType)
                }
                // `onFailure(int code, String msg, Object handle)`——错误码是 int，
                // 和别处 `onError(String, String)` 的形状不一样，所以不走 callbackProxy。
                "onFailure" -> {
                    if (delivered.compareAndSet(false, true)) {
                        val code = (args?.getOrNull(0) as? Number)?.toInt() ?: -1
                        val message = args?.getOrNull(1)?.toString().orEmpty()
                        stopMultiModeActivator(uuid)
                        trace("ble pair: 失败 $code $message")
                        error(
                            result,
                            code.toString(),
                            message.ifEmpty { "双模配网失败" },
                        )
                    }
                    defaultValue(method.returnType)
                }
                else -> defaultValue(method.returnType)
            }
        }
        // 单独包一层：这样能分清 NPE 是**我们组 bean** 炸的、还是 **SDK 内部** 炸的——
        // 上一轮真机只回了一个光秃秃的 NullPointerException，这两种完全不同的原因
        // 在页面上根本分不开。
        runCatching {
            invoke(multiModeActivator(), "startActivator", activatorBean, listener)
        }.onFailure { cause ->
            val real = TuyaSdkInitializer.unwrap(cause)
            val frame = real.stackTrace.firstOrNull { item ->
                item.className.startsWith("com.thingclips") ||
                    item.className.startsWith("com.common")
            }
            val where = if (frame == null) {
                ""
            } else {
                " @ " + frame.className.substringAfterLast('.') +
                    "." + frame.methodName + ":" + frame.lineNumber
            }
            trace("ble pair: startActivator 抛异常 " + real.javaClass.simpleName + where)
            stopMultiModeActivator(uuid)
            error(
                result,
                "ble_start_failed",
                "调用 SDK 的 startActivator 失败：" +
                    real.javaClass.simpleName +
                    (real.message?.let { ": " + it } ?: "") +
                    where,
            )
        }
    }

    /** 停掉双模配网。没在跑时调用也安全。*/
    /**
     * 停掉双模配网，**并把那条 BLE 链路断干净**。
     *
     * ⚠️ **断开这一步不能省，它直接决定设备还能不能被再次扫到。**
     *
     * BLE 外设**在连接状态下会停止广播**。配网一旦连上设备、中途又失败了，如果我们不
     * 显式断开，设备就一直挂在这条连接上、不再发广播——下一轮扫描当然什么都扫不到。
     * 2026-09-11 真机「之前搜得到、配网失败之后就搜不到了」正是这个（另一半原因是设备
     * 静置会退出配网状态，那一半只能靠断电重启）。
     *
     * 改之前这里只调 `stopActivator`，链路留着没人管。
     */
    private fun stopMultiModeActivator(uuid: String) {
        // 并行配网器（现在的主路）：`stopConfigWifi` + 把这台从队列里摘掉。
        parallelActivator?.let { activator ->
            runCatching { invoke(activator, "stopConfigWifi") }.onFailure { cause ->
                Log.w(TUYA_LOG_TAG, "stopConfigWifi 失败：${cause.javaClass.simpleName}")
            }
            if (uuid.isNotEmpty()) {
                runCatching { invoke(activator, "removeDevice", uuid) }
            }
        }
        // 旧路（回落用）：两条各自有自己的配网器，停一个不影响另一个。
        multiModeActivator?.let { activator ->
            runCatching { invoke(activator, "stopActivator", uuid) }.onFailure { cause ->
                Log.w(TUYA_LOG_TAG, "stopActivator 失败：${cause.javaClass.simpleName}")
            }
        }
        disconnectBleDevice(uuid)
    }

    /**
     * 主动断开与某台设备的 BLE 连接，让它回到广播状态。
     *
     * uuid 为空时**把所有的都断掉**——退出配网动线时用，那一刻我们不该再占着任何一条。
     */
    private fun disconnectBleDevice(uuid: String) {
        val operator = runCatching { bleOperator() }.getOrNull() ?: return
        if (uuid.isNotEmpty()) {
            runCatching { invoke(operator, "disconnectBleDevice", uuid) }
                .onSuccess { trace("ble: 已断开 $uuid（断开后设备才会重新广播）") }
                .onFailure { cause ->
                    Log.w(TUYA_LOG_TAG, "disconnectBleDevice 失败：${cause.javaClass.simpleName}")
                }
            return
        }
        // 全断：SDK 的管理器上有一把总开关，没有就逐个断本轮扫到的。
        val manager = runCatching { invokeStatic(sdkClass(), "getBleManager") }.getOrNull()
        val all = manager?.let {
            runCatching { invoke(it, "disconnectAllBleDevices") }.isSuccess
        } ?: false
        if (!all) {
            bleScanned.keys.toList().forEach { id ->
                runCatching { invoke(operator, "disconnectBleDevice", id) }
            }
        }
        trace("ble: 已断开全部连接")
    }

    /**
     * 写一个公有裸字段，找不到就退回同名 setter。
     *
     * 涂鸦这几个 Bean 是「公有字段 + 少量 getter」的写法，`MultiModeActivatorBean` 连
     * setter 都没有，只能直接写字段。
     */
    /** 读一个公有裸字段，读不到就返回 null。只用于诊断打印。*/
    private fun readField(target: Any, name: String): String? = runCatching {
        val field = target.javaClass.getField(name)
        field.isAccessible = true
        field.get(target)?.toString()
    }.getOrNull()

    private fun setField(target: Any, name: String, value: Any?) {
        val field = runCatching { target.javaClass.getField(name) }
            .recoverCatching { target.javaClass.getDeclaredField(name) }
            .getOrNull()
        if (field != null) {
            field.isAccessible = true
            field.set(target, value)
            return
        }
        val setter = "set" + name.replaceFirstChar { it.uppercaseChar() }
        invoke(target, setter, value)
    }

    /**
     * 把设备报回来的 Wi-Fi 列表折成 Dart 认得的形状。
     *
     * 认不出字段时**把原样 `toString()` 一并带上**（`raw`）：真机上一眼就能看出这一版
     * SDK 到底给的是什么 bean，比在这里猜字段名快得多。
     */
    private fun bleWifiList(value: Any?): List<Map<String, Any?>> {
        val items = when (value) {
            null -> emptyList<Any?>()
            is List<*> -> value
            is Array<*> -> value.toList()
            else -> listOf(value)
        }
        return items.filterNotNull().map { item ->
            if (item is CharSequence) {
                mapOf("ssid" to item.toString(), "rssi" to 0, "sec" to 0, "raw" to item.toString())
            } else {
                mapOf(
                    "ssid" to (optionalGetter(item, "getSsid") ?: optionalGetter(item, "getName"))
                        ?.toString().orEmpty(),
                    "rssi" to ((optionalGetter(item, "getRssi") as? Number)?.toInt() ?: 0),
                    "sec" to ((optionalGetter(item, "getSec") as? Number)?.toInt() ?: 0),
                    "raw" to item.toString(),
                )
            }
        }
    }

    private fun currentUser(result: MethodChannel.Result) {
        val userApi = userInstance()
        val loggedIn = runCatching { invoke(userApi, "isLogin") as? Boolean }.getOrNull() ?: false
        if (!loggedIn) {
            result.success(null)
            return
        }
        val user = runCatching { invoke(userApi, "getUser") }.getOrNull()
        result.success(user?.let(::userMap))
    }

    private fun sendCode(call: MethodCall, result: MethodChannel.Result) {
        invokeWithCallback(
            userInstance(),
            "sendVerifyCodeWithUserName",
            call.argument<String>("account").orEmpty(),
            "",
            call.argument<String>("countryCode").orEmpty(),
            call.argument<Int>("type") ?: 2,
            onSuccess = { success(result, null) },
            onError = { code, message -> error(result, code, message) },
        )
    }

    private fun login(call: MethodCall, result: MethodChannel.Result) {
        val email = call.argument<Boolean>("email") ?: false
        val codeLogin = call.argument<Boolean>("verificationCode") ?: false
        val method = when {
            email -> "loginWithEmail"
            codeLogin -> "loginWithPhone"
            else -> "loginWithPhonePassword"
        }
        invokeWithCallback(
            userInstance(),
            method,
            call.argument<String>("countryCode").orEmpty(),
            call.argument<String>("account").orEmpty(),
            call.argument<String>("credential").orEmpty(),
            onSuccess = { value -> success(result, value?.let(::userMap)) },
            onError = { code, message -> error(result, code, message) },
        )
    }

    /**
     * 自有账号体系登录：APP 后端下发内部编号与配套密码，涂鸦侧据此登录，
     * 账号不存在时自动注册。
     *
     * 方法名以及是否带 createHome 参数在各 SDK 版本之间有差异，所以按候选
     * 组合逐个探测，取第一个签名匹配得上的，避免写死某一版的签名。
     */
    private fun loginWithUid(call: MethodCall, result: MethodChannel.Result) {
        val user = userInstance()
        val countryCode = call.argument<String>("countryCode").orEmpty()
        val uid = call.argument<String>("uid").orEmpty()
        val password = call.argument<String>("password").orEmpty()
        val argumentSets = listOf(
            arrayOf<Any?>(countryCode, uid, password, true),
            arrayOf<Any?>(countryCode, uid, password),
        )
        for (name in listOf("loginOrRegisterWithUid", "loginOrRegisterByUid")) {
            for (args in argumentSets) {
                if (optionalCallbackMethod(user.javaClass, name, args) == null) continue
                invokeWithCallback(
                    user,
                    name,
                    *args,
                    onSuccess = { value -> success(result, value?.let(::userMap)) },
                    onError = { code, message -> error(result, code, message) },
                )
                return
            }
        }
        error(result, "uid_login_unsupported", "当前涂鸦 SDK 不支持 uid 登录")
    }

    private fun register(call: MethodCall, result: MethodChannel.Result) {
        val email = call.argument<Boolean>("email") ?: false
        invokeWithCallback(
            userInstance(),
            if (email) "registerAccountWithEmail" else "registerAccountWithPhone",
            call.argument<String>("countryCode").orEmpty(),
            call.argument<String>("account").orEmpty(),
            call.argument<String>("password").orEmpty(),
            call.argument<String>("code").orEmpty(),
            onSuccess = { value -> success(result, value?.let(::userMap)) },
            onError = { code, message -> error(result, code, message) },
        )
    }

    private fun resetPassword(call: MethodCall, result: MethodChannel.Result) {
        val email = call.argument<Boolean>("email") ?: false
        invokeWithCallback(
            userInstance(),
            if (email) "resetEmailPassword" else "resetPhonePassword",
            call.argument<String>("countryCode").orEmpty(),
            call.argument<String>("account").orEmpty(),
            call.argument<String>("code").orEmpty(),
            call.argument<String>("newPassword").orEmpty(),
            onSuccess = { success(result, null) },
            onError = { code, message -> error(result, code, message) },
        )
    }

    private fun updateNickname(call: MethodCall, result: MethodChannel.Result) {
        invokeWithCallback(
            userInstance(),
            "updateNickName",
            call.argument<String>("nickname").orEmpty(),
            onSuccess = { success(result, null) },
            onError = { code, message -> error(result, code, message) },
        )
    }

    /**
     * `logout` takes ILogoutCallback while `cancelAccount` takes
     * IResultCallback; the proxy type is read from the resolved method so both
     * keep working from one call site.
     */
    private fun userAction(method: String, result: MethodChannel.Result) {
        invokeWithCallback(
            userInstance(),
            method,
            onSuccess = {
                // The devices belong to the account that is going away.
                activity.runOnUiThread {
                    releaseDeviceListeners()
                    homeId = null
                }
                success(result, null)
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    private fun withHome(result: MethodChannel.Result, ready: (Long) -> Unit) {
        homeId?.let {
            ready(it)
            return
        }
        queryHome(result, retry = true, ready = ready)
    }

    /**
     * 查家庭并挑一个。空列表有三种处置，按危险程度排：
     *
     * 1. 进程正绑在设备热点上（AP 配网中）——这条链路根本没有外网，此时的空列表
     *    说明不了「账号下没有家庭」，据此建家会给账号留下一个永久的空家庭，下次
     *    登录挑到它就是「设备全没了」。直接报错，让上层先连回路由器。
     * 2. 还有重试机会——再查一次，挡掉一次瞬时的空返回。
     * 3. 两次都空，且手机在正常网络上——才认为这个账号确实还没有家庭，建一个。
     */
    private fun queryHome(
        result: MethodChannel.Result,
        retry: Boolean,
        ready: (Long) -> Unit,
    ) {
        val manager = invokeStatic(sdkClass(), "getHomeManagerInstance")
            ?: throw IllegalStateException("无法获取家庭管理实例")
        invokeWithCallback(
            manager,
            "queryHomeList",
            onSuccess = { value ->
                onMain(result) {
                    val homes = (value as? List<*>).orEmpty().filterNotNull()
                    val picked = pickHome(homes)
                    when {
                        picked != null -> {
                            homeId = picked
                            ready(picked)
                        }
                        boundNetwork != null -> {
                            Log.i(TUYA_LOG_TAG, "home list empty while bound to device hotspot")
                            error(
                                result,
                                "home_offline",
                                "手机正连着设备热点，暂时读不到家庭列表，请先连回可上网的 Wi-Fi 再试",
                            )
                        }
                        retry -> {
                            Log.i(TUYA_LOG_TAG, "home list came back empty, retrying once")
                            queryHome(result, retry = false, ready = ready)
                        }
                        else -> createHome(manager, result, ready)
                    }
                }
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    /**
     * 账号名下有多个家庭时选哪一个。
     *
     * `queryHomeList` 的返回顺序在两次登录之间并不保证一致，原来直接取第一个：
     * 同一个账号这次登录读到 A 家的设备，下次登录可能读到 B 家（B 家往往是本
     * 地缓存为空时自动建出来的空家），用户看到的就是「重新登录后设备全没了」。
     *
     * 改成稳定规则：先挑带设备的家庭，同样带设备时取 homeId 最小的那个（最早
     * 建的通常就是设备所在的家庭）。这样每次登录选到的都是同一个家庭。
     */
    private fun pickHome(homes: List<*>): Long? {
        val tag = homeTag
        val ranked = homes.mapNotNull { bean ->
            if (bean == null) return@mapNotNull null
            val id = runCatching { number(getter(bean, "getHomeId")) }.getOrNull()
                ?: return@mapNotNull null
            val name = optionalGetter(bean, "getName")?.toString().orEmpty()
            val devices = (optionalGetter(bean, "getDeviceList") as? List<*>)?.size ?: 0
            HomeChoice(id, name, devices)
        }
        if (ranked.isEmpty()) return null
        // 名字对上本账号标记的排最前，其次带设备的，最后按 homeId 从小到大——
        // 前两项都平手时也要有个稳定顺序，否则又回到「每次登录挑到不同家庭」。
        val picked = ranked.sortedWith(
            compareByDescending<HomeChoice> { tag != null && it.name == tag }
                .thenByDescending { it.devices }
                .thenBy { it.id },
        ).first()
        Log.i(
            TUYA_LOG_TAG,
            "home picked ${picked.id} (name=${picked.name}, ${picked.devices} devices) " +
                "of ${ranked.size} homes, tag=$tag",
        )
        return picked.id
    }

    private data class HomeChoice(val id: Long, val name: String, val devices: Int)

    private fun createHome(manager: Any, result: MethodChannel.Result, ready: (Long) -> Unit) {
        invokeWithCallback(
            manager,
            "createHome",
            // 用本账号的标记当家庭名，下次登录就能按名字把它认回来。
            homeTag ?: "我的花园",
            0.0,
            0.0,
            "",
            emptyList<String>(),
            onSuccess = { value ->
                onMain(result) {
                    if (value == null) {
                        error(result, "home_missing", "创建家庭未返回家庭信息")
                    } else {
                        val id = number(getter(value, "getHomeId"))
                        homeId = id
                        ready(id)
                    }
                }
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    /** 本进程里已经拉过 `getHomeDetail` 的家庭。*/
    private val homeDetailLoaded = java.util.Collections.synchronizedSet(mutableSetOf<Long>())

    /**
     * **确保这个家庭的详情已经同步到 SDK，再往下走。**
     *
     * ⚠️ 这一步是 2026-09-11 真机那个 NPE 的正解：
     * `NullPointerException @ pqppqpd.bdpdqbp:21 (ble_start_failed)`——混淆后的类名说明
     * 炸在**涂鸦 SDK 内部**，就在我们调 `startActivator` 的那一瞬间。
     *
     * 原因：`withHome` 只负责**拿到 homeId**（Dart 侧会话开始时 `setHomeId` 钉进来的），
     * 全程没有调过 `getHomeDetail`；而 SDK 的配网器要从**家庭缓存**里取东西。App 重启后
     * 直接进搜索页配网，那份缓存还是空的，一解引用就 NPE。涂鸦给的排查第三条
     * 「App 重启后未先调用 homedetail 接口同步网关数据」说的正是它。
     *
     * 之所以以前 AP 配网没暴露：走 AP 的用户通常先进过设备列表（`getDevices` 会调
     * `getHomeDetail`），缓存顺带就热了。蓝牙这条动线可以完全不经过设备列表。
     *
     * 每个家庭每进程只拉一次；失败**不拦路**（照常往下走，让真正的配网错误来说话）。
     */
    private fun withHomeDetail(
        id: Long,
        result: MethodChannel.Result,
        ready: () -> Unit,
    ) {
        if (homeDetailLoaded.contains(id)) {
            ready()
            return
        }
        val home = runCatching { invokeStatic(sdkClass(), "newHomeInstance", id) }.getOrNull()
        if (home == null) {
            trace("home detail: 拿不到家庭实例，跳过同步")
            ready()
            return
        }
        trace("home detail: 同步家庭 " + id + " …（配网前必须先热一次 SDK 缓存）")
        runCatching {
            invokeWithCallback(
                home,
                "getHomeDetail",
                onSuccess = {
                    homeDetailLoaded.add(id)
                    trace("home detail: 同步完成")
                    onMain(result) { ready() }
                },
                onError = { code, message ->
                    // 不拦路：同步失败也让配网自己去报真正的错，别把两件事混成一个。
                    trace("home detail: 同步失败 " + code + " " + message + "（不拦路）")
                    onMain(result) { ready() }
                },
            )
        }.onFailure { cause ->
            trace("home detail: 调用失败 " + cause.javaClass.simpleName + "（不拦路）")
            ready()
        }
    }

    private fun loadHomeDevices(id: Long, result: MethodChannel.Result) {
        val home = invokeStatic(sdkClass(), "newHomeInstance", id)
            ?: throw IllegalStateException("无法创建家庭实例")
        invokeWithCallback(
            home,
            "getHomeDetail",
            onSuccess = { value ->
                homeDetailLoaded.add(id)
                onMain(result) {
                    val devices =
                        value?.let { optionalGetter(it, "getDeviceList") } as? List<*>
                    val beans = devices.orEmpty().filterNotNull()
                    // The snapshot below is a point in time; the listeners are
                    // what keep it current afterwards.
                    watchDevices(beans.map(::deviceIdOf))
                    success(result, beans.map(::deviceMap))
                }
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    /**
     * Fetches a provisioning token and caches it, without starting anything.
     *
     * AP mode needs this as its own step. Once the phone joins the device's
     * hotspot it has no route to the internet, so a token fetch made at
     * "start pairing" time fails with the SDK's `Network error please try it
     * again` — the token has to be obtained while the phone is still on the
     * router.
     */
    private fun prepareActivatorToken(result: MethodChannel.Result) {
        // 取令牌要走云端。没有配网在跑却还绑着网络，只能是上一次失败留下的——
        // 绑着的那个热点早就没了，不解开这次取令牌必然无网失败。
        if (activator == null && boundNetwork != null) {
            Log.i(TUYA_LOG_TAG, "token fetch: dropping stale network binding")
            unbindProcessNetwork()
        }
        withHome(result) { id ->
            fetchActivatorToken(id, result) { success(result, null) }
        }
    }

    private fun fetchActivatorToken(
        homeId: Long,
        result: MethodChannel.Result,
        onReady: (String) -> Unit,
    ) {
        val activatorApi = invokeStatic(sdkClass(), "getActivatorInstance")
            ?: throw IllegalStateException("无法获取配网实例")
        invokeWithCallback(
            activatorApi,
            "getActivatorToken",
            homeId,
            onSuccess = { value ->
                onMain(result) {
                    val token = value?.toString().orEmpty()
                    if (token.isEmpty()) {
                        error(result, "pair_failed", "云端未返回配网令牌")
                    } else {
                        activatorToken = token
                        activatorTokenAt = System.currentTimeMillis()
                        onReady(token)
                    }
                }
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    /** The cached token while it is still inside [ACTIVATOR_TOKEN_TTL_MS]. */
    private fun freshActivatorToken(): String? {
        val token = activatorToken ?: return null
        val age = System.currentTimeMillis() - activatorTokenAt
        return token.takeIf { age in 0..ACTIVATOR_TOKEN_TTL_MS }
    }

    private fun pairWifi(call: MethodCall, rawResult: MethodChannel.Result) {
        // 上一次配网还没回话就又来了一次（正常被 Dart 的 busy 锁挡住；取消后立刻
        // 重试时可能发生）：先把旧的了结，别让它的 Future 永远挂着。
        // 注意这一步只在还有旧配网在跑时才会动网络绑定；下面的注释说明为什么
        // 正常路径上不能碰它。
        if (pairingResult != null) releasePairing("pair_cancelled", "被新的配网请求取代")
        val result = PairingResult(rawResult)
        pairingResult = result
        // 这里**不能**清理网络绑定：joinDeviceHotspot 刚把手机连上设备热点，而那条
        // 连接是跟着 NetworkCallback 走的，一旦 unregister 系统立刻断开——凭据就再
        // 也发不到设备，只能等满 120 秒报 1006。上一次遗留的绑定由
        // joinDeviceHotspot 自己在发起新请求前清理，配网结束由 PairingResult 清理。
        // 复用预取的令牌——AP 配网能成立全靠这一步：跑到这里时手机已经连在设备
        // 热点上，云端不可达。EZ 全程连在路由器上，走的就是下面这条回落路径，
        // 所以 EZ 不需要用户先点「获取配网令牌」。
        freshActivatorToken()?.let { token ->
            startActivator(call, result, token)
            return
        }
        withHome(result) { id ->
            fetchActivatorToken(id, result) { token ->
                startActivator(call, result, token)
            }
        }
    }

    private fun startActivator(call: MethodCall, result: MethodChannel.Result, token: String) {
        val activatorApi = invokeStatic(sdkClass(), "getActivatorInstance")
            ?: throw IllegalStateException("无法获取配网实例")
        // The builder's fully-qualified name is not hard-coded: Tuya has moved
        // it between packages across 7.x, and a stale name here fails as a bare
        // ClassNotFoundException that says nothing about the real cause. The
        // factory method takes the builder as its only argument, so the type is
        // read off that signature instead — the same trick invokeWithCallback
        // already uses for callback interfaces.
        val factory = activatorFactory(activatorApi)
        val builderClass = factory.parameterTypes.single()
        val builder = builderClass.getDeclaredConstructor()
            .apply { isAccessible = true }
            .newInstance()
        val mode = activatorMode(builder, AP_MODE_NAMES)
        invoke(builder, "setContext", activity)
        invoke(builder, "setSsid", call.argument<String>("ssid").orEmpty())
        invoke(builder, "setPassword", call.argument<String>("password").orEmpty())
        invoke(builder, "setActivatorModel", mode)
        invoke(builder, "setTimeOut", 120L)
        invoke(builder, "setToken", token)
        // 这台机器上 adb 未必连得上，所以诊断信息不能只进 logcat——失败时一并
        // 回给 Dart，联调页的日志区才看得到实际用了哪个工厂、哪个枚举常量。
        val used = "ap/${factory.name}/${(mode as Enum<*>).name}"
        Log.i(TUYA_LOG_TAG, "pairing $used")
        invokeWithCallback(
            builder,
            "setListener",
            onSuccess = { value ->
                onMain(result) {
                    stopActivator()
                    // Tokens are single-use; keeping this one would make the
                    // next pairing attempt fail with a stale-token error.
                    activatorToken = null
                    if (value == null) {
                        error(result, "pair_failed", "配网未返回设备信息")
                    } else {
                        watchDevice(deviceIdOf(value))
                        success(result, deviceMap(value))
                    }
                }
            },
            onError = { code, message ->
                stopActivator()
                error(result, code, "$message · $used")
            },
        )
        activator = factory.invoke(activatorApi, builder)
            ?: throw IllegalStateException("${factory.name} 未返回配网实例")
        // AP 要把进程绑到 Wi-Fi 上：手机连的设备热点没有互联网，不绑定的话流量会被
        // 系统留在移动数据上，凭据就发不到设备。
        //
        // 这里**不再按 mode 判断**：AP 已是唯一的配网模式（EZ 实测不支持、已删），
        // 原来那句 `if (requested == "ap")` 在只剩 AP 之后恒真，而且万一 Dart 侧漏传
        // mode，它会静默跳过绑定——留着是个陷阱。
        // （历史背景：EZ 是往手机所在网络广播凭据，绑死 Network 会挡住广播，这正是当年
        // EZ 加了绑定之后开始报 1006 的原因，所以当时才要按模式区分。）
        //
        // joinDeviceHotspot 已经绑好时不要重绑：那条绑定指向的正是设备热点，而这里
        // 是从 allNetworks 里挑第一个 Wi-Fi，很可能挑中路由器，反而把凭据发错地方。
        if (boundNetwork == null) {
            val bound = bindProcessToWifi()
            Log.i(TUYA_LOG_TAG, "AP pairing: process bound to Wi-Fi = $bound")
        } else {
            Log.i(TUYA_LOG_TAG, "AP pairing: reusing hotspot binding")
        }
        invoke(activator!!, "start")
    }

    /**
     * `IThingActivator` 上的配网工厂，按模式选。
     *
     * 7.5.1 为 EZ 单独提供了 `newEZWifiConfigDevActivator(ActivatorBuilder)`——参数
     * 类型和通用的 `newActivator` 完全相同，光看签名分不出差别，但那才是 SDK 给
     * EZ 的正式入口。找不到时回落到 `newActivator`，老 SDK 仍能工作。
     *
     * 不用 `newMultiActivator`：那是「一次会话配多台」的语义，不保证配上第一台就
     * 回调；它还只实现了 EZ，喂 AP 的 Builder 会在 `start()` 报
     * `Multi Config don't support the AP Mode`。
     *
     * 工厂只接受 Builder 一个参数，[startActivator] 正是据此拿到 Builder 的类型，
     * 不必写死包名。
     */
    private fun activatorFactory(activatorApi: Any): Method {
        val preference = listOf("newActivator")
        val factories = candidates(activatorApi.javaClass).filter { method ->
            method.name in preference &&
                method.parameterTypes.size == 1 &&
                method.parameterTypes.single().simpleName.endsWith("Builder")
        }
        // 按偏好顺序取，而不是反射返回的顺序——后者不保证跨次运行稳定。
        return preference
            .firstNotNullOfOrNull { name -> factories.firstOrNull { it.name == name } }
            ?.apply { isAccessible = true }
            ?: throw NoSuchMethodException(
                "${activatorApi.javaClass.name} 未提供 ${preference.joinToString("/")}" +
                    "(Builder)，该类的工厂方法：" + describeFactories(activatorApi.javaClass),
            )
    }

    /** Signatures of the `new*` methods, so a rename is diagnosable from the log. */
    private fun describeFactories(clazz: Class<*>): String = candidates(clazz)
        .filter { it.name.startsWith("new") }
        .joinToString { method ->
            val params = method.parameterTypes.joinToString { it.simpleName }
            "${method.name}($params)"
        }
        .ifEmpty { "无" }

    /**
     * Resolves the EZ / AP constant from the setter's parameter type, so the
     * enum's package name does not have to be hard-coded either.
     *
     * [modeNames] is a preference list rather than one name: Tuya renamed these
     * constants from `TY_*` to `THING_*` during 7.x (7.5.1 ships only the
     * latter), and the bridge should work against either generation.
     */
    private fun activatorMode(builder: Any, modeNames: List<String>): Any {
        val setter = candidates(builder.javaClass).firstOrNull { method ->
            method.name == "setActivatorModel" &&
                method.parameterTypes.size == 1 &&
                method.parameterTypes.single().isEnum
        } ?: throw NoSuchMethodException(
            "${builder.javaClass.name}.setActivatorModel(枚举) 不存在",
        )
        val constants = (setter.parameterTypes.single().enumConstants ?: emptyArray())
            .filterIsInstance<Enum<*>>()
        return modeNames.firstNotNullOfOrNull { name ->
            constants.firstOrNull { it.name == name }
        } ?: throw IllegalStateException(
            "SDK 未提供配网模式 ${modeNames.joinToString("/")}，可用：" +
                constants.joinToString { it.name }.ifEmpty { "无" },
        )
    }

    /**
     * 由 App 直接连上设备热点，省掉「去系统设置连 Wi-Fi」这一步。
     *
     * Android 10 起应用不能再自己 `enableNetwork` 任意网络，取而代之的是
     * [WifiNetworkSpecifier]：应用描述想连的网络，系统弹一个确认框，用户点一下就
     * 连上——涂鸦官方 App 的 AP 配网没有「请到设置里连接热点」那一步，用的就是它。
     *
     * 这样连上的网络是**进程专属**的，正好是 AP 配网需要的形态：系统默认网络仍留
     * 在有互联网的那一边，而我们在 [onAvailable] 里把进程绑到热点上。所以必须显式
     * 声明 `removeCapability(NET_CAPABILITY_INTERNET)`，否则系统会因为热点上不了网
     * 而判定请求不满足。
     *
     * Android 9 及以下没有这个 API，仍然只能引导用户手动连，Dart 侧据此回落。
     */
    /**
     * 当前连着的 Wi-Fi 名，**只用于日志与失败诊断**，不参与任何判断。
     *
     * `connectionInfo.ssid` 在没有定位权限时会返回 `<unknown ssid>`，所以这里把读不到和
     * 读失败都折成一句人话——诊断串里出现「(读不到)」本身就是一条线索（缺权限），比
     * 一个空字符串有用。**不要拿它的返回值做门禁**：读不到不等于没连上。
     */
    private fun currentSsidForLog(): String = runCatching {
        val wifi = activity.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val ssid = wifi?.connectionInfo?.ssid?.trim('"')
        if (ssid.isNullOrEmpty() || ssid == "<unknown ssid>") "(读不到)" else ssid
    }.getOrElse { "(读失败:${it.message})" }

    private fun joinDeviceHotspot(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            error(
                result,
                "hotspot_join_unsupported",
                "Android 9 及以下无法由应用连接热点，请到系统设置手动连接",
            )
            return
        }
        val manager = activity.getSystemService(ConnectivityManager::class.java)
        if (manager == null) {
            error(result, "hotspot_join_failed", "无法获取网络服务")
            return
        }
        val ssid = call.argument<String>("ssid").orEmpty()
        // ⚠️ **只接受确切的 SSID。**
        //
        // 以前只给前缀时这里走 `setSsidPattern`，那是 `WifiNetworkSpecifier` 的
        // 「按模式搜索」一支：系统会弹出「查找设备…」，扫不到就停在「没有找到任何
        // 设备。请确保要连接的设备已打开并准备好进行连接。」——那是系统 UI，App
        // 关不掉它，只能不触发它。Android 能枚举附近网络，搜索页一定拿得到确切
        // 名字，所以这条路在 Android 上没有存在的必要。
        // （iOS 相反：它列不出附近网络，`NEHotspotConfiguration(ssidPrefix:)` 是
        // 唯一可行的路，那边照常收前缀。）
        if (ssid.isEmpty()) {
            error(
                result,
                "hotspot_ssid_required",
                "还不知道要连哪台设备的热点，请回到「搜索设备」选中设备后再配网",
            )
            return
        }
        val target = ssid
        // 已经持有这条热点连接就直接复用。**这一步决定了系统确认框只会出现一次**：
        // 搜索页连过之后，配网那一步的重试会走到这里并原地返回，不会再发
        // `requestNetwork`、也就不会再弹框。
        if (boundHotspotSsid == target && boundNetwork != null && hotspotCallback != null) {
            trace("join: $target already held, reusing (no dialog)")
            success(result, false)
            return
        }
        // 手机本来就连在这个热点上（系统记住后自动重连的）：什么都不用做，也没有框。
        if (currentSsidForLog() == target) {
            trace("join: phone already on $target (system auto-reconnect), no dialog")
            success(result, false)
            return
        }
        // 连热点**只有这一条路**：`WifiNetworkSpecifier` + `requestNetwork`，系统必弹一次
        // 入网授权框。这不是取舍，是 2026-09-11 涂鸦官方书面确认的结论：
        //
        // > - Android 10+ 第三方 App **无法**通过 `WifiManager#connect()` 静默连接任意热点
        // >   （需 `NETWORK_SETTINGS` 系统权限，**不可申请**）；
        // > - `WifiNetworkSpecifier + requestNetwork()` 是**唯一可行路径**，但强制弹出系统
        // >   授权框（**无绕过方案**）；
        // > - 「SDK 自动连热点」仅适用于 TuyaOS ≥ 3.6.1 固件 + **智能生活 App（预置/白名单
        // >   应用）**，第三方 App 不具备同等能力；
        // > - 文档中「SDK 会在指定时间内自动连接」指**设备端行为**，非手机侧静默连接。
        // >
        // > 因此，对第三方 App 而言，「零系统框」在 Android 10+ 上**技术上不可行**。
        //
        // 配合这条结论，我们真机上跑死过的两条路：
        //
        // 1. `WifiManager.connect(WifiConfiguration, ActionListener)`——方法存在、调用不抛
        //    异常，但 `ActionListener` 一个回调都没来，`addNetwork()` 返回 **-1**；
        // 2. `WifiNetworkSuggestion`——`addNetworkSuggestions` 返回 0 也没用：Android 10 上
        //    首次必须用户在通知栏点同意，且平台只在它判定某建议网络"当前最优"时才连，而设备
        //    热点没有外网、手机正连着有外网的路由器。它是为"凭据先给你，将来遇到再连"设计的，
        //    不是为配网设计的。**已删除**（留着只会在配网关键路径上白等十秒，而设备静置会退出
        //    配网模式，见 §1.5）。要看实现去 git：`747d871`。
        //
        // ⚠️ **不要再尝试这两条路，也不要再以"SDK 会自己连"为由删掉连热点这一步。**
        joinViaSpecifier(target, manager, result)
    }

    /**
     * `WifiNetworkSpecifier` + `requestNetwork`：Android 10+ 上**唯一**能让第三方应用
     * 按需连上一个指定的、没有外网的热点的公开 API。代价是系统必须弹一次入网授权框，
     * 关不掉、不能代点。
     *
     * 产品口径（`PRODUCT_RULES` §1.2）：必须授权就**统一收在搜索页那颗「连接」按钮上**，
     * 只在这一刻出现一次；之后选 Wi-Fi、输密码、配网进度**一个系统框都没有**。手机已经
     * 在该热点上、或我们已持有这条连接时，上面两条捷径会直接跳过，零点击。
     */
    private fun joinViaSpecifier(
        target: String,
        manager: ConnectivityManager,
        result: MethodChannel.Result,
    ) {
        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(target)
            .build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()

        // 连热点之前把上一次可能残留的绑定整个清掉，而不只是热点请求：残留的
        // 进程绑定指向一个已经不在的网络，留着的话新连接建立前 App 一直没网。
        // 此时不可能有配网在跑（Dart 的 busy 锁保证），清理不会打断任何东西。
        unbindProcessNetwork()
        trace("join: requestNetwork($target)，等用户点系统框里的「连接」")
        val answered = AtomicBoolean(false)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val bound = runCatching { manager.bindProcessToNetwork(network) }
                    .getOrDefault(false)
                trace("join: onAvailable，bindProcessToNetwork=$bound，当前「${currentSsidForLog()}」")
                if (!answered.compareAndSet(false, true)) return
                if (bound) {
                    boundNetwork = network
                    boundHotspotSsid = target
                    success(result, true)
                } else {
                    // 连上了却绑不过去，这条连接没有用处：立刻放掉，别让手机挂在
                    // 一个 App 用不了的热点上。
                    activity.runOnUiThread { releaseHotspotRequest() }
                    error(result, "hotspot_bind_failed", "已连上 $target，但进程流量未能切换到热点")
                }
            }

            override fun onUnavailable() {
                // 系统扫不到这个网络时也走这里，和用户点了「取消」无法区分，所以把目标
                // 名字带出去。设备静置久了会退出配网模式、不再广播热点，那时就是这条。
                trace("join: onUnavailable（热点不存在 / 用户取消 / 超时）")
                activity.runOnUiThread { releaseHotspotRequest() }
                if (answered.compareAndSet(false, true)) {
                    error(
                        result,
                        "hotspot_join_cancelled",
                        "未连上 $target：热点不存在（设备可能已退出配网模式，断电重启再试）、" +
                            "系统弹框被取消或超时",
                    )
                }
            }

            override fun onLost(network: Network) {
                if (network == boundNetwork) {
                    trace("join: onLost，释放进程绑定")
                    activity.runOnUiThread { unbindProcessNetwork() }
                }
            }
        }
        hotspotCallback = callback
        // 系统弹框要用户操作，给足时间；超时会走 onUnavailable。
        runCatching { manager.requestNetwork(request, callback, 60_000) }
            .onFailure {
                hotspotCallback = null
                error(result, "hotspot_join_failed", it.message ?: "请求连接热点失败")
            }
    }

    /** 释放热点请求，系统随即断开这条进程专属连接。 */
    private fun releaseHotspotRequest() {
        val manager = activity.getSystemService(ConnectivityManager::class.java)
        hotspotCallback?.let { callback ->
            runCatching { manager?.unregisterNetworkCallback(callback) }
        }
        hotspotCallback = null
    }

    private fun stopActivator() {
        activator?.let { runCatching { invoke(it, "stop") } }
        activator = null
        unbindProcessNetwork()
    }

    /**
     * 把进程流量绑定到 Wi-Fi，AP 配网期间必须做。
     *
     * 手机此刻连的是设备热点，那个网络没有互联网。Android 10 起系统会因此把默认
     * 网络留在移动数据上，App 发出的 socket 根本没走热点，凭据送不到设备——表现
     * 就是等满 120 秒后涂鸦回 `1006 out of time`。绑定后进程流量强制走 Wi-Fi。
     *
     * 绑定必须随热点消失而解除：设备一旦拿到凭据就会关掉热点去连路由器，那个
     * Network 随即失效。继续绑着的话 App 会彻底没网，SDK 拿不到云端的激活确认，
     * 最终同样报 1006——但那时设备其实已经配网成功了，最难判断的就是这种。
     * 所以这里注册回调，热点一 onLost 就立刻解绑，让手机回到路由器上。
     */
    private fun bindProcessToWifi(): Boolean {
        val manager = activity.getSystemService(ConnectivityManager::class.java)
            ?: return false
        val wifi = runCatching {
            @Suppress("DEPRECATION")
            manager.allNetworks.firstOrNull { network ->
                manager.getNetworkCapabilities(network)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            }
        }.getOrNull() ?: return false
        if (!runCatching { manager.bindProcessToNetwork(wifi) }.getOrDefault(false)) {
            return false
        }
        boundNetwork = wifi
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onLost(network: Network) {
                if (network == boundNetwork) {
                    Log.i(TUYA_LOG_TAG, "AP pairing: hotspot lost, releasing network binding")
                    activity.runOnUiThread { unbindProcessNetwork() }
                }
            }
        }
        runCatching {
            manager.registerNetworkCallback(
                NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .build(),
                callback,
            )
            networkCallback = callback
        }
        return true
    }

    private fun unbindProcessNetwork() {
        releaseHotspotRequest()
        boundHotspotSsid = null
        val manager = activity.getSystemService(ConnectivityManager::class.java)
        runCatching { manager?.bindProcessToNetwork(null) }
        networkCallback?.let { callback ->
            runCatching { manager?.unregisterNetworkCallback(callback) }
        }
        networkCallback = null
        boundNetwork = null
    }

    private fun deviceAction(call: MethodCall, result: MethodChannel.Result, method: String) {
        val deviceId = call.argument<String>("deviceId").orEmpty()
        val device = invokeStatic(sdkClass(), "newDeviceInstance", deviceId)
            ?: throw IllegalStateException("无法创建设备实例")
        val unbinds = method == "removeDevice" || method == "resetFactory"
        val onSuccess: (Any?) -> Unit = {
            if (unbinds) activity.runOnUiThread { unwatchDevice(deviceId) }
            success(result, null)
        }
        val onError: (String, String) -> Unit = { code, message -> error(result, code, message) }
        when (method) {
            "publishDps" -> {
                val dps = call.argument<Map<String, Any?>>("dps") ?: emptyMap()
                invokeWithCallback(
                    device,
                    method,
                    JSONObject(dps).toString(),
                    onSuccess = onSuccess,
                    onError = onError,
                )
            }
            "renameDevice" -> invokeWithCallback(
                device,
                method,
                call.argument<String>("name").orEmpty(),
                onSuccess = onSuccess,
                onError = onError,
            )
            else -> invokeWithCallback(device, method, onSuccess = onSuccess, onError = onError)
        }
    }

    private fun createShareLink(call: MethodCall, result: MethodChannel.Result) {
        // Link-based sharing is delivered by the Expansion SDK, whose manager
        // class moved between packages. Nothing is guessed silently: when no
        // known entry point resolves, Dart gets an actionable error instead.
        val managerClass = runCatching {
            firstClass(
                "com.thingclips.smart.extension.device.share.ThingDeviceShareManager",
                "com.thingclips.smart.bizbundle.device.share.ThingDeviceShareManager",
            )
        }.getOrNull()
        if (managerClass == null) {
            error(
                result,
                "share_service_unavailable",
                "当前业务拓展 SDK 未提供设备分享链接能力，请在涂鸦平台开通设备分享后核对接口",
            )
            return
        }
        val manager = managerClass.getDeclaredConstructor().newInstance()
        invokeWithCallback(
            manager,
            "createShareInfo",
            call.argument<String>("deviceId").orEmpty(),
            1,
            homeId ?: 0L,
            0,
            1,
            onSuccess = { value ->
                val link = value?.let { shared ->
                    optionalGetter(shared, "getUrl")?.toString() ?: shared.toString()
                }
                success(result, link.orEmpty())
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    private fun checkFirmware(call: MethodCall, result: MethodChannel.Result) {
        val deviceId = call.argument<String>("deviceId").orEmpty()
        invokeWithCallback(
            otaInstance(deviceId),
            "getOtaInfo",
            onSuccess = { value ->
                val list = (value as? List<*>).orEmpty().filterNotNull()
                // One entry per upgradable component. upgradeStatus 1 is "an
                // update is waiting"; 0 is up to date and 2 is mid-upgrade, so
                // reporting the first entry's version regardless would offer an
                // upgrade that does not exist.
                val statuses = list.map {
                    (optionalGetter(it, "getUpgradeStatus") as? Number)?.toInt()
                }
                val pending = list.zip(statuses).firstOrNull { it.second == 1 }?.first
                    // An SDK drop without the field would otherwise never
                    // offer an upgrade at all; fall back to the old behaviour.
                    ?: list.firstOrNull().takeIf { statuses.all { status -> status == null } }
                // 两个版本号都从同一条记录取：`getVersion` 是待装的新版本，
                // `getCurrentVersion` 是该组件当前跑的版本。分开取会把两个
                // 不同组件的版本号并排显示。
                success(
                    result,
                    pending?.let {
                        mapOf(
                            "version" to optionalGetter(it, "getVersion")?.toString(),
                            "currentVersion" to
                                optionalGetter(it, "getCurrentVersion")?.toString(),
                        )
                    },
                )
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    private fun startFirmwareUpgrade(call: MethodCall, result: MethodChannel.Result) {
        val deviceId = call.argument<String>("deviceId").orEmpty()
        val ota = otaInstance(deviceId)
        // 升级要跑几分钟，方法通道只能回答一次，所以它只回答"已发起"；下载进度
        // 和最终成败改从事件通道推给 Dart。
        val started = AtomicBoolean(false)
        val answerStarted = { if (started.compareAndSet(false, true)) success(result, null) }
        val onSuccess: (Any?) -> Unit = {
            answerStarted()
            emitOta(deviceId, "success")
            // 升级已经结束，SDK 内部的注册可以放了；下次检查会重新建实例。
            activity.runOnUiThread { releaseOta(deviceId) }
        }
        val onError: (String, String) -> Unit = { code, message ->
            // 还没回答过方法调用就失败，说明升级根本没起来，照常回错误；已经
            // 回答过则只能通过事件通道报告。
            if (started.compareAndSet(false, true)) {
                error(result, code, message)
            }
            emitOta(deviceId, "failed", message = message)
            activity.runOnUiThread { releaseOta(deviceId) }
        }
        // 7.x reports progress through a listener and starts with a no-arg call;
        // older builds accept the callback directly on startOta.
        val listenerMethod =
            optionalCallbackMethod(ota.javaClass, "setOtaListener", emptyArray<Any?>())
        if (listenerMethod != null) {
            listenerMethod.invoke(
                ota,
                otaListenerProxy(
                    listenerMethod.parameterTypes.last(),
                    deviceId,
                    onSuccess,
                    onError,
                ),
            )
            invoke(ota, "startOta")
            answerStarted()
            return
        }
        invokeWithCallback(ota, "startOta", onSuccess = onSuccess, onError = onError)
    }

    /**
     * `IThingOtaListener` 的动态代理。
     *
     * 和 [callbackProxy] 的区别只在于它还认 `onProgress(otaType, percent)`——
     * 通用代理会把这个回调丢进默认分支，进度就没了，界面只能干等几分钟。
     * 方法名之外不假设签名：百分比从参数里挑第一个数字，兼容不同的参数顺序。
     */
    private fun otaListenerProxy(
        listenerType: Class<*>,
        deviceId: String,
        onSuccess: (Any?) -> Unit,
        onError: (String, String) -> Unit,
    ): Any {
        val loader = listenerType.classLoader ?: activity.classLoader
        return Proxy.newProxyInstance(loader, arrayOf(listenerType)) { proxy, method, args ->
            when (method.name) {
                "equals" -> proxy === args?.firstOrNull()
                "hashCode" -> System.identityHashCode(proxy)
                "toString" -> "TuyaOtaListener(${listenerType.simpleName})"
                "onProgress" -> {
                    val percent = args?.filterIsInstance<Number>()?.lastOrNull()?.toInt()
                    emitOta(deviceId, "running", percent = percent)
                    defaultValue(method.returnType)
                }
                "onSuccess" -> {
                    onSuccess(args?.firstOrNull())
                    defaultValue(method.returnType)
                }
                "onFailure", "onError" -> {
                    val texts = args?.filterIsInstance<String>().orEmpty()
                    onError(
                        texts.firstOrNull() ?: "ota_failed",
                        texts.lastOrNull() ?: "固件升级失败",
                    )
                    defaultValue(method.returnType)
                }
                else -> defaultValue(method.returnType)
            }
        }
    }

    private fun emitOta(
        deviceId: String,
        status: String,
        percent: Int? = null,
        message: String? = null,
    ) = emit(
        mapOf(
            "deviceId" to deviceId,
            "ota" to mapOf(
                "status" to status,
                "percent" to percent,
                "message" to message,
            ),
        ),
    )

    private fun otaInstance(deviceId: String): Any = otaInstances.getOrPut(deviceId) {
        invokeStatic(sdkClass(), "newOTAInstance", deviceId)
            ?: throw IllegalStateException("当前 SDK 未提供 OTA 实例")
    }

    private fun userMap(user: Any): Map<String, Any?> = mapOf(
        "uid" to optionalGetter(user, "getUid"),
        "nickname" to (optionalGetter(user, "getNickName") ?: optionalGetter(user, "getNickname")),
        "account" to (
            optionalGetter(user, "getUsername")
                ?: optionalGetter(user, "getMobile")
                ?: optionalGetter(user, "getEmail")
            ),
        "avatarUrl" to (optionalGetter(user, "getHeadPic") ?: optionalGetter(user, "getIconUrl")),
    )

    /**
     * Keeps a registered listener for exactly [deviceIds].
     *
     * Called after every device-list load, so a device removed from the account
     * elsewhere stops being watched and a newly bound one starts.
     */
    private fun watchDevices(deviceIds: Collection<String>) {
        val wanted = deviceIds.filter { it.isNotEmpty() }.toSet()
        (watched.keys - wanted).forEach(::unwatchDevice)
        wanted.forEach(::watchDevice)
    }

    /**
     * Registers `IDevListener` on `ThingHomeSdk.newDeviceInstance(devId)`.
     *
     * This is the SDK's own push channel: once the account is logged in and the
     * home is loaded, the SDK keeps the MQTT/LAN link up and calls the listener
     * for every DP the device reports. Nothing here polls.
     *
     * The interface is taken from the resolved `registerDevListener` signature
     * rather than named, for the same reason as every other callback in this
     * bridge, and a failure is logged instead of thrown: losing live updates
     * must not break the device list that triggered the registration.
     */
    private fun watchDevice(deviceId: String) {
        if (deviceId.isEmpty() || watched.containsKey(deviceId)) return
        runCatching {
            val device = invokeStatic(sdkClass(), "newDeviceInstance", deviceId)
                ?: throw IllegalStateException("newDeviceInstance 未返回设备实例")
            val method = findCallbackMethod(
                device.javaClass,
                "registerDevListener",
                emptyArray<Any?>(),
            )
            method.invoke(device, devListenerProxy(method.parameterTypes.last(), deviceId))
            watched[deviceId] = device
        }.onFailure { throwable ->
            val cause = TuyaSdkInitializer.unwrap(throwable)
            Log.w(
                TUYA_LOG_TAG,
                "registerDevListener failed for one device: ${cause.javaClass.simpleName}",
            )
        }
    }

    private fun unwatchDevice(deviceId: String) {
        val device = watched.remove(deviceId) ?: return
        runCatching { invoke(device, "unRegisterDevListener") }
        // Releases the SDK-side control instance the listener was attached to.
        runCatching { invoke(device, "onDestroy") }
    }

    /**
     * `IDevListener`, as a proxy.
     *
     * Callbacks arrive on an SDK thread and are forwarded to Dart as one event
     * shape:
     *
     * ```text
     * deviceId : String        always present
     * dps      : Map?          the DPs that just changed, ids as strings
     * online   : Boolean?      online/offline or phone-network change
     * removed  : Boolean?      the device left the account
     * device   : Map?          full snapshot after a device-info change
     * ```
     */
    private fun devListenerProxy(listenerType: Class<*>, deviceId: String): Any {
        val loader = listenerType.classLoader ?: activity.classLoader
        return Proxy.newProxyInstance(loader, arrayOf(listenerType)) { proxy, method, args ->
            val id = args?.firstOrNull() as? String ?: deviceId
            when (method.name) {
                "equals" -> proxy === args?.firstOrNull()
                "hashCode" -> System.identityHashCode(proxy)
                "toString" -> "TuyaDevListener($deviceId)"
                "onDpUpdate" -> {
                    val dps = dpMap(args?.getOrNull(1))
                    if (dps.isNotEmpty()) emit(mapOf("deviceId" to id, "dps" to dps))
                    defaultValue(method.returnType)
                }
                // onStatusChanged is the device going on/offline;
                // onNetworkStatusChanged is the phone losing the cloud. Either
                // way the device can no longer be trusted to be reachable.
                "onStatusChanged", "onNetworkStatusChanged" -> {
                    val online = args?.getOrNull(1) as? Boolean
                    if (online != null) emit(mapOf("deviceId" to id, "online" to online))
                    defaultValue(method.returnType)
                }
                "onRemoved" -> {
                    emit(mapOf("deviceId" to id, "removed" to true))
                    // Deferred: unregistering from inside the callback would
                    // release the instance the SDK is still calling through.
                    activity.runOnUiThread { unwatchDevice(id) }
                    defaultValue(method.returnType)
                }
                // Name, online flag and firmware version live on the bean, not
                // in a DP, so the whole snapshot is re-read.
                "onDevInfoUpdate" -> {
                    deviceBean(id)?.let { emit(mapOf("deviceId" to id, "device" to deviceMap(it))) }
                    defaultValue(method.returnType)
                }
                else -> defaultValue(method.returnType)
            }
        }
    }

    /** The SDK's cached bean for [deviceId], or null when it holds none. */
    private fun deviceBean(deviceId: String): Any? = runCatching {
        val data = invokeStatic(sdkClass(), "getDataInstance") ?: return@runCatching null
        invoke(data, "getDeviceBean", deviceId)
    }.getOrNull()

    /**
     * `IDevListener.onDpUpdate` delivers `{"101": true}` as a JSON string. Some
     * SDK generations hand over a map instead, so both are accepted.
     */
    private fun dpMap(value: Any?): Map<String, Any?> = when (value) {
        is Map<*, *> -> value.entries.associate { (key, item) -> "$key" to plainValue(item) }
        is String -> runCatching {
            val json = JSONObject(value)
            json.keys().asSequence().associateWith { key -> plainValue(json.get(key)) }
        }.getOrDefault(emptyMap())
        else -> emptyMap()
    }

    /** Narrows a JSON value to something the method channel can encode. */
    private fun plainValue(value: Any?): Any? = when {
        value == null || value === JSONObject.NULL -> null
        value is JSONObject || value is JSONArray -> value.toString()
        else -> value
    }

    /**
     * 打一行配网日志，**同时推给 Dart** —— 页面上要直接显示出来。
     *
     * 产品不看 logcat（「你把日志直接打印到页面上，我截图给你」），所以这些行必须能到
     * 界面上。`Log.i` 照旧保留：真机联调时两边都能看。
     */
    private fun trace(line: String) {
        Log.i(TUYA_LOG_TAG, line)
        emit(mapOf("type" to "pairingLog", "line" to line))
    }

    private fun emit(event: Map<String, Any?>) {
        activity.runOnUiThread { events?.success(event) }
    }

    private fun deviceIdOf(device: Any): String =
        (optionalGetter(device, "getDevId") ?: optionalGetter(device, "getDeviceId"))
            ?.toString()
            .orEmpty()

    private fun deviceMap(device: Any): Map<String, Any?> = mapOf(
        "deviceId" to deviceIdOf(device),
        "productId" to (optionalGetter(device, "getProductId") ?: optionalGetter(device, "getPid")),
        "name" to optionalGetter(device, "getName"),
        "online" to (optionalGetter(device, "getIsOnline") ?: optionalGetter(device, "isOnline")),
        "signal" to (optionalGetter(device, "getSignal") ?: 0),
        "activeTime" to (optionalGetter(device, "getActiveTime") ?: 0),
        "mac" to (optionalGetter(device, "getMac") ?: optionalGetter(device, "getUuid")),
        // getPv 是通信协议版本（"2.2" 这种），不是固件版本——之前取它，
        // 「当前版本」显示的一直是协议号。固件版本在 DeviceBean.verSw 上。
        "firmwareVersion" to (
            optionalGetter(device, "getVerSw")
                ?: optionalGetter(device, "getVersion")
            ),
        "dps" to (optionalGetter(device, "getDps") ?: emptyMap<String, Any>()),
    )

    private fun userInstance(): Any = invokeStatic(sdkClass(), "getUserInstance")
        ?: throw IllegalStateException("无法获取涂鸦用户实例")

    private fun sdkClass(): Class<*> = TuyaSdkInitializer.homeSdkClass()
        ?: throw ClassNotFoundException("com.thingclips.smart.home.sdk.ThingHomeSdk")

    private fun firstClass(vararg names: String): Class<*> = names.firstNotNullOfOrNull { name ->
        runCatching { Class.forName(name) }.getOrNull()
    } ?: throw ClassNotFoundException(names.joinToString())

    private fun invokeStatic(clazz: Class<*>, name: String, vararg args: Any?): Any? =
        findMethod(clazz, name, args).invoke(null, *args)

    private fun invoke(target: Any, name: String, vararg args: Any?): Any? =
        findMethod(target.javaClass, name, args).invoke(target, *args)

    /**
     * Calls [name] with [args] plus an SDK callback appended. The callback
     * interface is taken from the resolved method signature, so no SDK
     * interface name is hard-coded.
     */
    private fun invokeWithCallback(
        target: Any,
        name: String,
        vararg args: Any?,
        onSuccess: (Any?) -> Unit,
        onError: (String, String) -> Unit,
    ): Any? {
        val method = findCallbackMethod(target.javaClass, name, args)
        val callback = callbackProxy(method.parameterTypes.last(), onSuccess, onError)
        return method.invoke(target, *(args.toList() + callback).toTypedArray())
    }

    private fun callbackProxy(
        callbackType: Class<*>,
        onSuccess: (Any?) -> Unit,
        onError: (String, String) -> Unit,
        extraTypes: List<Class<*>> = emptyList(),
    ): Any {
        val delivered = AtomicBoolean(false)
        val loader = callbackType.classLoader ?: activity.classLoader
        val types = (listOf(callbackType) + extraTypes).distinct().toTypedArray()
        return Proxy.newProxyInstance(loader, types) { proxy, method, args ->
            when (method.name) {
                "equals" -> proxy === args?.firstOrNull()
                "hashCode" -> System.identityHashCode(proxy)
                "toString" -> "TuyaCallback(${callbackType.simpleName})"
                // 配网进度回调。只打日志（会进页面上那个日志框），不再往 Dart 推：
                // 进度页是固定三步，靠 `PairingStage` 推进，不需要这串名字。
                "onStep" -> {
                    trace("pairing step: ${args?.firstOrNull()}")
                    defaultValue(method.returnType)
                }
                "onSuccess" -> {
                    if (delivered.compareAndSet(false, true)) onSuccess(args?.firstOrNull())
                    defaultValue(method.returnType)
                }
                 // Signatures differ per interface (onError(code, msg),
                // onFailure(otaType, code, msg), ...), so the human-readable
                // pair is picked from the String arguments.
                "onError", "onFailure" -> {
                    if (delivered.compareAndSet(false, true)) {
                        val texts = args?.filterIsInstance<String>().orEmpty()
                        onError(
                            texts.firstOrNull() ?: "sdk_error",
                            texts.getOrNull(1) ?: texts.firstOrNull() ?: "SDK 调用失败",
                        )
                    }
                    defaultValue(method.returnType)
                }
                else -> defaultValue(method.returnType)
            }
        }
    }

    private fun getter(target: Any, name: String): Any =
        invoke(target, name) ?: throw IllegalStateException("$name returned null")

    private fun optionalGetter(target: Any, name: String): Any? =
        runCatching { invoke(target, name) }.getOrNull()

    private fun findMethod(clazz: Class<*>, name: String, args: Array<out Any?>): Method =
        candidates(clazz).firstOrNull { method ->
            method.name == name && method.parameterTypes.size == args.size &&
                method.parameterTypes.zip(args.toList()).all { (type, value) -> compatible(type, value) }
        }?.apply { isAccessible = true }
            ?: throw NoSuchMethodException(
                "${clazz.name}.$name(${args.joinToString { it?.javaClass?.simpleName ?: "null" }})",
            )

    private fun findCallbackMethod(clazz: Class<*>, name: String, args: Array<out Any?>): Method =
        optionalCallbackMethod(clazz, name, args)
            ?: throw NoSuchMethodException(
                "${clazz.name}.$name(${args.joinToString { it?.javaClass?.simpleName ?: "null" }}, callback)",
            )

    private fun optionalCallbackMethod(
        clazz: Class<*>,
        name: String,
        args: Array<out Any?>,
    ): Method? = candidates(clazz).firstOrNull { method ->
        method.name == name && method.parameterTypes.size == args.size + 1 &&
            method.parameterTypes.last().isInterface &&
            method.parameterTypes.dropLast(1).zip(args.toList())
                .all { (type, value) -> compatible(type, value) }
    }?.apply { isAccessible = true }

    private fun candidates(clazz: Class<*>): List<Method> =
        (clazz.methods + clazz.declaredMethods).distinct()

    private fun compatible(type: Class<*>, value: Any?): Boolean {
        if (value == null) return !type.isPrimitive
        val boxed = when (type) {
            java.lang.Boolean.TYPE -> java.lang.Boolean::class.java
            java.lang.Integer.TYPE -> java.lang.Integer::class.java
            java.lang.Long.TYPE -> java.lang.Long::class.java
            java.lang.Double.TYPE -> java.lang.Double::class.java
            java.lang.Float.TYPE -> java.lang.Float::class.java
            else -> type
        }
        if (boxed.isAssignableFrom(value.javaClass)) return true
        return Number::class.java.isAssignableFrom(boxed) && value is Number
    }

    private fun number(value: Any): Long = (value as? Number)?.toLong() ?: value.toString().toLong()

    private fun defaultValue(type: Class<*>): Any? = when (type) {
        java.lang.Boolean.TYPE -> false
        java.lang.Integer.TYPE -> 0
        java.lang.Long.TYPE -> 0L
        java.lang.Float.TYPE -> 0f
        java.lang.Double.TYPE -> 0.0
        else -> null
    }

    private fun success(result: MethodChannel.Result, value: Any?) {
        activity.runOnUiThread { result.success(value) }
    }

    private fun error(result: MethodChannel.Result, code: String, message: String) {
        activity.runOnUiThread { result.error(code, message, null) }
    }

    private fun fail(result: MethodChannel.Result, throwable: Throwable) {
        val cause = TuyaSdkInitializer.unwrap(throwable)
        Log.e(TUYA_LOG_TAG, "Tuya SDK call failed: ${cause.javaClass.simpleName}")
        val (code, message) = TuyaSdkInitializer.describe(cause)
        error(result, code, message)
    }
}
