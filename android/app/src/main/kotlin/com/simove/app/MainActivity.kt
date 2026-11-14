package com.simove.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.simove.app.capture.ScreenCaptureService
import com.simove.app.overlay.OverlayService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val CAPTURE_REQUEST = 4801
        const val NOTIFICATION_REQUEST = 4802
        const val CHANNEL = "simove/control"
        const val EVENTS = "simove/events"
    }

    private var pendingCaptureResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    EventBridge.setSink(events)
                    if (ScreenCaptureService.isRunning()) {
                        EventBridge.emit(
                            mapOf(
                                "type" to "status",
                                "status" to "monitoring",
                                "message" to "Screen capture is already running",
                            ),
                        )
                    }
                }

                override fun onCancel(arguments: Any?) {
                    EventBridge.setSink(null)
                }
            },
        )

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPermissionStatus" -> result.success(
                    PermissionHelper.snapshot(this, ScreenCaptureService.isRunning()),
                )

                "startCapture" -> startCapture(result)
                "stopCapture" -> {
                    stopService(Intent(this, ScreenCaptureService::class.java))
                    ScreenCaptureService.clearLastObservation()
                    result.success(true)
                }

                "isCaptureRunning" -> result.success(ScreenCaptureService.isRunning())

                "setTargetPackage" -> {
                    val packageName = (call.arguments as? Map<*, *>)?.get("package") as? String
                    if (packageName.isNullOrBlank()) {
                        result.error("invalid_package", "A package name is required.", null)
                    } else {
                        SimovePrefs.setTargetPackage(this, packageName)
                        result.success(null)
                    }
                }

                "getLastOcr" -> {
                    val last = ScreenCaptureService.lastObservation()
                    result.success(last?.let { HashMap(it) })
                }

                "showOverlay", "updateOverlay" -> {
                    val data = (call.arguments as? Map<*, *>)?.entries
                        ?.associate { it.key.toString() to (it.value?.toString() ?: "") }
                        ?: emptyMap()
                    showOverlay(data, call.method == "showOverlay", result)
                }

                "hideOverlay" -> {
                    stopService(Intent(this, OverlayService::class.java))
                    result.success(null)
                }

                "openSettings" -> openSettings(
                    (call.arguments as? Map<*, *>)?.get("target") as? String,
                    result,
                )

                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            NOTIFICATION_REQUEST,
                        )
                    }
                    result.success(null)
                }

                "openTargetApp" -> openTargetApp(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun startCapture(result: MethodChannel.Result) {
        if (ScreenCaptureService.isRunning()) {
            result.success(true)
            return
        }
        if (pendingCaptureResult != null) {
            result.error("capture_pending", "Screen capture permission is already open.", null)
            return
        }
        val manager = getSystemService(MediaProjectionManager::class.java)
        if (manager == null) {
            result.error("no_projection", "Screen capture is not supported on this device.", null)
            return
        }
        pendingCaptureResult = result
        try {
            // Android 14+ defaults the consent dialog to "Share one app".
            // SIMOVE needs the whole display so it can see Angkas even when a
            // different app is in front. The rider can still switch the choice
            // in the dialog, so the setup screen explains it as well.
            val captureIntent =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    manager.createScreenCaptureIntent(
                        MediaProjectionConfig.createConfigForDefaultDisplay(),
                    )
                } else {
                    manager.createScreenCaptureIntent()
                }
            startActivityForResult(captureIntent, CAPTURE_REQUEST)
        } catch (error: Exception) {
            pendingCaptureResult = null
            result.error("capture_failed", error.message ?: "Could not open screen capture.", null)
        }
    }

    private fun showOverlay(
        data: Map<String, String>,
        forceShow: Boolean,
        result: MethodChannel.Result,
    ) {
        if (!Settings.canDrawOverlays(this)) {
            result.error(
                "overlay_permission",
                "Display over other apps permission is not granted.",
                null,
            )
            return
        }
        try {
            val intent = Intent(this, OverlayService::class.java).apply {
                action = if (forceShow) OverlayService.ACTION_SHOW else OverlayService.ACTION_UPDATE
                data.forEach { (key, value) -> putExtra(key, value) }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("overlay_failed", error.message ?: "Could not show overlay.", null)
        }
    }

    private fun openSettings(target: String?, result: MethodChannel.Result) {
        val intent = when (target) {
            "overlay" -> Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            )

            "usage" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)

            "notificationListener" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)

            "battery" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)

            "notifications" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    !PermissionHelper.hasNotifications(this)
                ) {
                    requestPermissions(
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        NOTIFICATION_REQUEST,
                    )
                    result.success(null)
                    return
                }
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }

            else -> Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
        }
        try {
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("settings_failed", error.message ?: "Could not open settings.", null)
        }
    }

    private fun openTargetApp(result: MethodChannel.Result) {
        val target = SimovePrefs.targetPackage(this)
        val launch = packageManager.getLaunchIntentForPackage(target)
        if (launch == null) {
            result.error(
                "not_installed",
                "The Angkas app ($target) is not installed on this device.",
                null,
            )
            return
        }
        try {
            startActivity(launch)
            result.success(null)
        } catch (error: Exception) {
            result.error("launch_failed", error.message ?: "Could not open Angkas.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CAPTURE_REQUEST) return
        val pending = pendingCaptureResult
        pendingCaptureResult = null
        if (resultCode == Activity.RESULT_OK && data != null) {
            try {
                val intent = Intent(this, ScreenCaptureService::class.java).apply {
                    action = ScreenCaptureService.ACTION_START
                    putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(ScreenCaptureService.EXTRA_DATA, data)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                pending?.success(true)
            } catch (error: Exception) {
                pending?.error(
                    "capture_failed",
                    error.message ?: "Could not start screen capture.",
                    null,
                )
            }
        } else {
            pending?.success(false)
        }
    }

    override fun onDestroy() {
        EventBridge.setSink(null)
        super.onDestroy()
    }
}
