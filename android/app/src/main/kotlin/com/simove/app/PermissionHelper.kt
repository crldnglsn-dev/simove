package com.simove.app

import android.Manifest
import android.app.AppOpsManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

object PermissionHelper {
    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun hasOverlay(context: Context): Boolean = Settings.canDrawOverlays(context)

    fun hasNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun hasNotificationListener(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val expected = ComponentName(context, com.simove.app.notifications.AngkasNotificationListener::class.java)
        return enabled.split(':').any { value ->
            val component = ComponentName.unflattenFromString(value)
            component != null &&
                component.packageName == expected.packageName &&
                component.className == expected.className
        }
    }

    fun ignoresBatteryOptimisation(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun snapshot(context: Context, captureRunning: Boolean): Map<String, Any> {
        return mapOf(
            "notifications" to hasNotifications(context),
            "overlay" to hasOverlay(context),
            "usageAccess" to hasUsageAccess(context),
            "notificationListener" to hasNotificationListener(context),
            "batteryOptimizationIgnored" to ignoresBatteryOptimisation(context),
            "captureRunning" to captureRunning,
            "sdkInt" to Build.VERSION.SDK_INT,
        )
    }
}
