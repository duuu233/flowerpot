package com.common.yikaltd

import com.thingclips.smart.sdk.api.IDevOTAListener
import com.thingclips.smart.device.bean.ThingDevUpgradeStatusBean
import com.thingclips.sdk.device.enums.DevUpgradeStatusEnum

fun main() {
    val running = mutableListOf<Pair<Int?, Int?>>()
    val successes = mutableListOf<Any?>()
    val errors = mutableListOf<Pair<String, String>>()
    var checks = 0
    fun verify(ok: Boolean) { check(ok); checks++ }
    val report: (Any?) -> Unit = { bean -> TuyaOtaServiceBridge.report(bean, "device-test", 9,
        { percent, stage -> running.add(percent to stage) }, { successes.add(it) }, { code, message -> errors.add(code to message) }) }
    val listener = TuyaOtaServiceBridge.create(IDevOTAListener::class.java,
        IDevOTAListener::class.java.classLoader, report, { null }) as IDevOTAListener
    val bean = ThingDevUpgradeStatusBean()
    bean.devId = "device-test"; bean.firmwareType = 9
    for (stage in listOf(1, 2, 5, 6, 13, 14, 100)) {
        bean.status = DevUpgradeStatusEnum.to(stage); bean.progress = -1
        listener.firmwareUpgradeStatus(bean)
        verify(running.last() == (null to stage))
    }
    bean.status = DevUpgradeStatusEnum.UPGRADING; bean.progress = 46
    listener.firmwareUpgradeStatus(bean); verify(running.last() == (46 to 2))
    bean.progress = 101; listener.firmwareUpgradeStatus(bean); verify(running.last() == (null to 2))
    val count = running.size
    bean.devId = "different-device"; listener.firmwareUpgradeStatus(bean); verify(running.size == count)
    bean.devId = "device-test"; bean.firmwareType = 0; listener.firmwareUpgradeStatus(bean); verify(running.size == count)
    bean.firmwareType = 9; bean.status = DevUpgradeStatusEnum.SUCCESS
    listener.firmwareUpgradeStatus(bean); verify(successes.single() == 9)
    bean.status = DevUpgradeStatusEnum.FAILURE; bean.errorCode = "5018"; bean.errorMsg = "包校验失败"
    listener.firmwareUpgradeStatus(bean); verify(errors.last() == ("5018" to "包校验失败"))
    bean.errorCode = null; bean.errorMsg = null; bean.statusText = null
    bean.status = DevUpgradeStatusEnum.TIMEOUT; listener.firmwareUpgradeStatus(bean)
    verify(errors.last().first == "ota_timeout")
    verify(errors.last().second.contains("超时"))
    bean.status = DevUpgradeStatusEnum.LOCALPREPARE; bean.errorCode = "5005"
    listener.firmwareUpgradeStatus(bean); verify(errors.last().first == "5005")
    verify(listener == listener); verify(listener != Any())
    verify(listener.hashCode() == System.identityHashCode(listener))
    verify(listener.toString().contains("TuyaOtaServiceListener"))
    report(null); verify(errors.size == 3)
    println("PASS $checks OTA service callback checks against the actual SDK")
}
