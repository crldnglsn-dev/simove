package com.simove.app

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel

/**
 * Single event sink shared by the foreground service, notification listener and
 * overlay. Events are delivered on the main thread to Flutter.
 */
object EventBridge {
    private const val TAG = "SimoveBridge"

    private val handler = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun setSink(value: EventChannel.EventSink?) {
        Log.d(TAG, "setSink attached=${value != null}")
        sink = value
    }

    fun hasSink(): Boolean = sink != null

    fun emit(event: Map<String, Any?>) {
        val attached = sink != null
        Log.d(TAG, "emit type=${event["type"]} attached=$attached")
        handler.post { sink?.success(event) }
    }

    fun emitError(message: String) {
        handler.post { sink?.error("simove", message, null) }
    }
}
