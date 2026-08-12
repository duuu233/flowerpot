package com.common.yikaltd

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.lang.reflect.InvocationTargetException
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
        if (grantResults.any { it != PackageManager.PERMISSION_GRANTED }) {
            pending.second.error("permission_denied", "配网需要附近设备与定位权限", null)
        } else {
            bridge.handle(pending.first, pending.second)
        }
    }
}

/**
 * Flutter-to-Tuya adapter. Reflection is deliberate: the app-specific Tuya
 * security component is not committed to source control. Once
 * security-algorithm.aar is placed in app/libs, Gradle links SDK 7.5.x and the
 * same implementation starts calling the real classes without source changes.
 */
private class TuyaSdkBridge(private val activity: FlutterActivity) {
    private val sdkClassName = "com.thingclips.smart.home.sdk.ThingHomeSdk"
    private var homeId: Long? = null
    private var activator: Any? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> initialize(result)
                "currentUser" -> currentUser(result)
                "sendVerificationCode" -> sendCode(call, result)
                "login" -> login(call, result)
                "register" -> register(call, result)
                "resetPassword" -> resetPassword(call, result)
                "updateNickname" -> updateNickname(call, result)
                "logout" -> simpleUserCallback("logout", result)
                "cancelAccount" -> simpleUserCallback("cancelAccount", result)
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

    private fun initialize(result: MethodChannel.Result) {
        val sdk = sdkClass()
        val metadata = activity.packageManager
            .getApplicationInfo(activity.packageName, PackageManager.GET_META_DATA)
            .metaData
        val key = metadata?.getString("THING_SMART_APPKEY").orEmpty()
        val secret = metadata?.getString("THING_SMART_SECRET").orEmpty()
        if (key.isBlank() || secret.isBlank()) {
            result.error("credentials_missing", "请在 android/local.properties 配置涂鸦 AppKey 与 AppSecret", null)
            return
        }
        invokeStatic(sdk, "init", activity.application, key, secret)
        runCatching { invokeStatic(sdk, "setDebugMode", isDebugBuild()) }
        result.success(true)
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
        val account = call.argument<String>("account").orEmpty()
        val countryCode = call.argument<String>("countryCode").orEmpty()
        val type = call.argument<Int>("type") ?: 2
        val callback = resultCallback(result)
        invoke(userInstance(), "sendVerifyCodeWithUserName", account, "", countryCode, type, callback)
    }

    private fun login(call: MethodCall, result: MethodChannel.Result) {
        val account = call.argument<String>("account").orEmpty()
        val credential = call.argument<String>("credential").orEmpty()
        val countryCode = call.argument<String>("countryCode").orEmpty()
        val email = call.argument<Boolean>("email") ?: false
        val codeLogin = call.argument<Boolean>("verificationCode") ?: false
        val callback = callbackProxy(
            interfaces = listOf("com.thingclips.smart.android.user.api.ILoginCallback"),
            onSuccess = { value -> success(result, userMap(value)) },
            onError = { code, message -> error(result, code, message) },
        )
        val method = when {
            email -> "loginWithEmail"
            codeLogin -> "loginWithPhone"
            else -> "loginWithPhonePassword"
        }
        invoke(userInstance(), method, countryCode, account, credential, callback)
    }

    private fun register(call: MethodCall, result: MethodChannel.Result) {
        val account = call.argument<String>("account").orEmpty()
        val password = call.argument<String>("password").orEmpty()
        val code = call.argument<String>("code").orEmpty()
        val countryCode = call.argument<String>("countryCode").orEmpty()
        val email = call.argument<Boolean>("email") ?: false
        val callback = callbackProxy(
            interfaces = listOf("com.thingclips.smart.android.user.api.IRegisterCallback"),
            onSuccess = { value -> success(result, userMap(value)) },
            onError = { errorCode, message -> error(result, errorCode, message) },
        )
        invoke(
            userInstance(),
            if (email) "registerAccountWithEmail" else "registerAccountWithPhone",
            countryCode,
            account,
            password,
            code,
            callback,
        )
    }

