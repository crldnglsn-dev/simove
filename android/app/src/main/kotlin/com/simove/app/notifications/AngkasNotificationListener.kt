package com.simove.app.notifications

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.simove.app.EventBridge
import com.simove.app.SimovePrefs

/**
 * Optional hint source. Only a coarse event name is forwarded — notification
 * text is inspected in memory and then discarded, never stored.
 */
class AngkasNotificationListener : NotificationListenerService() {
    private var lastHash = 0
    private var lastAt = 0L

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        val target = SimovePrefs.targetPackage(this)
        if (!notification.packageName.startsWith(target.substringBeforeLast('.'))) return

        val extras = notification.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty() +
                " " +
                extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
            ).lowercase()
        if (title.isBlank() && text.isBlank()) return

        val combined = "$title $text".lowercase()
        val event = when {
            combined.contains("auto-accepted") ||
                combined.contains("auto accepted") ||
                combined.contains("booking accepted") ||
                combined.contains("proceed to pickup") -> "booking_accepted"

            combined.contains("trip completed") ||
                combined.contains("ride completed") ||
                combined.contains("payment received") -> "trip_update"

            combined.contains("earning") || combined.contains("fare") -> "earnings_update"

            else -> return
        }

        val now = System.currentTimeMillis()
        val hash = combined.hashCode()
        if (hash == lastHash && now - lastAt < 5_000) return
        lastHash = hash
        lastAt = now

        EventBridge.emit(
            mapOf(
                "type" to "notification",
                "event" to event,
            ),
        )
    }
}
