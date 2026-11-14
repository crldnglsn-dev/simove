package com.simove.app.overlay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.simove.app.MainActivity
import com.simove.app.R
import com.simove.app.SimovePrefs
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Small movable earnings card shown over other apps. Values are pushed from
 * Flutter after every recorded transaction.
 */
class OverlayService : Service() {
    companion object {
        const val ACTION_SHOW = "com.simove.app.action.SHOW_OVERLAY"
        const val ACTION_UPDATE = "com.simove.app.action.UPDATE_OVERLAY"

        private const val CHANNEL_ID = "simove_overlay"
        private const val NOTIFICATION_ID = 4811

        @Volatile
        private var running = false

        fun isRunning(): Boolean = running
    }

    private lateinit var windowManager: WindowManager
    private var container: LinearLayout? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var todayView: TextView? = null
    private var latestView: TextView? = null
    private var statusView: TextView? = null
    private var notificationText: String = "₱0.00"

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForegroundCompat()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        val values = readValues(intent)
        SimovePrefs.saveOverlayValues(this, values)
        if (container == null) addOverlay()
        updateValues(values)
        updateNotification(values["today"] ?: "₱0.00")
        return START_STICKY
    }

    private fun readValues(intent: Intent?): Map<String, String> {
        val stored = SimovePrefs.overlayValues(this)
        if (intent == null) return stored
        fun value(key: String): String =
            intent.getStringExtra(key) ?: stored[key] ?: ""
        return mapOf(
            "today" to value("today"),
            "latest" to value("latest"),
            "status" to value("status"),
            "reference" to value("reference"),
        )
    }

    private fun addOverlay() {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(11), dp(14), dp(12))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(18).toFloat()
                setColor(Color.parseColor("#F20C172A"))
                setStroke(dp(1), Color.parseColor("#5522D3EE"))
            }
            elevation = dp(8).toFloat()
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val brand = TextView(this).apply {
            text = "SIMOVE"
            setTextColor(Color.parseColor("#22D3EE"))
            textSize = 9f
            letterSpacing = 0.14f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        val close = TextView(this).apply {
            text = "×"
            setTextColor(Color.parseColor("#94A3B8"))
            textSize = 18f
            setPadding(dp(10), 0, dp(2), dp(4))
            setOnClickListener { stopSelf() }
        }
        header.addView(brand)
        header.addView(close)

        val label = TextView(this).apply {
            text = "TODAY"
            setTextColor(Color.parseColor("#64748B"))
            textSize = 8f
            letterSpacing = 0.12f
            setPadding(0, dp(6), 0, 0)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
        val today = TextView(this).apply {
            text = "₱0.00"
            setTextColor(Color.parseColor("#F1F5F9"))
            textSize = 24f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            includeFontPadding = false
        }
        val latest = TextView(this).apply {
            text = "Latest —"
            setTextColor(Color.parseColor("#94A3B8"))
            textSize = 10f
            setPadding(0, dp(3), 0, 0)
        }
        val status = TextView(this).apply {
            text = "Monitoring off"
            setTextColor(Color.parseColor("#34D399"))
            textSize = 9f
            setPadding(0, dp(4), 0, 0)
        }

        card.addView(header)
        card.addView(label)
        card.addView(today)
        card.addView(latest)
        card.addView(status)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(16)
            y = dp(160)
        }

        var startX = 0
        var startY = 0
        var downX = 0f
        var downY = 0f
        var moved = false

        card.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    downX = event.rawX
                    downY = event.rawY
                    moved = false
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).roundToInt()
                    val dy = (event.rawY - downY).roundToInt()
                    if (abs(dx) > dp(4) || abs(dy) > dp(4)) moved = true
                    params.x = startX + dx
                    params.y = startY + dy
                    try {
                        windowManager.updateViewLayout(card, params)
                    } catch (_: Exception) {
                    }
                    true
                }

                MotionEvent.ACTION_UP -> {
                    if (!moved) openApp()
                    true
                }

                MotionEvent.ACTION_CANCEL -> true
                else -> false
            }
        }

        try {
            windowManager.addView(card, params)
            container = card
            layoutParams = params
            todayView = today
            latestView = latest
            statusView = status
        } catch (error: Exception) {
            stopSelf()
        }
    }

    private fun updateValues(values: Map<String, String>) {
        todayView?.text = values["today"] ?: "₱0.00"
        latestView?.text = "Latest ${values["latest"] ?: "—"}"
        statusView?.text = values["status"] ?: "Monitoring"
        val reference = values["reference"].orEmpty()
        if (reference.isNotEmpty()) {
            latestView?.text = "Latest ${values["latest"] ?: "—"} • $reference"
        }
        notificationText = values["today"] ?: "₱0.00"
    }

    private fun openApp() {
        try {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
        }
    }

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SIMOVE floating tracker",
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = "Keeps the optional floating earnings card available"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("SIMOVE tracker")
            .setContentText("Today: $notificationText")
            .setSmallIcon(R.drawable.ic_stat_simove)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openApp)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun startForegroundCompat() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(today: String) {
        notificationText = today
        try {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        running = false
        try {
            container?.let { windowManager.removeView(it) }
        } catch (_: Exception) {
        }
        container = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).roundToInt()
}
