package com.example.quizsync_android.capture

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
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import io.flutter.Log
import java.io.ByteArrayOutputStream

/**
 * 截屏主路径（用户已定，SPEC 3.2）：常驻前台服务复用**同一个**
 * MediaProjection / VirtualDisplay / ImageReader 会话。
 * - foregroundServiceType="mediaProjection"（Android 14 硬性要求）；
 * - MediaProjection.Callback.onStop 清状态并通知 Dart 重新授权；
 * - createVirtualDisplay 每个会话只调一次；
 * - 取帧：隐藏悬浮球 → 等 250ms → acquireLatestImage → JPEG 字节。
 */
class CaptureService : Service() {

    companion object {
        const val CHANNEL_ID = "quizsync_capture"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.example.quizsync_android.capture.START"
        const val ACTION_STOP = "com.example.quizsync_android.capture.STOP"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"

        @Volatile var projectionReady: Boolean = false
            private set

        /** 会话失效（锁屏/系统回收/用户停止/权限撤销）后置位，直到重新授权。 */
        @Volatile var projectionSessionLost: Boolean = false
            private set

        /** 会话失效时通知 Dart 的回调（由 CaptureBridge 注入）。 */
        @Volatile var onSessionLost: (() -> Unit)? = null

        fun start(context: Context, resultCode: Int, data: Intent) {
            val intent = Intent(context, CaptureService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_RESULT_DATA, data)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            // 用 stopService：startService 在后台（API 26+）会抛
            // IllegalStateException，主界面销毁时调用会直接崩。
            context.stopService(Intent(context, CaptureService::class.java))
        }

        /** 桥接句柄（Service 生命周期由系统管理）。 */
        @Volatile var instance: CaptureService? = null
            private set
    }

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.w("CaptureService", "MediaProjection onStop：会话失效")
            projectionReady = false
            projectionSessionLost = true
            releaseCapture()
            onSessionLost?.invoke()
        }
    }

    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                startAsForeground()
                val code = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val data: Intent? =
                    if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(EXTRA_RESULT_DATA)
                    }
                if (data != null) {
                    setupProjection(code, data)
                }
            }
        }
        instance = this
        // 不要 START_STICKY：系统重启服务时 intent 为 null，两个分支都不走，
        // startAsForeground() 不会被调用（服务非前台、投影也不可用）。
        return START_NOT_STICKY
    }

    private fun startAsForeground() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "截屏服务",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "保持截屏会话常驻（授权只弹一次系统框）"
                    setShowBadge(false)
                })
        }
        val launch = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification: Notification =
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("QuizSync 截屏服务运行中")
                .setContentText("点悬浮球即可截屏搜题")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentIntent(launch)
                .setOngoing(true)
                .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private data class ScreenSpec(val width: Int, val height: Int, val dpi: Int)

    private fun realSpec(): ScreenSpec {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(dm)
        // 上限对齐桌面端规格：长边 ≤ 1600，降低内存与流量。
        val longEdge = maxOf(dm.widthPixels, dm.heightPixels)
        return if (longEdge > 1600) {
            val scale = 1600f / longEdge
            ScreenSpec(
                (dm.widthPixels * scale).toInt(),
                (dm.heightPixels * scale).toInt(),
                (dm.densityDpi * scale).toInt(),
            )
        } else {
            ScreenSpec(dm.widthPixels, dm.heightPixels, dm.densityDpi)
        }
    }

    private fun setupProjection(resultCode: Int, data: Intent) {
        releaseCapture()
        val manager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val proj = manager.getMediaProjection(resultCode, data) ?: return
        // Android 14+ 硬性要求：回调必须在 createVirtualDisplay 之前注册，
        // 否则 createVirtualDisplay 直接抛 IllegalStateException。
        proj.registerCallback(projectionCallback, Handler(Looper.getMainLooper()))
        val spec = realSpec()
        val reader = ImageReader.newInstance(spec.width, spec.height, PixelFormat.RGBA_8888, 2)
        val display = proj.createVirtualDisplay(
            "quizsync-capture",
            spec.width, spec.height, spec.dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface, null, null,
        )
        projection = proj
        virtualDisplay = display
        imageReader = reader
        projectionReady = true
        projectionSessionLost = false
    }

    /**
     * 取当前帧并压缩为 JPEG（质量 80）。
     * 调用方负责：截屏前先隐藏悬浮球并等待约 250ms。
     * 返回 null 表示取帧失败（可能为 FLAG_SECURE 黑图/无帧）。
     */
    fun captureJpeg(): ByteArray? {
        val reader = imageReader ?: return null
        var image: Image? = null
        return try {
            // 等一帧新鲜的（VirtualDisplay 持续镜像，丢掉旧帧）。
            Thread.sleep(60)
            image = reader.acquireLatestImage() ?: return null
            val bitmap = image.toBitmap()
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
            out.toByteArray()
        } catch (e: Exception) {
            Log.e("CaptureService", "capture failed", e)
            null
        } finally {
            image?.close()
        }
    }

    private fun releaseCapture() {
        try { virtualDisplay?.release() } catch (_: Exception) {}
        try { imageReader?.close() } catch (_: Exception) {}
        try { projection?.stop() } catch (_: Exception) {}
        virtualDisplay = null
        imageReader = null
        projection = null
        projectionReady = false
    }

    override fun onDestroy() {
        releaseCapture()
        instance = null
        super.onDestroy()
    }
}

private fun Image.toBitmap(): Bitmap {
    val plane = planes[0]
    val buffer = plane.buffer
    val pixelStride = plane.pixelStride
    val rowStride = plane.rowStride
    val rowPadding = rowStride - pixelStride * width
    val bitmap = Bitmap.createBitmap(
        width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888,
    )
    bitmap.copyPixelsFromBuffer(buffer)
    // 裁掉行尾 padding。
    return if (rowPadding == 0) bitmap
    else Bitmap.createBitmap(bitmap, 0, 0, width, height)
}
