package com.common.yikaltd

import java.lang.reflect.Proxy

/** Maps the SDK's OTA callbacks without depending on Android lifecycle objects. */
internal object TuyaOtaListenerBridge {
    fun create(
        listenerType: Class<*>,
        loader: ClassLoader,
        onRunning: (Int?, Int?) -> Unit,
        onSuccess: (Any?) -> Unit,
        onError: (String, String) -> Unit,
        defaultValue: (Class<*>) -> Any?,
    ): Any = Proxy.newProxyInstance(loader, arrayOf(listenerType)) { proxy, method, args ->
        when (method.name) {
            "equals" -> proxy === args?.firstOrNull()
            "hashCode" -> System.identityHashCode(proxy)
            "toString" -> "TuyaOtaListener(${listenerType.simpleName})"
            "onProgress" -> {
                // IOtaListener.onProgress(otaType, progress).
                onRunning(args?.filterIsInstance<Number>()?.lastOrNull()?.toInt(), null)
                defaultValue(method.returnType)
            }
            "onStatusChanged" -> {
                val stage = (args?.firstOrNull() as? Number)?.toInt()
                if (stage != null && stage in setOf(2, 5, 6, 13, 14, 100)) {
                    onRunning(null, stage)
                }
                defaultValue(method.returnType)
            }
            "onSuccess" -> {
                onSuccess(args?.firstOrNull())
                defaultValue(method.returnType)
            }
            "onTimeout" -> {
                onError("ota_timeout", "固件升级超时，请保持设备通电并稍后重新检查。")
                defaultValue(method.returnType)
            }
            "onFailureWithText" -> {
                val code = (args?.getOrNull(1) as? String)?.takeIf { it.isNotBlank() }
                    ?: "ota_failed"
                val bean = args?.getOrNull(2)
                val message = beanText(bean, "getText") ?: beanText(bean, "getTitle")
                    ?: "固件升级失败，请稍后重试。"
                onError(code, message)
                defaultValue(method.returnType)
            }
            "onFailure", "onError" -> {
                val texts = args?.filterIsInstance<String>().orEmpty()
                onError(
                    texts.firstOrNull()?.takeIf { it.isNotBlank() } ?: "ota_failed",
                    texts.getOrNull(1)?.takeIf { it.isNotBlank() } ?: "固件升级失败",
                )
                defaultValue(method.returnType)
            }
            else -> defaultValue(method.returnType)
        }
    }

    private fun beanText(bean: Any?, method: String): String? = runCatching {
        (bean?.javaClass?.getMethod(method)?.invoke(bean) as? String)
            ?.takeIf { it.isNotBlank() }
    }.getOrNull()
}
