package com.simove.app.capture

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.simove.app.EventBridge
import com.simove.app.ForegroundAppDetector
import com.simove.app.MainActivity
import com.simove.app.PermissionHelper
import com.simove.app.R
import com.simove.app.SimovePrefs
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

/**
 * Captures the visible screen through MediaProjection and runs ML Kit OCR only
 * while Angkas is in the foreground. Frames are never written to disk.
 */
class ScreenCaptureService : Service() {
    companion object {
        const val ACTION_START = "com.simove.app.action.START_CAPTURE"
        const val ACTION_STOP = "com.simove.app.action.STOP_CAPTURE"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_DATA = "projection_data"

        private const val CHANNEL_ID = "simove_monitoring"
        private const val NOTIFICATION_ID = 4810
        private const val TAG = "SimoveCapture"
        private const val FRAME_INTERVAL_MS = 1_200L
        private const val HASH_INTERVAL_MS = 1_200L

        @Volatile
        private var running = false

        @Volatile
        private var _lastObservation: Map<String, Any?>? = null

        fun isRunning(): Boolean = running

        fun lastObservation(): Map<String, Any?>? = _lastObservation

        fun clearLastObservation() {
            _lastObservation = null
        }
    }

    private lateinit var handlerThread: HandlerThread
    private lateinit var handler: Handler
    private val processing = AtomicBoolean(false)
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var recognizer: TextRecognizer? = null

    private var lastFrameHash = 0
    private var lastFrameAt = 0L
    private var lastStatusKey: String? = null
    private var lastStatusAt = 0L
    private var frameId = 0L
    private var destroyed = false
    private var lastNotificationText: String? = null

    override fun onCreate() {
        super.onCreate()
        handlerThread = HandlerThread("simove-capture").also { it.start() }
        handler = Handler(handlerThread.looper)
        recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_START -> {
                if (running) return START_NOT_STICKY
                startForegroundCompat(
                    "SIMOVE is monitoring",
                    "Waiting for the Angkas booking screen",
                )
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                val data = projectionData(intent)
                if (resultCode != Activity.RESULT_OK || data == null) {
                    fail("Screen capture permission data is missing.")
                    return START_NOT_STICKY
                }
                startProjection(resultCode, data)
            }

            else -> {
                if (!running) stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    private fun projectionData(intent: Intent): Intent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            intent.getParcelableExtra(EXTRA_DATA)
        }
    }

    private fun startProjection(resultCode: Int, data: Intent) {
        try {
            val manager = getSystemService(MediaProjectionManager::class.java)
            val mediaProjection = manager.getMediaProjection(resultCode, data)
            if (mediaProjection == null) {
                fail("Android did not provide a screen capture session.")
                return
            }
            projection = mediaProjection
            mediaProjection.registerCallback(
                object : MediaProjection.Callback() {
                    override fun onStop() {
                        if (destroyed) return
                        emitStatus("stopped", "Screen capture was stopped by Android")
                        stopSelf()
                    }
                },
                handler,
            )

            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                .defaultDisplay
                .getRealMetrics(metrics)
            val width = metrics.widthPixels
            val height = metrics.heightPixels
            val density = metrics.densityDpi

            val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            reader.setOnImageAvailableListener(
                { source ->
                    // A single unreadable frame must never take down monitoring.
                    try {
                        handleFrame(source)
                    } catch (error: Throwable) {
                        Log.e(TAG, "Frame processing failed", error)
                        emitStatusThrottled(
                            "paused",
                            "Could not read this screen frame: ${error.message}",
                        )
                    }
                },
                handler,
            )
            imageReader = reader

            virtualDisplay = mediaProjection.createVirtualDisplay(
                "simove-screen",
                width,
                height,
                density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface,
                null,
                handler,
            )
            running = true
            updateNotification("SIMOVE is monitoring", "Waiting for the Angkas booking screen")
            emitStatus("monitoring", "Screen capture started — waiting for Angkas")
        } catch (error: Exception) {
            fail(error.message ?: "Could not start screen capture.")
        }
    }

    private fun handleFrame(reader: ImageReader) {
        val image = try {
            reader.acquireLatestImage()
        } catch (error: Exception) {
            null
        } ?: return

        if (destroyed || !running) {
            image.close()
            return
        }
        val now = SystemClock.elapsedRealtime()
        if (processing.get() || now - lastFrameAt < FRAME_INTERVAL_MS) {
            image.close()
            return
        }
        if (!isScreenOn()) {
            image.close()
            return
        }

        val target = SimovePrefs.targetPackage(this)
        val foreground = ForegroundAppDetector.foregroundPackage(this)
        if (foreground == null) {
            image.close()
            emitStatusThrottled(
                "permission_required",
                "Allow usage access so SIMOVE can detect when Angkas is open.",
            )
            return
        }
        if (!ForegroundAppDetector.matchesTarget(foreground, target)) {
            image.close()
            emitStatusThrottled(
                "monitoring",
                "Waiting for Angkas (foreground: $foreground)",
            )
            return
        }

        val hash = frameHash(image)
        if (hash == lastFrameHash) {
            image.close()
            return
        }
        lastFrameHash = hash
        lastFrameAt = now

        val textRecognizer = recognizer
        if (textRecognizer == null) {
            image.close()
            return
        }

        processing.set(true)
        val width = image.width
        val height = image.height
        // MediaProjection's ImageReader delivers RGBA_8888 frames, but ML Kit's
        // InputImage.fromMediaImage only accepts JPEG/YUV images. Copy the
        // frame into a Bitmap instead. The bitmap is recycled on completion.
        val bitmap = try {
            imageToBitmap(image)
        } catch (error: Throwable) {
            Log.e(TAG, "Could not convert screen frame", error)
            null
        }
        if (bitmap == null) {
            processing.set(false)
            image.close()
            emitStatusThrottled("paused", "Could not read this screen frame.")
            return
        }
        val input = InputImage.fromBitmap(bitmap, 0)
        textRecognizer.process(input)
            .addOnSuccessListener { text ->
                publishObservation(text, foreground, width, height)
            }
            .addOnFailureListener { error ->
                emitStatusThrottled("paused", "OCR could not read this frame: ${error.message}")
            }
            .addOnCompleteListener {
                processing.set(false)
                image.close()
                bitmap.recycle()
            }
    }