    private fun resetPassword(call: MethodCall, result: MethodChannel.Result) {
        val account = call.argument<String>("account").orEmpty()
        val newPassword = call.argument<String>("newPassword").orEmpty()
        val code = call.argument<String>("code").orEmpty()
        val countryCode = call.argument<String>("countryCode").orEmpty()
        val email = call.argument<Boolean>("email") ?: false
        val callback = callbackProxy(
            interfaces = listOf("com.thingclips.smart.android.user.api.IResetPasswordCallback"),
            onSuccess = { success(result, null) },
            onError = { errorCode, message -> error(result, errorCode, message) },
        )
        invoke(
            userInstance(),
            if (email) "resetEmailPassword" else "resetPhonePassword",
            countryCode,
            account,
            code,
            newPassword,
            callback,
        )
    }

    private fun updateNickname(call: MethodCall, result: MethodChannel.Result) {
        val callback = callbackProxy(
            interfaces = listOf("com.thingclips.smart.android.user.api.IReNickNameCallback"),
            onSuccess = { success(result, null) },
            onError = { errorCode, message -> error(result, errorCode, message) },
        )
        invoke(
            userInstance(),
            "updateNickName",
            call.argument<String>("nickname").orEmpty(),
            callback,
        )
    }

    private fun simpleUserCallback(method: String, result: MethodChannel.Result) {
        val callback = callbackProxy(
            interfaces = listOf(
                "com.thingclips.smart.android.user.api.ILogoutCallback",
                "com.thingclips.smart.sdk.api.IResultCallback",
            ),
            onSuccess = { success(result, null) },
            onError = { code, message -> error(result, code, message) },
        )
        invoke(userInstance(), method, callback)
    }

    private fun withHome(result: MethodChannel.Result, ready: (Long) -> Unit) {
        homeId?.let {
            ready(it)
            return
        }
        val manager = invokeStatic(sdkClass(), "getHomeManagerInstance")
            ?: throw IllegalStateException("无法获取家庭管理实例")
        val callback = callbackProxy(
            interfaces = listOf("com.thingclips.smart.home.sdk.callback.IThingGetHomeListCallback"),
            onSuccess = { value ->
                val homes = value as? List<*> ?: emptyList<Any>()
                if (homes.isNotEmpty()) {
                    val id = number(getter(homes.first()!!, "getHomeId"))
                    homeId = id
                    ready(id)
                } else {
                    createHome(manager, result, ready)
                }
            },
            onError = { code, message -> error(result, code, message) },
        )
        invoke(manager, "queryHomeList", callback)
    }

    private fun createHome(manager: Any, result: MethodChannel.Result, ready: (Long) -> Unit) {
        val callback = callbackProxy(
            interfaces = listOf("com.thingclips.smart.home.sdk.callback.IThingHomeResultCallback"),
            onSuccess = { value ->
                val id = number(getter(value, "getHomeId"))
                homeId = id
                ready(id)
            },
            onError = { code, message -> error(result, code, message) },
        )
        invoke(manager, "createHome", "我的花园", 0.0, 0.0, "", emptyList<String>(), callback)
    }

    private fun loadHomeDevices(id: Long, result: MethodChannel.Result) {
        val home = invokeStatic(sdkClass(), "newHomeInstance", id)
            ?: throw IllegalStateException("无法创建家庭实例")
        val callback = callbackProxy(
            interfaces = listOf("com.thingclips.smart.home.sdk.callback.IThingHomeResultCallback"),
            onSuccess = { value ->
                val devices = getter(value, "getDeviceList") as? List<*> ?: emptyList<Any>()
                success(result, devices.filterNotNull().map(::deviceMap))
            },
            onError = { code, message -> error(result, code, message) },
        )
        invoke(home, "getHomeDetail", callback)
    }

