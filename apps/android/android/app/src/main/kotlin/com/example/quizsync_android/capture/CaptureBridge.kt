package com.example.quizsync_android.capture

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.example.quizsync_android.ball.FloatingBallManager

/**
 * MethodChannel 桥（SPEC 3.2 / M5 任务 6，保持极薄）：
 * - captureScreen() -> Uint8List（JPEG 字节；含隐藏悬浮球→250ms→取帧→恢复）
 * - setBallVisible(bool)
 * - isCaptureAvailable() -> {main, accessibility, sessionLost, overlayGranted}
 * - requestProjectionAuthorization()（弹一次系统授权框）
 * - requestCameraPermission()（配对扫码用；用户点「开始使用」后才调用）
 * - openAppSettings()
 * - showResultNotification(title, text)（后台结果通知，点开进结果页）
 * 事件：session_lost（Dart 收到后引导重新授权）
 *
 * 用户需求 3：**没有任何把 Activity 拉到前台的路径**——识别全程静默，
 * 界面只靠「当前任务」页与通知栏自然更新。
 */
class CaptureBridge : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "quizsync/capture"
        const val REQUEST_PROJECTION = 4001
        const val REQUEST_NOTIFICATIONS = 4002
        const val REQUEST_CAMERA = 4003

        @Volatile var activity: Activity? = null

        /** 进程级 application context：Activity 被回收后发通知仍需要它。 */
        @Volatile var appContext: android.content.Context? = null

        /**
         * 悬浮球持有 **applicationContext** 且进程内单例：挂在 Activity 上下文上的
         * TYPE_APPLICATION_OVERLAY 视图会随 Activity 的 window token 一起被系统移除
         * （授权录屏弹系统界面时 Activity 可能被销毁重建 → 悬浮球凭空消失）。
         */
        @Volatile var ball: FloatingBallManager? = null
            private set
        @Volatile var instance: CaptureBridge? = null
        @Volatile var pendingAuthCallback: ((Boolean) -> Unit)? = null
        @Volatile var pendingNotifPermission: MethodChannel.Result? = null

        /**
         * 配对页「开始使用」时申请的相机权限（用户需求 7）。
         * 首次进入配对页**不会**走这里——只有用户点了按钮才会申请。
         */
        @Volatile var pendingCameraPermission: MethodChannel.Result? = null
        @Volatile var methodChannel: MethodChannel? = null
        @Volatile var useAccessibilityPath: Boolean = false

        /** 主线程 handler：Toast 等 UI 操作必须在主线程。 */
        private val mainHandler = Handler(Looper.getMainLooper())

        /** 当前正在显示的系统 Toast（M49：新提示顶掉旧的，不排队）。 */
        @Volatile private var currentToast: android.widget.Toast? = null

        /** Dart 期望悬浮球显示（setBallVisible(true) 曾成功或待重试）。 */
        @Volatile var ballWantedVisible: Boolean = false

        fun ensureBall(appContext: android.content.Context): FloatingBallManager {
            return ball ?: FloatingBallManager(
                context = appContext,
                onTap = { invokeBallAction("capture") },
                onLongPress = { invokeBallAction("capture_long") },
            ).also { ball = it }
        }

        /**
         * 悬浮球手势 → Dart（用户需求 3：识别全程静默）。
         *
         * 这里**不再**把主界面抢到前台：采集、上传与结果都在后台完成，
         * 「当前任务」页与通知栏自然更新，用户正在看的那道题不会被盖住。
         */
        private fun invokeBallAction(action: String) {
            methodChannel?.invokeMethod("ball_action", action)
        }

        /** MainActivity 权限请求结果转发（通知权限）。 */
        fun handlePermissionResult(permissions: Array<out String>, granted: Boolean) {
            pendingNotifPermission?.success(granted)
            pendingNotifPermission = null
        }

        /** MainActivity 权限请求结果转发（相机权限，配对扫码用）。 */
        fun handleCameraPermissionResult(granted: Boolean) {
            pendingCameraPermission?.success(granted)
            pendingCameraPermission = null
        }

        /** MainActivity.onActivityResult 转发到这里。 */
        fun handleProjectionResult(resultCode: Int, data: Intent?) {
            val granted = data != null
            if (granted) {
                activity?.let { CaptureService.start(it, resultCode, data!!) }
                // 授权流程可能触发 Activity 重建；球挂在 app 上下文上不会丢，
                // 这里再重申一次显隐，确保授权回来后球一定在。
                if (ballWantedVisible) ball?.show()
            }
            pendingAuthCallback?.invoke(granted)
            pendingAuthCallback = null
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        methodChannel = channel
        instance = this
        appContext = binding.applicationContext
        ensureBall(binding.applicationContext)
        CaptureService.onSessionLost = {
            // 会话失效 → 通知 Dart 引导重新授权（SPEC §8，不静默失败）。
            methodChannel?.invokeMethod("session_lost", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = null
        instance = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "captureScreen" -> captureScreen(result)
            "setBallVisible" -> {
                val visible = call.argument<Boolean>("visible") ?: false
                ballWantedVisible = visible
                val shown = if (visible) {
                    ball?.show() ?: false
                } else {
                    ball?.hide()
                    // M47（用户实测反馈「关闭悬浮球后，屏幕共享未自动终止」）：
                    // 悬浮球是截屏的唯一入口，关掉它就该把常驻的截屏前台服务一起
                    // 停掉 —— 否则 MediaProjection 一直活着、系统状态栏那条
                    // 「屏幕共享/投屏」提示也不会消失。停服务会走 onDestroy →
                    // releaseCapture()（释放 VirtualDisplay/ImageReader 并 stop 投影），
                    // 下次要用时 availability() 会报不可用 → Dart 重新弹一次授权。
                    (activity ?: appContext)?.let { CaptureService.stop(it) }
                    true
                }
                result.success(shown)
            }
            "bringToForeground" -> {
                // 已废弃（用户需求 3）：识别全程静默，任何手势都不再把主界面
                // 拉到前台。保留方法名只为兼容可能残留的旧调用，行为是空操作。
                result.success(null)
            }
            "requestCameraPermission" -> {
                // 配对扫码用（用户需求 7）：Dart 只在用户点了「开始使用」后调用，
                // 保证首次进入配对页不会自动调起相机。
                val act = activity
                val perm = android.Manifest.permission.CAMERA
                if (act == null) {
                    result.success(false)
                } else if (act.checkSelfPermission(perm) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                ) {
                    result.success(true)
                } else {
                    pendingCameraPermission = result
                    act.requestPermissions(arrayOf(perm), REQUEST_CAMERA)
                }
            }
            "openAppSettings" -> {
                // 相机权限被「拒绝且不再询问」后的兜底入口。
                val ctx = activity ?: appContext
                if (ctx != null) {
                    ctx.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = android.net.Uri.parse("package:${ctx.packageName}")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                }
                result.success(null)
            }
            "requestNotificationPermission" -> {
                val act = activity
                val perm = "android.permission.POST_NOTIFICATIONS"
                if (act == null) {
                    result.success(false)
                } else if (Build.VERSION.SDK_INT < 33) {
                    result.success(true)
                } else if (act.checkSelfPermission(perm) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                ) {
                    result.success(true)
                } else {
                    pendingNotifPermission = result
                    act.requestPermissions(arrayOf(perm), REQUEST_NOTIFICATIONS)
                }
            }
            "isCaptureAvailable" -> {
                result.success(
                    mapOf(
                        "main" to CaptureService.projectionReady,
                        "accessibility" to ScreenCaptureAccessibilityService.isAvailable(),
                        "sessionLost" to CaptureService.projectionSessionLost,
                        "overlayGranted" to overlayGranted(),
                    ),
                )
            }
            "getPermissionStatus" -> {
                // 权限引导页要回读**真实**状态：从系统设置回来后刷新，
                // 否则页面永远显示旧的「未授予」。
                result.success(
                    mapOf(
                        "notifications" to notificationGranted(),
                        "overlay" to overlayGranted(),
                        "battery" to batteryUnrestricted(),
                        "accessibility" to ScreenCaptureAccessibilityService.isAvailable(),
                    ),
                )
            }
            "requestProjectionAuthorization" -> requestAuthorization(result)
            "openOverlaySettings" -> {
                activity?.startActivity(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                        data = android.net.Uri.parse("package:${activity?.packageName}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                result.success(null)
            }
            "openNotificationSettings" -> {
                activity?.startActivity(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, activity?.packageName)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                result.success(null)
            }
            "openAccessibilitySettings" -> {
                activity?.startActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                result.success(null)
            }
            "openBatterySettings" -> {
                // 电池优化白名单引导（不自动改，SPEC 3.5）。
                activity?.startActivity(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                result.success(null)
            }
            "showResultNotification" -> {
                val title = call.argument<String>("title") ?: "识别完成"
                val text = call.argument<String>("text") ?: ""
                showNotification(title, text)
                result.success(null)
            }
            "setCaptureMode" -> {
                useAccessibilityPath = call.argument<String>("mode") == "accessibility"
                result.success(null)
            }
            // 多页模式（用户需求 11）：只影响悬浮球外观，业务判断在 Dart。
            "setBallMode" -> {
                val active = call.argument<Boolean>("active") ?: false
                val pages = call.argument<Int>("pages") ?: 0
                ball?.setMode(active, pages)
                result.success(null)
            }
            // 悬浮球外观（识别模块设置二级页）。
            "setBallAppearance" -> {
                val opacity = call.argument<Double>("opacity") ?: 0.75
                val size = call.argument<Double>("size") ?: 48.0
                ball?.setAppearance(opacity, size)
                result.success(null)
            }
            // 悬浮球在其他应用上时 SnackBar 用户看不到，用系统 Toast。
            "showToast" -> {
                val text = call.argument<String>("text") ?: ""
                showToast(text)
                result.success(null)
            }
            "getCaptureState" -> {
                // 设置页需要回读真实状态：原来 _captureMode/_ballEnabled 只是
                // Dart 侧写死的默认值，重启后显示的状态和实际生效的路径不一致。
                result.success(
                    mapOf(
                        "mode" to if (useAccessibilityPath) "accessibility" else "main",
                        "ballVisible" to ballWantedVisible,
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun overlayGranted(): Boolean {
        val ctx = activity ?: appContext ?: return false
        return Settings.canDrawOverlays(ctx)
    }

    /** 系统 Toast（主线程）。悬浮球在其他应用上时用它给反馈。 */
    private fun showToast(text: String) {
        if (text.isEmpty()) return
        val ctx = activity ?: appContext ?: return
        mainHandler.post {
            try {
                // M49：`Toast.makeText().show()` 会**排队**（每条 LENGTH_SHORT ≈ 2 秒），
                // 连按几页悬浮球就攒出一串提示，用户要等十几秒才看完。取消上一条、
                // 只显示最新的那条（多页提示本身带页数，看最后一条信息量更大）。
                currentToast?.cancel()
                val toast = android.widget.Toast
                    .makeText(ctx, text, android.widget.Toast.LENGTH_SHORT)
                currentToast = toast
                toast.show()
            } catch (_: Exception) {
            }
        }
    }

    /** Android 13+ 需要 POST_NOTIFICATIONS；低版本恒为已授予。 */
    private fun notificationGranted(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        val ctx = activity ?: appContext ?: return false
        return ctx.checkSelfPermission("android.permission.POST_NOTIFICATIONS") ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    /** 是否已加入电池优化白名单（允许后台常驻）。 */
    private fun batteryUnrestricted(): Boolean {
        val ctx = activity ?: appContext ?: return false
        val pm = ctx.getSystemService(android.content.Context.POWER_SERVICE) as
            android.os.PowerManager
        return pm.isIgnoringBatteryOptimizations(ctx.packageName)
    }

    /** 截屏：隐藏悬浮球 → 250ms → 取帧（主/备路径）→ 恢复悬浮球。 */
    private fun captureScreen(result: MethodChannel.Result) {
        if (activity == null) {
            result.error("no_activity", "Activity 未就绪", null)
            return
        }
        Thread {
            var bytes: ByteArray? = null
            var errorCode = "no_frame"
            // 切回主线程隐藏并等待：本方法跑在后台线程，直接 removeView 会抛
            // CalledFromWrongThreadException，球会留在画面里被一起截进去。
            ball?.hideAndWait()
            try {
                Thread.sleep(250) // 等悬浮球真正消失（SPEC 3.1）
                if (useAccessibilityPath &&
                    ScreenCaptureAccessibilityService.isAvailable()
                ) {
                    bytes = ScreenCaptureAccessibilityService.requestCapture()
                }
                if (bytes == null) {
                    // 备选路径失败（未授权/不支持/黑图）→ 回落主路径。
                    // 设置页承诺「不可用时自动回落主路径」，原来只有
                    // !useAccessibilityPath 时才走主路径，选过备选路径后
                    // 所有截屏都直接失败并谎报「该应用禁止截屏」。
                    bytes = CaptureService.instance?.captureJpeg()
                }
                if (bytes == null && CaptureService.projectionSessionLost) {
                    errorCode = "session_lost"
                }
            } catch (e: Exception) {
                Log.e("CaptureBridge", "capture error", e)
            } finally {
                ball?.showAndWait()
            }
            if (bytes != null) {
                result.success(bytes)
            } else {
                result.error("capture_failed", errorCode, null)
            }
        }.start()
    }

    private fun requestAuthorization(result: MethodChannel.Result) {
        val act = activity ?: run {
            result.error("no_activity", "Activity 未就绪", null)
            return
        }
        val manager =
            act.getSystemService(Activity.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        pendingAuthCallback = { granted -> result.success(granted) }
        act.startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_PROJECTION)
    }

    private fun showNotification(title: String, text: String) {
        // 后台完成分析时 Activity 可能已经被系统回收；用 application context
        // 兜底，否则「后台结果通知」这一整条路径会静默失效。
        val ctx: android.content.Context = activity ?: appContext ?: return
        val nm = ctx.getSystemService(android.content.Context.NOTIFICATION_SERVICE) as
            android.app.NotificationManager
        if (nm.getNotificationChannel("quizsync_results") == null) {
            nm.createNotificationChannel(
                android.app.NotificationChannel(
                    "quizsync_results", "识别结果",
                    android.app.NotificationManager.IMPORTANCE_HIGH,
                ))
        }
        val launch = PendingIntent.getActivity(
            ctx, 1,
            ctx.packageManager.getLaunchIntentForPackage(ctx.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = android.app.Notification.Builder(ctx, "quizsync_results")
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_send)
            .setContentIntent(launch)
            .setAutoCancel(true)
            .build()
        nm.notify((System.currentTimeMillis() % 100000).toInt(), notification)
    }
}
