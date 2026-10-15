package com.common.yikaltd

import android.util.Log

/** Application diagnostics follow the Dart build flag. */
internal object AppLog {
    fun i(tag: String, message: String) { if (BuildConfig.APP_DEBUG_TOOLS) Log.i(tag, message) }
    fun w(tag: String, message: String) { if (BuildConfig.APP_DEBUG_TOOLS) Log.w(tag, message) }
    fun e(tag: String, message: String) { if (BuildConfig.APP_DEBUG_TOOLS) Log.e(tag, message) }
}
