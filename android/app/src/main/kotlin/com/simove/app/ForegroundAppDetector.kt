package com.simove.app

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build

object ForegroundAppDetector {
    /**
     * How far back to look for the most recent "resumed" event. UsageStats
     * writes can be batched, and a 20 second window is often empty right after
     * an app switch, which used to make SIMOVE think usage access was missing.
     */
    private const val EVENT_LOOKBACK_MS = 2 * 60_000L
    private const val STATS_LOOKBACK_MS = 5 * 60_000L

    /**
     * Returns the package of the most recently resumed app, or null when usage
     * access is unavailable and no aggregated statistics can be read.
     */
    fun foregroundPackage(context: Context): String? {
        if (!PermissionHelper.hasUsageAccess(context)) return null
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return null
        val end = System.currentTimeMillis()

        runCatching {
            val events = manager.queryEvents(end - EVENT_LOOKBACK_MS, end)
            val event = UsageEvents.Event()
            var latest: String? = null
            var latestAt = 0L
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (isForegroundEvent(event) && !event.packageName.isNullOrBlank()) {
                    if (event.timeStamp >= latestAt) {
                        latest = event.packageName
                        latestAt = event.timeStamp
                    }
                }
            }
            if (latest != null) return latest
        }

        // Some devices only expose aggregated usage. The app used most
        // recently is the best available approximation of the foreground app.
        return runCatching {
            manager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                end - STATS_LOOKBACK_MS,
                end,
            )
                ?.asSequence()
                ?.filter { it.lastTimeUsed in 1..end }
                ?.maxByOrNull { it.lastTimeUsed }
                ?.packageName
        }.getOrNull()
    }

    private fun isForegroundEvent(event: UsageEvents.Event): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
        } else {
            @Suppress("DEPRECATION")
            event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
        }
    }

    fun matchesTarget(foreground: String?, target: String): Boolean {
        if (foreground.isNullOrBlank()) return false
        if (foreground == target) return true
        // The Angkas rider package has changed between releases. When the
        // target is an Angkas package, accept sibling Angkas packages so the
        // default configuration keeps working.
        if (target.startsWith("com.angkas.") && foreground.startsWith("com.angkas.")) {
            return true
        }
        return false
    }
}