    /**
     * Copies an RGBA_8888 [Image] into an ARGB Bitmap, removing the row padding
     * that screen capture frames normally contain.
     */
    private fun imageToBitmap(image: Image): Bitmap {
        val plane = image.planes.firstOrNull()
            ?: throw IllegalStateException("Screen frame has no pixel plane")
        val buffer = plane.buffer
        buffer.rewind()
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * image.width
        val paddedWidth = image.width + rowPadding / pixelStride
        val padded = Bitmap.createBitmap(paddedWidth, image.height, Bitmap.Config.ARGB_8888)
        padded.copyPixelsFromBuffer(buffer)
        if (paddedWidth == image.width) return padded
        val cropped = Bitmap.createBitmap(padded, 0, 0, image.width, image.height)
        padded.recycle()
        return cropped
    }

    private fun publishObservation(
        text: Text,
        packageName: String,
        width: Int,
        height: Int,
    ) {
        if (destroyed) return
        val lines = ArrayList<Map<String, Any?>>()
        for (block in text.textBlocks) {
            for (line in block.lines) {
                val box = line.boundingBox ?: continue
                if (line.text.isBlank()) continue
                var confidenceSum = 0.0
                var confidenceCount = 0
                for (element in line.elements) {
                    val confidence = element.confidence
                    if (confidence != null) {
                        confidenceSum += confidence.toDouble()
                        confidenceCount++
                    }
                }
                lines.add(
                    mapOf(
                        "text" to line.text,
                        "left" to box.left.toDouble(),
                        "top" to box.top.toDouble(),
                        "right" to box.right.toDouble(),
                        "bottom" to box.bottom.toDouble(),
                        "confidence" to if (confidenceCount > 0) {
                            confidenceSum / confidenceCount
                        } else {
                            null
                        },
                    ),
                )
            }
        }
        frameId++
        val observation = hashMapOf<String, Any?>(
            "type" to "ocr",
            "timestamp" to System.currentTimeMillis(),
            "packageName" to packageName,
            "screenWidth" to width,
            "screenHeight" to height,
            "frameId" to frameId,
            "lines" to lines,
        )
        _lastObservation = observation
        Log.d(TAG, "ocr frame=$frameId lines=${lines.size} screen=${width}x$height")
        EventBridge.emit(observation)
        if (lastNotificationText != "Reading Angkas booking screen") {
            lastNotificationText = "Reading Angkas booking screen"
            updateNotification("SIMOVE is monitoring", "Reading the visible Angkas screen")
        }
    }

    private fun frameHash(image: Image): Int {
        val plane = image.planes.firstOrNull() ?: return 0
        val buffer = plane.buffer
        val limit = buffer.limit()
        val step = max(1, limit / 3072)
        var hash = 17
        var index = 0
        while (index < limit) {
            hash = hash * 31 + buffer.get(index)
            index += step
        }
        return hash
    }

    private fun isScreenOn(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isInteractive
    }

    private fun emitStatusThrottled(status: String, message: String) {
        val now = System.currentTimeMillis()
        val key = "$status|$message"
        if (key == lastStatusKey && now - lastStatusAt < 20_000) return
        lastStatusKey = key
        lastStatusAt = now
        Log.d(TAG, "status=$status :: $message")
        EventBridge.emit(
            mapOf(
                "type" to "status",
                "status" to status,
                "message" to message,
                "foregroundPackage" to ForegroundAppDetector.foregroundPackage(this),
            ),
        )
        if (status == "monitoring" && lastNotificationText != message) {
            lastNotificationText = message
            updateNotification("SIMOVE is monitoring", message)
        }
    }

    private fun emitStatus(status: String, message: String) {
        EventBridge.emit(
            mapOf(
                "type" to "status",
                "status" to status,
                "message" to message,
            ),
        )
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SIMOVE monitoring",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shown while SIMOVE is reading the visible Angkas screen"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, text: String): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, ScreenCaptureService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_simove)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(openApp)
            .addAction(Notification.Action.Builder(R.drawable.ic_stat_simove, "Stop monitoring", stop).build())
            .build()
    }

    private fun startForegroundCompat(title: String, text: String) {
        val notification = buildNotification(title, text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(title: String, text: String) {
        if (!running && !destroyed) return
        try {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification(title, text))
        } catch (_: Exception) {
            // The service may already be shutting down.
        }
    }

    private fun fail(message: String) {
        EventBridge.emit(
            mapOf(
                "type" to "error",
                "status" to "error",
                "message" to message,
            ),
        )
        running = false
        stopSelf()
    }

    override fun onDestroy() {
        destroyed = true
        running = false
        _lastObservation = null
        try {
            imageReader?.setOnImageAvailableListener(null, null)
        } catch (_: Exception) {
        }
        try {
            imageReader?.close()
        } catch (_: Exception) {
        }
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {
        }
        try {
            projection?.stop()
        } catch (_: Exception) {
        }
        imageReader = null
        virtualDisplay = null
        projection = null
        try {
            recognizer?.close()
        } catch (_: Exception) {
        }
        recognizer = null
        handlerThread.quitSafely()
        emitStatus("stopped", "Monitoring stopped")
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
