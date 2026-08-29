package com.common.yikaltd

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Build
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
 * How long a cached provisioning token may be reused.
 *
 * Tuya issues them with a 10-minute validity; 8 leaves room for the user to
 * switch networks and for the activator's own handshake.
 */
private const val ACTIVATOR_TOKEN_TTL_MS = 8L * 60 * 1000

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
    private var activator: Any? = null

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

    /**
     * `IThingDevice` instances that currently hold a registered listener, keyed
     * by device id. Written from the main thread, read from the SDK's callback
     * threads.
     */
    private val watched = ConcurrentHashMap<String, Any>()

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
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "scanWifi") {
                scanWifi(result)
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
    private fun scanWifi(result: MethodChannel.Result) {
        val context = activity.applicationContext
        val wifi = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifi.isWifiEnabled) {
            error(result, "wifi_disabled", "手机 Wi-Fi 未开启，无法扫描")
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
        // Throttled since Android 9 (a few scans per two minutes). A refused
        // start still leaves the last cached results, which is good enough.
        runCatching { wifi.startScan() }
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
        success(
            result,
            mapOf(
                "current" to current?.takeIf { it != "<unknown ssid>" },
                "currentFrequency" to currentFrequency,
                "networks" to networks,
            ),
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
        val manager = invokeStatic(sdkClass(), "getHomeManagerInstance")
            ?: throw IllegalStateException("无法获取家庭管理实例")
        invokeWithCallback(
            manager,
            "queryHomeList",
            onSuccess = { value ->
                onMain(result) {
                    val homes = value as? List<*> ?: emptyList<Any>()
                    val first = homes.filterNotNull().firstOrNull()
                    if (first != null) {
                        val id = number(getter(first, "getHomeId"))
                        homeId = id
                        ready(id)
                    } else {
                        createHome(manager, result, ready)
                    }
                }
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    private fun createHome(manager: Any, result: MethodChannel.Result, ready: (Long) -> Unit) {
        invokeWithCallback(
            manager,
            "createHome",
            "我的花园",
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

    private fun pairWifi(call: MethodCall, result: MethodChannel.Result) {
        // 上一次配网若被中途放弃（用户退页面、进程被杀），绑定可能还留着，那会让
        // App 一直没有外网。这里先无条件清一次。
        unbindProcessNetwork()
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
        val ez = call.argument<String>("mode") == "ez"
        val factory = activatorFactory(activatorApi, allowMulti = ez)
        val builderClass = factory.parameterTypes.single()
        val builder = builderClass.getDeclaredConstructor()
            .apply { isAccessible = true }
            .newInstance()
        val mode = activatorMode(builder, if (ez) EZ_MODE_NAMES else AP_MODE_NAMES)
        invoke(builder, "setContext", activity)
        invoke(builder, "setSsid", call.argument<String>("ssid").orEmpty())
        invoke(builder, "setPassword", call.argument<String>("password").orEmpty())
        invoke(builder, "setActivatorModel", mode)
        invoke(builder, "setTimeOut", 120L)
        invoke(builder, "setToken", token)
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
                error(result, code, message)
            },
        )
        activator = factory.invoke(activatorApi, builder)
            ?: throw IllegalStateException("${factory.name} 未返回配网实例")
        val bound = bindProcessToWifi()
        Log.i(TUYA_LOG_TAG, "AP pairing: process bound to Wi-Fi = $bound")
        invoke(activator!!, "start")
    }

    /**
     * `IThingActivator` 上的配网工厂，按模式选。
     *
     * `newMultiActivator` 一次会话可以配多台，但只实现了 EZ——喂给它一个 AP 的
     * Builder 会在 `start()` 时报 `Multi Config don't support the AP Mode`。所以
     * AP 只允许单设备的 `newActivator`，EZ 优先 multi、缺失时回落到单设备。
     *
     * 两者都只接受 Builder 一个参数，[startActivator] 正是据此拿到 Builder 的
     * 类型，不必写死包名。
     */
    private fun activatorFactory(activatorApi: Any, allowMulti: Boolean): Method {
        val preference = if (allowMulti) {
            listOf("newMultiActivator", "newActivator")
        } else {
            listOf("newActivator")
        }
        val factories = candidates(activatorApi.javaClass).filter { method ->
            method.name in preference &&
                method.parameterTypes.size == 1 &&
                method.parameterTypes.single().simpleName.endsWith("Builder")
        }
        // Walk the preference list rather than the reflected order, which is
        // not promised to be stable across runs.
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
        invokeWithCallback(
            otaInstance(call),
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
                success(result, pending?.let { optionalGetter(it, "getVersion")?.toString() })
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    private fun startFirmwareUpgrade(call: MethodCall, result: MethodChannel.Result) {
        val deviceId = call.argument<String>("deviceId").orEmpty()
        val ota = otaInstance(call)
        // 升级要跑几分钟，方法通道只能回答一次，所以它只回答"已发起"；下载进度
        // 和最终成败改从事件通道推给 Dart。
        val started = AtomicBoolean(false)
        val answerStarted = { if (started.compareAndSet(false, true)) success(result, null) }
        val onSuccess: (Any?) -> Unit = {
            answerStarted()
            emitOta(deviceId, "success")
        }
        val onError: (String, String) -> Unit = { code, message ->
            // 还没回答过方法调用就失败，说明升级根本没起来，照常回错误；已经
            // 回答过则只能通过事件通道报告。
            if (started.compareAndSet(false, true)) {
                error(result, code, message)
            }
            emitOta(deviceId, "failed", message = message)
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

    private fun otaInstance(call: MethodCall): Any =
        invokeStatic(sdkClass(), "newOTAInstance", call.argument<String>("deviceId").orEmpty())
            ?: throw IllegalStateException("当前 SDK 未提供 OTA 实例")

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
        "firmwareVersion" to (optionalGetter(device, "getPv") ?: optionalGetter(device, "getVersion")),
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
