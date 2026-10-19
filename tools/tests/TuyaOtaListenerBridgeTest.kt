package com.common.yikaltd

import com.thingclips.smart.sdk.api.IOtaListener
import com.thingclips.smart.sdk.bean.OTAErrorMessageBean

// Run with the real Home SDK device-api classes.jar on the JVM classpath.
fun main() {
    val running = mutableListOf<Pair<Int?, Int?>>()
    val successes = mutableListOf<Any?>()
    val errors = mutableListOf<Pair<String, String>>()
    val listener = TuyaOtaListenerBridge.create(
        IOtaListener::class.java,
        IOtaListener::class.java.classLoader,
        onRunning = { percent, stage -> running.add(percent to stage) },
        onSuccess = { successes.add(it) },
        onError = { code, message -> errors.add(code to message) },
        defaultValue = { null },
    ) as IOtaListener
    var checks = 0
    fun verify(condition: Boolean) { check(condition); checks++ }

    listener.onProgress(1, 42)
    verify(running.single() == (42 to null))
    listener.onStatusChanged(6, 1)
    verify(running.last() == (null to 6))
    for (stage in listOf(2, 5, 13, 14, 100)) {
        listener.onStatusChanged(stage, 1)
        verify(running.last() == (null to stage))
    }
    val count = running.size
    listener.onStatusChanged(0, 1)
    verify(running.size == count)
    listener.onTimeout(1)
    verify(errors.last().first == "ota_timeout")
    verify(errors.last().second.contains("升级超时"))
    listener.onFailure(1, "E101", "download failed")
    verify(errors.last() == ("E101" to "download failed"))
    listener.onFailure(1, "", "")
    verify(errors.last() == ("ota_failed" to "固件升级失败"))

    val bean = OTAErrorMessageBean()
    bean.title = "安装失败"
    bean.text = "包校验失败"
    listener.onFailureWithText(1, "E102", bean)
    verify(errors.last() == ("E102" to "包校验失败"))
    bean.text = " "
    listener.onFailureWithText(1, "E103", bean)
    verify(errors.last() == ("E103" to "安装失败"))
    bean.title = ""
    listener.onFailureWithText(1, "", bean)
    verify(errors.last() == ("ota_failed" to "固件升级失败，请稍后重试。"))
    listener.onFailureWithText(1, "E104", null)
    verify(errors.last() == ("E104" to "固件升级失败，请稍后重试。"))
    listener.onSuccess(1)
    verify(successes.single() == 1)
    listener.onStatusChanged(3, 9)
    verify(successes.last() == 9)
    listener.onStatusChanged(4, 9)
    verify(errors.last().first == "ota_failed")
    listener.onStatusChanged(7, 9)
    verify(errors.last().first == "ota_timeout")
    verify(listener == listener)
    verify(listener != Any())
    verify(listener.hashCode() == System.identityHashCode(listener))
    verify(listener.toString().contains("IOtaListener"))

    val legacy = TuyaOtaListenerBridge.create(
        LegacyOtaListener::class.java, LegacyOtaListener::class.java.classLoader,
        onRunning = { percent, stage -> running.add(percent to stage) },
        onSuccess = { successes.add(it) },
        onError = { code, message -> errors.add(code to message) },
        defaultValue = { null },
    ) as LegacyOtaListener
    legacy.onError("legacy", "legacy failure")
    verify(errors.last() == ("legacy" to "legacy failure"))
    legacy.onProgress(55)
    verify(running.last() == (55 to null))
    println("$checks OTA bridge assertions passed against SDK 7.5.1 IOtaListener")
}

interface LegacyOtaListener {
    fun onError(code: String, message: String)
    fun onProgress(percent: Int)
}
