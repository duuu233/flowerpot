package com.common.yikaltd

import java.lang.reflect.Proxy

/** Decodes the OTA service callback and queried snapshot through the same contract. */
internal object TuyaOtaServiceBridge {
    fun create(
        listenerType: Class<*>,
        loader: ClassLoader,
        onStatus: (Any?) -> Unit,
        defaultValue: (Class<*>) -> Any?,
    ): Any = Proxy.newProxyInstance(loader, arrayOf(listenerType)) { proxy, method, args ->
        when (method.name) {
            "equals" -> proxy === args?.firstOrNull()
            "hashCode" -> System.identityHashCode(proxy)
            "toString" -> "TuyaOtaServiceListener(${listenerType.simpleName})"
            "firmwareUpgradeStatus" -> { onStatus(args?.firstOrNull()); defaultValue(method.returnType) }
            else -> defaultValue(method.returnType)
        }
    }

    fun status(bean: Any?): Int? {
        val status = getter(bean, "getStatus")
        return (status as? Number)?.toInt() ?: (getter(status, "getStatus") as? Number)?.toInt()
    }

    fun report(
        bean: Any?,
        deviceId: String,
        firmwareType: Int,
        onRunning: (Int?, Int?) -> Unit,
        onSuccess: (Any?) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        if (bean == null) return
        val reportedDevice = getter(bean, "getDevId")?.toString().orEmpty()
        if (reportedDevice.isNotEmpty() && reportedDevice != deviceId) return
        if ((getter(bean, "getFirmwareType") as? Number)?.toInt() != firmwareType) return
        val stage = status(bean)
        val errorCode = text(bean, "getErrorCode")
        val error = text(bean, "getErrorMsg") ?: text(bean, "getStatusText")
        // Weak-signal confirmation is never accepted automatically.
        if (errorCode == "5005") {
            onError(errorCode, error ?: "设备信号较弱，请改善网络后重新检查升级。")
            return
        }
        when (stage) {
            3 -> onSuccess(firmwareType)
            4 -> onError(errorCode ?: "ota_failed", error ?: "固件升级失败，请稍后重试。")
            7 -> onError(errorCode ?: "ota_timeout", error ?: "固件升级超时，请保持设备通电并稍后重新检查。")
            1, 2, 5, 6, 13, 14, 100 -> {
                // -1 is an absent percentage in the SDK, not a reset to zero.
                val percent = (getter(bean, "getProgress") as? Number)?.toInt()?.takeIf { it in 0..100 }
                onRunning(percent, stage)
            }
        }
    }

    private fun getter(bean: Any?, name: String): Any? = runCatching {
        bean?.javaClass?.getMethod(name)?.invoke(bean)
    }.getOrNull()
    private fun text(bean: Any?, name: String): String? = getter(bean, name)?.toString()?.takeIf { it.isNotBlank() }
}
