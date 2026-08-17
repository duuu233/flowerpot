package com.common.yikaltd

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private lateinit var bridge: TuyaSdkBridge
    private var pendingPair: Pair<MethodCall, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = TuyaSdkBridge(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.common.yikaltd/tuya",
        ).setMethodCallHandler { call, result ->
            if (call.method == "pairWifiDevice" && requestPairingPermissions(call, result)) {
                return@setMethodCallHandler
            }
            bridge.handle(call, result)
        }
    }

    private fun requestPairingPermissions(
        call: MethodCall,
        result: MethodChannel.Result,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val permissions = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions += Manifest.permission.BLUETOOTH_SCAN
            permissions += Manifest.permission.BLUETOOTH_CONNECT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions += Manifest.permission.NEARBY_WIFI_DEVICES
        }
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) return false
        if (pendingPair != null) {
            result.error("busy", "已有配网权限请求正在进行", null)
            return true
        }
        pendingPair = call to result
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
        if (grantResults.isEmpty() || grantResults.any { it != PackageManager.PERMISSION_GRANTED }) {
            pending.second.error("permission_denied", "配网需要附近设备与定位权限", null)
        } else {
            bridge.handle(pending.first, pending.second)
        }
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

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (!ensureReady(result)) return
            when (call.method) {
                "initialize" -> result.success(true)
                "currentUser" -> currentUser(result)
                "sendVerificationCode" -> sendCode(call, result)
                "login" -> login(call, result)
                "register" -> register(call, result)
                "resetPassword" -> resetPassword(call, result)
                "updateNickname" -> updateNickname(call, result)
                "logout" -> userAction("logout", result)
                "cancelAccount" -> userAction("cancelAccount", result)
                "getDevices" -> withHome(result) { home -> loadHomeDevices(home, result) }
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
            onSuccess = { success(result, null) },
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
                val homes = value as? List<*> ?: emptyList<Any>()
                val first = homes.filterNotNull().firstOrNull()
                if (first != null) {
                    val id = number(getter(first, "getHomeId"))
                    homeId = id
                    ready(id)
                } else {
                    createHome(manager, result, ready)
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
                if (value == null) {
                    error(result, "home_missing", "创建家庭未返回家庭信息")
                } else {
                    val id = number(getter(value, "getHomeId"))
                    homeId = id
                    ready(id)
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
                val devices = value?.let { optionalGetter(it, "getDeviceList") } as? List<*>
                success(result, devices.orEmpty().filterNotNull().map(::deviceMap))
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    private fun pairWifi(call: MethodCall, result: MethodChannel.Result) {
        withHome(result) { id ->
            val activatorApi = invokeStatic(sdkClass(), "getActivatorInstance")
                ?: throw IllegalStateException("无法获取配网实例")
            invokeWithCallback(
                activatorApi,
                "getActivatorToken",
                id,
                onSuccess = { token -> startActivator(call, result, token?.toString().orEmpty()) },
                onError = { code, message -> error(result, code, message) },
            )
        }
    }

    private fun startActivator(call: MethodCall, result: MethodChannel.Result, token: String) {
        val activatorApi = invokeStatic(sdkClass(), "getActivatorInstance")
            ?: throw IllegalStateException("无法获取配网实例")
        val builderClass = firstClass(
            "com.thingclips.smart.sdk.builder.ActivatorBuilder",
            "com.thingclips.smart.sdk.builder.ThingActivatorBuilder",
        )
        val builder = builderClass.getDeclaredConstructor().newInstance()
        val enumClass = firstClass("com.thingclips.smart.sdk.enums.ActivatorModelEnum")
        @Suppress("UNCHECKED_CAST")
        val enumType = enumClass as Class<out Enum<*>>
        val modeName = if (call.argument<String>("mode") == "ez") "TY_EZ" else "TY_AP"
        val mode = enumType.enumConstants.first { it.name == modeName }
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
                stopActivator()
                if (value == null) {
                    error(result, "pair_failed", "配网未返回设备信息")
                } else {
                    success(result, deviceMap(value))
                }
            },
            onError = { code, message ->
                stopActivator()
                error(result, code, message)
            },
        )
        activator = invoke(activatorApi, "newMultiActivator", builder)
        invoke(activator!!, "start")
    }

    private fun stopActivator() {
        activator?.let { runCatching { invoke(it, "stop") } }
        activator = null
    }

    private fun deviceAction(call: MethodCall, result: MethodChannel.Result, method: String) {
        val deviceId = call.argument<String>("deviceId").orEmpty()
        val device = invokeStatic(sdkClass(), "newDeviceInstance", deviceId)
            ?: throw IllegalStateException("无法创建设备实例")
        val onSuccess: (Any?) -> Unit = { success(result, null) }
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
                val list = value as? List<*> ?: emptyList<Any>()
                val version = list.filterNotNull().firstOrNull()?.let {
                    optionalGetter(it, "getVersion")?.toString()
                }
                success(result, version)
            },
            onError = { code, message -> error(result, code, message) },
        )
    }

    private fun startFirmwareUpgrade(call: MethodCall, result: MethodChannel.Result) {
        val ota = otaInstance(call)
        val onSuccess: (Any?) -> Unit = { success(result, null) }
        val onError: (String, String) -> Unit = { code, message -> error(result, code, message) }
        // 7.x reports progress through a listener and starts with a no-arg call;
        // older builds accept the callback directly on startOta.
        val listenerMethod =
            optionalCallbackMethod(ota.javaClass, "setOtaListener", emptyArray<Any?>())
        if (listenerMethod != null) {
            listenerMethod.invoke(
                ota,
                callbackProxy(listenerMethod.parameterTypes.last(), onSuccess, onError),
            )
            invoke(ota, "startOta")
            return
        }
        invokeWithCallback(ota, "startOta", onSuccess = onSuccess, onError = onError)
    }

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

    private fun deviceMap(device: Any): Map<String, Any?> = mapOf(
        "deviceId" to (optionalGetter(device, "getDevId") ?: optionalGetter(device, "getDeviceId")),
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
