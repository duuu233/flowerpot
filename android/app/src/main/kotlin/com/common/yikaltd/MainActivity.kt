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
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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
 * 配网模式常量，新拼写在前。
 *
 * 两种都支持：EZ 让手机全程连在路由器上直接广播凭据，省掉切热点那一步，是默认
 * 路径；AP 要手机先连设备热点，步骤繁琐但不受路由器组播策略影响，作为 EZ 失败
 * 后的兜底。
 *
 * Tuya renamed `ActivatorModelEnum`'s constants from `TY_*` to `THING_*` during
 * 7.x — 7.5.1 offers `THING_AP, THING_EZ, THING_4G_GATEWAY, THING_STATIC_IP,
 * THING_QR` and no `TY_*` at all. The old names stay as a fallback so the
 * bridge also works against an older SDK drop.
 */
private val EZ_MODE_NAMES = listOf("THING_EZ", "TY_EZ")
private val AP_MODE_NAMES = listOf("THING_AP", "TY_AP")

/**
 * EZ+AP 双模。SDK 里叫什么没有公开保证，所以按候选列表逐个试；一个都没有时
 * [activatorMode] 会把该枚举实际提供的常量名列进异常，据此再补名字。
 */
private val DUAL_MODE_NAMES = listOf(
    "THING_EZ_AP", "TY_EZ_AP", "THING_AP_EZ", "TY_AP_EZ", "THING_EZ_AND_AP",
)

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
                call.method == "pairWifiDevice" || call.method == "scanWifi" ||
                    call.method == "apQueryDeviceWifi" || call.method == "apStartPairing"
            if (needsWifiPermissions && requestPairingPermissions(call, result)) {
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
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val required = mutableSetOf<String>()
        val requested = mutableSetOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
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
                "配网需要定位或附近 Wi-Fi 设备权限",
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
            // 停配网属于释放类调用：SDK 没就绪时也可能有残留的配网器要放掉。
            if (call.method == "apStopPairing") {
                releaseOptimizedActivator()
                success(result, null)
                return
            }
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
                "prepareActivatorToken" -> prepareActivatorToken(result)
                "pairWifiDevice" -> pairWifi(call, result)
                // 「热点配网新流程」：SDK 自己连热点、读回设备扫到的 Wi-Fi 列表，
                // 再下发凭据。见 apQueryDeviceWifi 的说明。
                "apQueryDeviceWifi" -> apQueryDeviceWifi(call, result)
                "apStartPairing" -> apStartPairing(call, result)
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

    private fun loadHomeDevices(id: Long, result: MethodChannel.Result) {
        val home = invokeStatic(sdkClass(), "newHomeInstance", id)
            ?: throw IllegalStateException("无法创建家庭实例")
        invokeWithCallback(
            home,
            "getHomeDetail",
            onSuccess = { value ->
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

    /** Calls [onReady] on the main thread with a freshly cached token. */
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

    /**
     * 「热点配网新流程」的配网器。查 Wi-Fi 列表与开始配网必须是**同一个实例**：
     * 连热点这一步发生在 [apQueryDeviceWifi] 里，实例换了连接也就没了。
     */
    private var optimizedActivator: Any? = null

    /**
     * 新流程第一步：让 SDK 自己连上设备热点，并读回**设备扫到的 Wi-Fi 列表**。
     *
     * 这是整条新流程的关键——官方文档原话：「在配网过程中，SDK 会在指定时间内自动去
     * 连接 AP 热点」。也就是说 App 不必再用 `WifiNetworkSpecifier` 去连，那个每次都弹
     * 的系统入网授权框也就不存在了。
     *
     * 返回的列表来自**设备的视角**（设备自己扫到的），比手机侧扫描准得多：设备能看见
     * 的才是它连得上的。`sec` 还给出加密方式，可以据此提前校验密码长度。
     *
     * ⚠️ 只对新固件有效（TuyaOS ≥ 3.6.1）。老固件上这一步会以 `207206`
     * （设备返回不能识别的状态）或超时失败。
     */
    private fun apQueryDeviceWifi(call: MethodCall, result: MethodChannel.Result) {
        val activator = newOptimizedActivator()

        // ApQueryBuilder.Builder().setContext(ctx).setTimeout(ms).build()
        val timeout = (call.argument<Number>("timeout")?.toLong() ?: 0L)
        val queryBuilderClass = firstClass(
            "com.thingclips.smart.sdk.bean.ApQueryBuilder\$Builder",
        )
        val queryBuilder = queryBuilderClass.getDeclaredConstructor()
            .apply { isAccessible = true }
            .newInstance()
        invoke(queryBuilder, "setContext", activity)
        invoke(queryBuilder, "setTimeout", timeout)
        val query = invoke(queryBuilder, "build")
            ?: throw IllegalStateException("ApQueryBuilder.build 返回空")

        Log.i(TUYA_LOG_TAG, "ap query device wifi, timeout=$timeout")
        invokeWithCallback(
            activator,
            "queryDeviceConfigState",
            query,
            onSuccess = { value ->
                onMain(result) { success(result, wifiInfoList(value)) }
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    /**
     * 建一个「热点配网新流程」的配网器（`IThingOptimizedActivator`）。
     *
     * `apQueryDeviceWifi` 和 `apStartPairing` 都要它，而**两者互不依赖**：
     * 2026-09-10 起查设备 Wi-Fi 列表这一步被产品去掉了（只用手机当前连着的网络），
     * 所以配网可以在从没查过列表的情况下直接开始。文档说的「SDK 会在指定时间内
     * 自动去连接 AP 热点」就发生在 `startActivator` 里面，不是查询那一步的副作用。
     *
     * 旧的先释放：一个配网器身上挂着一条热点连接，留着会互相抢。
     */
    private fun newOptimizedActivator(): Any {
        val activatorApi = invokeStatic(sdkClass(), "getActivatorInstance")
            ?: throw IllegalStateException("无法获取配网实例")
        // ThingApActivatorBuilder().setContext(activity)
        val builderClass = firstClass(
            "com.thingclips.smart.home.sdk.builder.ThingApActivatorBuilder",
        )
        val builder = builderClass.getDeclaredConstructor()
            .apply { isAccessible = true }
            .newInstance()
        invoke(builder, "setContext", activity)
        releaseOptimizedActivator()
        val created = invoke(activatorApi, "newOptimizedActivator", builder)
            ?: throw IllegalStateException("newOptimizedActivator 未返回配网实例")
        optimizedActivator = created
        return created
    }

    /** `List<WifiInfoBean>` → Dart 端的 `[{ssid, rssi, sec}]`。 */
    private fun wifiInfoList(value: Any?): List<Map<String, Any?>> {
        val items = value as? Collection<*> ?: return emptyList()
        return items.mapNotNull { bean ->
            if (bean == null) return@mapNotNull null
            val ssid = readAny(bean, "getSsid", "getSSID")?.toString().orEmpty()
            if (ssid.isEmpty()) return@mapNotNull null
            mapOf(
                "ssid" to ssid,
                "rssi" to (readAny(bean, "getRssi", "getRSSI") as? Number)?.toInt(),
                "sec" to (readAny(bean, "getSec", "getSecurity") as? Number)?.toInt(),
            )
        }
    }

    /** 依次试几个取值方法名，都没有就返回 null——SDK 在 7.x 里改过命名。 */
    private fun readAny(target: Any, vararg names: String): Any? = names.firstNotNullOfOrNull {
        runCatching { invoke(target, it) }.getOrNull()
    }

    /**
     * 新流程第二步：把路由器凭据下发给设备。
     *
     * 必须复用 [apQueryDeviceWifi] 建好的那个配网器——热点连接挂在它上面。
     */
    private fun apStartPairing(call: MethodCall, rawResult: MethodChannel.Result) {
        if (pairingResult != null) releasePairing("pair_cancelled", "被新的配网请求取代")
        val result = PairingResult(rawResult)
        pairingResult = result
        freshActivatorToken()?.let { token ->
            apStartWithToken(call, result, token)
            return
        }
        withHome(result) { id ->
            fetchActivatorToken(id, result) { token ->
                apStartWithToken(call, result, token)
            }
        }
    }

    private fun apStartWithToken(
        call: MethodCall,
        result: MethodChannel.Result,
        token: String,
    ) {
        // 没查过设备 Wi-Fi 列表也能直接配网：现在的动线就是不查（只用手机当前连着
        // 的网络），配网器在这里按需新建，连热点由 startActivator 自己完成。
        val activator = optimizedActivator ?: newOptimizedActivator()
        // ApActivatorBuilder.Builder()…build()
        val builderClass = firstClass(
            "com.thingclips.smart.sdk.bean.ApActivatorBuilder\$Builder",
        )
        val builder = builderClass.getDeclaredConstructor()
            .apply { isAccessible = true }
            .newInstance()
        invoke(builder, "setSsid", call.argument<String>("ssid").orEmpty())
        invoke(builder, "setPwd", call.argument<String>("password").orEmpty())
        // 新流程的超时单位是**毫秒**（原流程的 setTimeOut 是秒），别搞混。
        invoke(builder, "setTimeout", call.argument<Number>("timeout")?.toLong() ?: 120_000L)
        invoke(builder, "setToken", token)
        call.argument<String>("securityConfig")?.takeIf { it.isNotBlank() }?.let {
            runCatching { invoke(builder, "setSecurityConfig", it) }
        }
        invokeWithCallback(
            builder,
            "setListener",
            onSuccess = { value ->
                onMain(result) {
                    releaseOptimizedActivator()
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
                releaseOptimizedActivator()
                error(result, code, message)
            },
        )
        val request = invoke(builder, "build")
            ?: throw IllegalStateException("ApActivatorBuilder.build 返回空")
        Log.i(TUYA_LOG_TAG, "ap start activator (new flow)")
        invoke(activator, "startActivator", request)
    }

    /** 停掉新流程的配网器并释放它持有的热点连接。 */
    private fun releaseOptimizedActivator() {
        val activator = optimizedActivator ?: return
        optimizedActivator = null
        runCatching { invoke(activator, "stopActivator") }
        runCatching { invoke(activator, "onDestroy") }
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
        val requested = call.argument<String>("mode").orEmpty()
        val modeNames = when (requested) {
            "ez" -> EZ_MODE_NAMES
            "dual" -> DUAL_MODE_NAMES
            else -> AP_MODE_NAMES
        }
        val factory = activatorFactory(activatorApi, requested)
        val builderClass = factory.parameterTypes.single()
        val builder = builderClass.getDeclaredConstructor()
            .apply { isAccessible = true }
            .newInstance()
        val mode = activatorMode(builder, modeNames)
        invoke(builder, "setContext", activity)
        invoke(builder, "setSsid", call.argument<String>("ssid").orEmpty())
        invoke(builder, "setPassword", call.argument<String>("password").orEmpty())
        invoke(builder, "setActivatorModel", mode)
        invoke(builder, "setTimeOut", 120L)
        invoke(builder, "setToken", token)
        // 这台机器上 adb 未必连得上，所以诊断信息不能只进 logcat——失败时一并
        // 回给 Dart，联调页的日志区才看得到实际用了哪个工厂、哪个枚举常量。
        val used = "$requested/${factory.name}/${(mode as Enum<*>).name}"
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
        // 绑定只对 AP 做。EZ 是往手机所在网络广播凭据，把进程绑死在某个 Network
        // 上会挡住那些广播——这正是 EZ 加了绑定之后开始报 1006 的原因。AP 则相反：
        // 手机连的设备热点没有互联网，不绑定的话流量会被系统留在移动数据上。
        //
        // joinDeviceHotspot 已经绑好时不要重绑：那条绑定指向的正是设备热点，而这里
        // 是从 allNetworks 里挑第一个 Wi-Fi，很可能挑中路由器，反而把凭据发错地方。
        if (requested == "ap") {
            if (boundNetwork == null) {
                val bound = bindProcessToWifi()
                Log.i(TUYA_LOG_TAG, "AP pairing: process bound to Wi-Fi = $bound")
            } else {
                Log.i(TUYA_LOG_TAG, "AP pairing: reusing hotspot binding")
            }
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
    private fun activatorFactory(activatorApi: Any, mode: String): Method {
        val preference = if (mode == "ez") {
            listOf("newEZWifiConfigDevActivator", "newActivator")
        } else {
            listOf("newActivator")
        }
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
        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
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
        val answered = AtomicBoolean(false)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val bound = runCatching { manager.bindProcessToNetwork(network) }
                    .getOrDefault(false)
                Log.i(TUYA_LOG_TAG, "hotspot joined $target, bound=$bound")
                if (!answered.compareAndSet(false, true)) return
                if (bound) {
                    boundNetwork = network
                    success(result, true)
                } else {
                    // 连上了却绑不过去，这条连接没有用处：立刻放掉，别让手机挂在
                    // 一个 App 用不了的热点上。
                    activity.runOnUiThread { releaseHotspotRequest() }
                    error(result, "hotspot_bind_failed", "已连上 $target，但进程流量未能切换到热点")
                }
            }

            override fun onUnavailable() {
                // 系统扫不到匹配的网络时也走这里，和用户点了取消无法区分，所以把
                // 实际匹配的目标带出去——前缀写错导致一个都匹配不上时，这行是唯一
                // 能看出问题的信息。请求已经结束，回调也一并注销。
                activity.runOnUiThread { releaseHotspotRequest() }
                if (answered.compareAndSet(false, true)) {
                    error(
                        result,
                        "hotspot_join_cancelled",
                        "未连上 $target：热点不存在、系统弹框被取消或超时",
                    )
                }
            }

            override fun onLost(network: Network) {
                if (network == boundNetwork) {
                    Log.i(TUYA_LOG_TAG, "hotspot lost, releasing binding")
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
    ): Any {
        val delivered = AtomicBoolean(false)
        val loader = callbackType.classLoader ?: activity.classLoader
        return Proxy.newProxyInstance(loader, arrayOf(callbackType)) { proxy, method, args ->
            when (method.name) {
                "equals" -> proxy === args?.firstOrNull()
                "hashCode" -> System.identityHashCode(proxy)
                "toString" -> "TuyaCallback(${callbackType.simpleName})"
                "onSuccess", "onActiveSuccess" -> {
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
