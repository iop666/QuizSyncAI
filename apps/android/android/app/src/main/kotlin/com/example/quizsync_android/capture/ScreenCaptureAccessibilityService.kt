package com.example.quizsync_android.capture

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.view.accessibility.AccessibilityEvent
import io.flutter.Log
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 截屏备选路径（SPEC 3.2）：AccessibilityService.takeScreenshot()，API 30+。
 * 在设置里可切换；低于 API 30 或未授予无障碍权限时不可用，回落主路径。
 */
class ScreenCaptureAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile private var svcInstance: ScreenCaptureAccessibilityService? = null

        @Volatile var connected: Boolean = false
            private set

        fun isAvailable(): Boolean =
            connected && Build.VERSION.SDK_INT >= 30 && svcInstance != null

        /**
         * 请求截屏（同步等待，超时 5s）。
         * 服务未连接 / API 不足 / 截屏失败（含 FLAG_SECURE）返回 null。
         */
        fun requestCapture(timeoutMs: Long = 5000): ByteArray? {
            val svc = svcInstance ?: return null
            if (Build.VERSION.SDK_INT < 30) return null
            var out: ByteArray? = null
            val latch = CountDownLatch(1)
            svc.takeScreenshotJpeg { bytes ->
                out = bytes
                latch.countDown()
            }
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            return out
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        // 注意：这里**不能**整体替换 serviceInfo。替换成新的
        // AccessibilityServiceInfo() 会丢掉清单里声明的 canTakeScreenshot
        // 能力，之后 takeScreenshot() 会以「Services don't have the
        // capability of taking the screenshot」直接失败，备选路径永远不可用。
        // 清单已经声明了 feedbackGeneric 与空 eventTypes，无需再设置。
        svcInstance = this
        connected = true
        Log.i("A11yCapture", "accessibility capture service connected")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        connected = false
        svcInstance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        connected = false
        svcInstance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    /** 取整屏 JPEG；失败返回 null。 */
    fun takeScreenshotJpeg(onDone: (ByteArray?) -> Unit) {
        if (Build.VERSION.SDK_INT < 30) {
            onDone(null)
            return
        }
        takeScreenshot(
            android.view.Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    try {
                        val hardwareBuffer = screenshot.hardwareBuffer
                        val hardwareBitmap =
                            Bitmap.wrapHardwareBuffer(hardwareBuffer, null)
                        if (hardwareBitmap == null) {
                            hardwareBuffer.close()
                            onDone(null)
                            return
                        }
                        val sw = hardwareBitmap.copy(Bitmap.Config.ARGB_8888, false)
                        hardwareBuffer.close()
                        val out = ByteArrayOutputStream()
                        sw.compress(Bitmap.CompressFormat.JPEG, 80, out)
                        onDone(out.toByteArray())
                    } catch (e: Exception) {
                        Log.e("A11yCapture", "screenshot failed", e)
                        onDone(null)
                    }
                }

                override fun onFailure(errorCode: Int) {
                    Log.w("A11yCapture", "screenshot onFailure: $errorCode")
                    onDone(null)
                }
            },
        )
    }
}
