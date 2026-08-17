package com.common.yikaltd

import android.app.Application
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.lang.reflect.InvocationTargetException

internal const val TUYA_LOG_TAG = "FlowerpotTuya"

/**
 * Smart Life App SDK requires `ThingHomeSdk.init` to run from
 * `Application.onCreate` before any other SDK call, so the app-level entry
 * point owns initialization instead of the Flutter bridge.
 *
 * Initialization is deliberately best-effort: a build without the app-specific
 * security AAR, without credentials, or on an unsupported ABI must still start
 * so the Flutter UI and the mock backend keep working. The failure reason is
 * recorded and reported to Dart through the method channel instead of crashing
 * the process.
 */
class FlowerpotApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        TuyaSdkInitializer.ensureInitialized(this)
    }
}

internal object TuyaSdkInitializer {
    private const val HOME_SDK_CLASS = "com.thingclips.smart.home.sdk.ThingHomeSdk"
    private const val OPTIMUS_SDK_CLASS = "com.thingclips.smart.optimus.sdk.ThingOptimusSdk"

    /** ABIs shipped by the Tuya security component and the Home SDK native libs. */
    private val supportedAbis = setOf("arm64-v8a", "armeabi-v7a")

    /** `ThingHomeSdk.init` must never run twice in one process. */
    @Volatile
    private var initCalled = false

    @Volatile
    var ready: Boolean = false
        private set

    @Volatile
    var failureCode: String? = null
        private set

    @Volatile
    var failureMessage: String? = null
        private set

    /** Whether the Tuya SDK was compiled into this build at all. */
    val linked: Boolean
        get() = homeSdkClass() != null

    fun homeSdkClass(): Class<*>? = runCatching { Class.forName(HOME_SDK_CLASS) }.getOrNull()

    @Synchronized
    fun ensureInitialized(application: Application): Boolean {
        if (ready) return true
        if (initCalled) return false

        val sdk = homeSdkClass()
        if (sdk == null) {
            return record(
                "sdk_unavailable",
                "本次构建未编入涂鸦 SDK：请把 security-algorithm.aar 放到 android/app/libs/ 后重新构建",
            )
        }
        if (!hasCredentials(application)) {
            return record(
                "credentials_missing",
                "请在 android/local.properties 配置 tuya.appKey 与 tuya.appSecret 后重新构建",
            )
        }
        if (!hasCompatibleAbi()) {
            return record(
                "sdk_abi_unsupported",
                "涂鸦安全组件只提供 armeabi-v7a 与 arm64-v8a；当前设备 ABI 为 " +
                    "${Build.SUPPORTED_ABIS.joinToString()}，请改用支持 ARM 转译的模拟器镜像或真机",
            )
        }

        initCalled = true
        return try {
            sdk.getMethod("init", Application::class.java).invoke(null, application)
            Log.i(TUYA_LOG_TAG, "ThingHomeSdk.init returned successfully")
            initExpansionSdk(application)
            runCatching {
                sdk.getMethod("setDebugMode", java.lang.Boolean.TYPE)
                    .invoke(null, isDebugBuild(application))
            }
            ready = true
            failureCode = null
            failureMessage = null
            true
        } catch (throwable: Throwable) {
            val cause = unwrap(throwable)
            Log.e(TUYA_LOG_TAG, "ThingHomeSdk.init failed: ${cause.javaClass.simpleName}")
            val (code, message) = describe(cause)
            record(code, message)
        }
    }

    /**
     * Maps SDK throwables to stable codes the Flutter layer can branch on.
     * Messages never contain the AppKey, AppSecret or signing material.
     */
    fun describe(throwable: Throwable): Pair<String, String> = when (throwable) {
        is ClassNotFoundException -> "sdk_unavailable" to
            (throwable.message ?: "涂鸦 SDK 不可用")
        is UnsatisfiedLinkError -> "sdk_abi_unsupported" to
            ("涂鸦原生库无法在当前 ABI 加载（${Build.SUPPORTED_ABIS.joinToString()}），" +
                "请改用支持 ARM 转译的模拟器镜像或真机")
        is javax.crypto.AEADBadTagException -> "security_component_mismatch" to
            "涂鸦安全组件与 AppKey、AppSecret、包名或签名不匹配，请核对平台配置后重新下载安全组件"
        else -> {
            val nested = generateSequence(throwable.cause) { it.cause }
                .take(5)
                .firstOrNull { it is javax.crypto.AEADBadTagException || it is UnsatisfiedLinkError }
            if (nested != null) {
                describe(nested)
            } else {
                "native_error" to (throwable.message ?: throwable.javaClass.simpleName)
            }
        }
    }

    fun unwrap(throwable: Throwable): Throwable =
        if (throwable is InvocationTargetException) throwable.targetException else throwable

    private fun initExpansionSdk(application: Application) {
        val optimus = runCatching { Class.forName(OPTIMUS_SDK_CLASS) }.getOrNull()
        if (optimus == null) {
            Log.w(TUYA_LOG_TAG, "ThingOptimusSdk is unavailable; expansion features stay off")
            return
        }
        runCatching {
            optimus.getMethod("init", Context::class.java)
                .invoke(null, application)
            Log.i(TUYA_LOG_TAG, "ThingOptimusSdk.init returned successfully")
        }.onFailure {
            Log.w(TUYA_LOG_TAG, "ThingOptimusSdk.init failed: ${unwrap(it).javaClass.simpleName}")
        }
    }

    private fun hasCredentials(application: Application): Boolean {
        val metadata = runCatching {
            application.packageManager
                .getApplicationInfo(application.packageName, PackageManager.GET_META_DATA)
                .metaData
        }.getOrNull()
        val key = metadata?.getString("THING_SMART_APPKEY").orEmpty()
        val secret = metadata?.getString("THING_SMART_SECRET").orEmpty()
        return key.isNotBlank() && secret.isNotBlank()
    }

    private fun hasCompatibleAbi(): Boolean =
        Build.SUPPORTED_ABIS.any { supportedAbis.contains(it) }

    private fun isDebugBuild(application: Application): Boolean =
        (application.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun record(code: String, message: String): Boolean {
        failureCode = code
        failureMessage = message
        ready = false
        Log.w(TUYA_LOG_TAG, "Tuya SDK is not ready: $code")
        return false
    }
}