    private fun pairWifi(call: MethodCall, result: MethodChannel.Result) {
        withHome(result) { id ->
            val tokenCallback = callbackProxy(
                interfaces = listOf("com.thingclips.smart.sdk.api.IThingActivatorGetToken"),
                onSuccess = { token -> startActivator(call, result, token.toString()) },
                onError = { code, message -> error(result, code, message) },
            )
            val activatorApi = invokeStatic(sdkClass(), "getActivatorInstance")
                ?: throw IllegalStateException("无法获取配网实例")
            invoke(activatorApi, "getActivatorToken", id, tokenCallback)
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
        val listener = callbackProxy(
            interfaces = listOf("com.thingclips.smart.sdk.api.IThingSmartActivatorListener"),
            onSuccess = { value ->
                activator?.let { runCatching { invoke(it, "stop") } }
                success(result, deviceMap(value))
            },
            onError = { code, message -> error(result, code, message) },
        )
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
        invoke(builder, "setListener", listener)
        activator = invoke(activatorApi, "newMultiActivator", builder)
        invoke(activator!!, "start")
    }

    private fun deviceAction(call: MethodCall, result: MethodChannel.Result, method: String) {
        val deviceId = call.argument<String>("deviceId").orEmpty()
        val device = invokeStatic(sdkClass(), "newDeviceInstance", deviceId)
            ?: throw IllegalStateException("无法创建设备实例")
        val callback = resultCallback(result)
        when (method) {
            "publishDps" -> {
                val dps = call.argument<Map<String, Any?>>("dps") ?: emptyMap()
                invoke(device, method, JSONObject(dps).toString(), callback)
            }
            "renameDevice" -> invoke(device, method, call.argument<String>("name").orEmpty(), callback)
            else -> invoke(device, method, callback)
        }
    }

    private fun createShareLink(call: MethodCall, result: MethodChannel.Result) {
        // Device share is delivered by the Expansion SDK. Class and API names
        // are resolved dynamically to keep the pre-credential build runnable.
        val managerClass = firstClass(
            "com.thingclips.smart.extension.device.share.ThingDeviceShareManager",
            "com.thingclips.smart.bizbundle.device.share.ThingDeviceShareManager",
        )
        val manager = managerClass.getDeclaredConstructor().newInstance()
        val callback = callbackProxy(
            interfaces = listOf("com.thingclips.smart.sdk.api.IThingResultCallback"),
            onSuccess = { value ->
                val link = runCatching { getter(value, "getUrl").toString() }
                    .getOrElse { value.toString() }
                success(result, link)
            },
            onError = { code, message -> error(result, code, message) },
        )
        invoke(
            manager,
            "createShareInfo",
            call.argument<String>("deviceId").orEmpty(),
            1,
            homeId ?: 0L,
            0,
            1,
            callback,
        )
    }

    private fun checkFirmware(call: MethodCall, result: MethodChannel.Result) {
        val deviceId = call.argument<String>("deviceId").orEmpty()
        val ota = invokeStatic(sdkClass(), "newOTAInstance", deviceId)
            ?: throw IllegalStateException("当前 SDK 未提供 OTA 实例")
        val callback = callbackProxy(
            interfaces = listOf("com.thingclips.smart.sdk.api.IThingOtaInfoCallback"),
            onSuccess = { value ->
                val list = value as? List<*> ?: emptyList<Any>()
                val version = list.firstOrNull()?.let { runCatching { getter(it, "getVersion").toString() }.getOrNull() }
                success(result, version)
            },
            onError = { code, message -> error(result, code, message) },
        )
        invoke(ota, "getOtaInfo", callback)
    }

    private fun startFirmwareUpgrade(call: MethodCall, result: MethodChannel.Result) {
        val deviceId = call.argument<String>("deviceId").orEmpty()
        val ota = invokeStatic(sdkClass(), "newOTAInstance", deviceId)
            ?: throw IllegalStateException("当前 SDK 未提供 OTA 实例")
        val callback = resultCallback(result)
        invoke(ota, "startOta", callback)
    }

    private fun resultCallback(result: MethodChannel.Result): Any = callbackProxy(
        interfaces = listOf("com.thingclips.smart.sdk.api.IResultCallback"),
        onSuccess = { success(result, null) },
        onError = { code, message -> error(result, code, message) },
    )

    private fun callbackProxy(
        interfaces: List<String>,
        onSuccess: (Any) -> Unit,
        onError: (String, String) -> Unit,
    ): Any {
        val callbackClass = interfaces.firstNotNullOfOrNull { name ->
            runCatching { Class.forName(name) }.getOrNull()
        } ?: throw ClassNotFoundException("SDK callback not found: $interfaces")
        val delivered = AtomicBoolean(false)
        return Proxy.newProxyInstance(callbackClass.classLoader, arrayOf(callbackClass)) { _, method, args ->
            when (method.name) {
                "onSuccess", "onActiveSuccess" -> if (delivered.compareAndSet(false, true)) {
                    onSuccess(args?.firstOrNull() ?: Unit)
                }
                "onError", "onFailure" -> if (delivered.compareAndSet(false, true)) {
                    onError(args?.getOrNull(0)?.toString() ?: "sdk_error", args?.getOrNull(1)?.toString() ?: "SDK 调用失败")
                }
            }
            defaultValue(method.returnType)
        }
    }

    private fun userMap(user: Any): Map<String, Any?> = mapOf(
        "uid" to optionalGetter(user, "getUid"),
        "nickname" to (optionalGetter(user, "getNickName") ?: optionalGetter(user, "getNickname")),
        "account" to (optionalGetter(user, "getUsername") ?: optionalGetter(user, "getMobile") ?: optionalGetter(user, "getEmail")),
        "avatarUrl" to (optionalGetter(user, "getHeadPic") ?: optionalGetter(user, "getIconUrl")),
    )

    private fun deviceMap(device: Any): Map<String, Any?> = mapOf(
        "deviceId" to (optionalGetter(device, "getDevId") ?: optionalGetter(device, "getDeviceId")),
        "productId" to (optionalGetter(device, "getProductId") ?: optionalGetter(device, "getProductId")),
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

    private fun sdkClass(): Class<*> = Class.forName(sdkClassName)

    private fun firstClass(vararg names: String): Class<*> = names.firstNotNullOfOrNull { name ->
        runCatching { Class.forName(name) }.getOrNull()
    } ?: throw ClassNotFoundException(names.joinToString())

    private fun invokeStatic(clazz: Class<*>, name: String, vararg args: Any?): Any? =
        findMethod(clazz, name, args).invoke(null, *args)

    private fun invoke(target: Any, name: String, vararg args: Any?): Any? =
        findMethod(target.javaClass, name, args).invoke(target, *args)

    private fun getter(target: Any, name: String): Any =
        invoke(target, name) ?: throw IllegalStateException("$name returned null")

    private fun optionalGetter(target: Any, name: String): Any? = runCatching { invoke(target, name) }.getOrNull()

    private fun findMethod(clazz: Class<*>, name: String, args: Array<out Any?>): Method {
        val methods = (clazz.methods + clazz.declaredMethods).distinct()
        return methods.firstOrNull { method ->
            method.name == name && method.parameterTypes.size == args.size &&
                method.parameterTypes.zip(args).all { (type, value) -> compatible(type, value) }
        }?.apply { isAccessible = true }
            ?: throw NoSuchMethodException("${clazz.name}.$name(${args.joinToString { it?.javaClass?.simpleName ?: "null" }})")
    }

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
        val cause = if (throwable is InvocationTargetException) throwable.targetException else throwable
        val code = if (cause is ClassNotFoundException) "sdk_unavailable" else "native_error"
        error(result, code, cause.message ?: cause.javaClass.simpleName)
    }

    private fun isDebugBuild(): Boolean = runCatching {
        val clazz = Class.forName("${activity.packageName}.BuildConfig")
        clazz.getField("DEBUG").getBoolean(null)
    }.getOrDefault(false)
}
