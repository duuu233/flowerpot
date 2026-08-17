-keep class com.alibaba.fastjson.** { *; }
-dontwarn com.alibaba.fastjson.**
-keep class com.thingclips.smart.mqttclient.mqttv3.** { *; }
-dontwarn com.thingclips.smart.mqttclient.mqttv3.**
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**
-keep class com.thingclips.** { *; }
-dontwarn com.thingclips.**

# Optional Flutter deferred-components APIs are absent because this app does
# not use Play Feature Delivery.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Tuya 7.8.0 packages optional Matter JSON and compile-time Hilt metadata that
# are not used by the current planter integration.
-dontwarn com.google.gson.JsonArray
-dontwarn com.google.gson.JsonElement
-dontwarn com.google.gson.JsonNull
-dontwarn com.google.gson.JsonObject
-dontwarn dagger.hilt.processor.internal.aggregateddeps.AggregatedDeps
