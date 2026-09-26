package com.example.quizsync_android.ball

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager

/**
 * 悬浮球（SPEC 3.1 + 用户需求 8/11）：原生 View + WindowManager TYPE_APPLICATION_OVERLAY。
 * - **默认停靠右边缘**、垂直位置约屏幕高度 40%（用户需求 8）；
 * - 可拖动，松手吸附最近的左/右边缘（垂直位置保留），并记住该侧为停靠方向；
 * - 8dp 阈值区分点击与拖动（拖动不触发截屏）；
 * - **单击** → onTap()（Dart 决定：单图识别，或结束多页模式）；
 * - **长按 500ms** → onLongPress()（Dart 决定：追加一页，进入/继续多页模式）；
 *   —— 长按菜单已废弃（用户需求 11），历史/设置移到 App 的底部标签栏；
 * - setMode() 让球在多页收集期间换色并显示已收集页数；
 * - setAppearance() 支持透明度与大小（识别模块设置二级页）；
 * - 截屏前由 CaptureBridge 隐藏本球、等 250ms、截完恢复。
 *
 * 业务判断（当前是不是多页模式、该做什么）全部在 Dart 侧，这里只上报手势。
 * 用户需求 3：本类与调用方都**不再把主界面拉到前台**。
 */
class FloatingBallManager(
    private val context: Context,
    private val onTap: () -> Unit,
    private val onLongPress: () -> Unit,
) {
    companion object {
        private const val DEFAULT_SIZE_DP = 48f
        private const val MIN_SIZE_DP = 32f
        private const val MAX_SIZE_DP = 72f
        private const val CLICK_SLOP_DP = 8f
        private const val LONG_PRESS_MS = 500L
        private const val EDGE_MARGIN_DP = 0f

        /** 默认停靠方向：右边缘（用户需求 8）。 */
        private const val DEFAULT_DOCK_RIGHT = true

        /** 默认垂直位置：屏幕高度的 40%（用户需求 8）。 */
        private const val DEFAULT_Y_FRACTION = 0.4f
    }

    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var ballView: View? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    var isShowing: Boolean = false
        private set

    private val density = context.resources.displayMetrics.density

    /** 外观与模式状态（由 Dart 通过 setAppearance / setMode 推送）。 */
    private var sizeDp = DEFAULT_SIZE_DP
    private var opacity = 190f / 255f
    private var multiPageActive = false
    private var multiPageCount = 0

    /** 当前停靠方向（true = 右边缘）；默认右侧（用户需求 8）。 */
    private var dockRight = DEFAULT_DOCK_RIGHT

    /** 用户拖动后的垂直位置；-1 表示还没拖过，用默认的 40% 高度。 */
    private var lastY = -1

    private val ballSizePx: Int get() = (sizeDp * density).toInt()
    private val clickSlopPx = CLICK_SLOP_DP * density
    private val screenWidth: Int get() = context.resources.displayMetrics.widthPixels
    private val screenHeight: Int get() = context.resources.displayMetrics.heightPixels

    /** 贴边时的水平坐标（按当前停靠方向）。 */
    private fun dockX(): Int {
        val margin = (EDGE_MARGIN_DP * density).toInt()
        return if (dockRight) {
            (screenWidth - ballSizePx - margin).coerceAtLeast(0)
        } else {
            margin
        }
    }

    /** 默认垂直位置：屏幕高度约 40%（用户需求 8）；拖过之后沿用用户的位置。 */
    private fun dockY(): Int {
        val fallback =
            (screenHeight * DEFAULT_Y_FRACTION).toInt() - ballSizePx / 2
        val y = if (lastY >= 0) lastY else fallback
        return y.coerceIn(0, (screenHeight - ballSizePx).coerceAtLeast(0))
    }

    @SuppressLint("ClickableViewAccessibility")
    fun show(): Boolean {
        if (ballView != null) return true
        // 悬浮窗权限未授予时无法显示：返回 false 让调用方引导授权，而不是静默失败。
        if (!canDrawOverlays()) return false
        val view = object : View(context) {
            private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(120, 255, 255, 255)
                style = Paint.Style.STROKE
                strokeWidth = 2f * density
            }
            private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                style = Paint.Style.STROKE
                strokeWidth = 2.5f * density
            }
            private val badgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(255, 245, 158, 11) // 多页进行中：琥珀色
            }
            private val badgeText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textAlign = Paint.Align.CENTER
                textSize = 10f * density
                isFakeBoldText = true
            }

            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)
                val s = size.toFloat()
                // 多页收集期间换成琥珀色，用户一眼能看出「还在加页」。
                paint.color = if (multiPageActive) {
                    Color.argb((opacity * 255).toInt(), 245, 158, 11)
                } else {
                    Color.argb((opacity * 255).toInt(), 22, 163, 74) // 半透明品牌绿
                }
                val r = s / 2f - 4f * density
                canvas.drawCircle(s / 2f, s / 2f, r, paint)
                canvas.drawCircle(s / 2f, s / 2f, r, stroke)
                // 简单的「搜」意象：放大镜圈
                canvas.drawCircle(s / 2f - 3 * density, s / 2f - 3 * density, 7 * density, iconPaint)
                canvas.drawLine(
                    s / 2f + 2 * density, s / 2f + 2 * density,
                    s / 2f + 7 * density, s / 2f + 7 * density, iconPaint,
                )
                if (multiPageActive) {
                    val cx = s - 7 * density
                    val cy = 7 * density
                    canvas.drawCircle(cx, cy, 7.5f * density, badgePaint)
                    val label = if (multiPageCount > 0) multiPageCount.toString() else "•"
                    val fm = badgeText.fontMetrics
                    val baseline = cy - (fm.ascent + fm.descent) / 2f
                    canvas.drawText(label, cx, baseline, badgeText)
                }
            }

            private val size get() = sizeDp * density
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.START or Gravity.TOP
            width = ballSizePx
            height = ballSizePx
            // 默认贴在右边缘、垂直约 40% 高度（用户需求 8）。
            x = dockX()
            y = dockY()
        }

        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        var longFired = false
        // 长按只上报一次手势，不再弹菜单（用户需求 11）。
        val longPressRunnable = Runnable {
            if (!moved) {
                longFired = true
                onLongPress()
            }
        }

        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    moved = false
                    longFired = false
                    mainHandler.postDelayed(longPressRunnable, LONG_PRESS_MS)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (moved || kotlin.math.abs(dx) > clickSlopPx ||
                        kotlin.math.abs(dy) > clickSlopPx
                    ) {
                        if (!moved) mainHandler.removeCallbacks(longPressRunnable)
                        moved = true
                        params.x = (startX + dx).toInt()
                        params.y = (startY + dy).toInt()
                        try {
                            wm.updateViewLayout(view, params)
                        } catch (_: Exception) {
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    mainHandler.removeCallbacks(longPressRunnable)
                    val up = event.actionMasked == MotionEvent.ACTION_UP
                    snapToEdge(params)
                    if (up && !moved && !longFired) {
                        // 单击：不做任何原生业务，交给 Dart 决定语义。
                        onTap()
                    }
                    true
                }
                else -> false
            }
        }

        wm.addView(view, params)
        ballView = view
        isShowing = true
        return true
    }

    /**
     * 松手后吸附最近的左/右边缘，垂直位置保留（SPEC 3.1），
     * 并把这一侧记为停靠方向（用户需求 8：默认停靠右侧）。
     */
    private fun snapToEdge(params: WindowManager.LayoutParams) {
        val view = ballView ?: return
        val dm = context.resources.displayMetrics
        val center = params.x + ballSizePx / 2
        dockRight = center >= dm.widthPixels / 2
        params.x = dockX()
        params.y = params.y.coerceIn(0, (dm.heightPixels - ballSizePx).coerceAtLeast(0))
        lastY = params.y
        try {
            wm.updateViewLayout(view, params)
        } catch (_: Exception) {
        }
    }

    /**
     * 多页模式状态（用户需求 11）：只影响外观，业务判断在 Dart。
     * [pages] = 已收集页数（0 表示刚进入多页模式还没截到页）。
     */
    fun setMode(active: Boolean, pages: Int) {
        multiPageActive = active
        multiPageCount = if (pages < 0) 0 else pages
        ballView?.invalidate()
    }

    /** 外观（识别模块设置二级页）：opacity 0.3–1.0，sizeDp 32–72。 */
    fun setAppearance(opacityValue: Double, sizeDpValue: Double) {
        opacity = (if (opacityValue.isNaN()) 0.75 else opacityValue)
            .coerceIn(0.3, 1.0).toFloat()
        sizeDp = (if (sizeDpValue.isNaN()) DEFAULT_SIZE_DP.toDouble() else sizeDpValue)
            .coerceIn(MIN_SIZE_DP.toDouble(), MAX_SIZE_DP.toDouble()).toFloat()
        val view = ballView ?: return
        try {
            val params = view.layoutParams as WindowManager.LayoutParams
            lastY = params.y
            params.width = ballSizePx
            params.height = ballSizePx
            // 球变大/变小后要重新贴边，否则会有一半留在屏幕外。
            params.x = dockX()
            params.y = dockY()
            wm.updateViewLayout(view, params)
        } catch (_: Exception) {
        }
        view.invalidate()
    }

    fun hide() {
        ballView?.let {
            try { wm.removeView(it) } catch (_: Exception) {}
        }
        ballView = null
        isShowing = false
    }

    /** 截屏前隐藏 / 截后恢复。 */
    fun setVisible(visible: Boolean) {
        if (visible) show() else hide()
    }

    /**
     * 截屏线程调用：切回主线程隐藏并等待完成。
     * View 只能在创建它的线程（这里是主线程，`show()` 由 MethodChannel 回调触发）
     * 上 removeView，否则 WindowManagerGlobal 会抛 CalledFromWrongThreadException
     * ——异常被 `hide()` 里的 catch 吞掉，球没被移除，于是**球出现在截图里**。
     */
    fun hideAndWait(timeoutMs: Long = 400) = runOnMainAndWait(timeoutMs) { hide() }

    /** 截屏线程调用：切回主线程恢复悬浮球。 */
    fun showAndWait(timeoutMs: Long = 400) = runOnMainAndWait(timeoutMs) { show() }

    private fun runOnMainAndWait(timeoutMs: Long, block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
            return
        }
        val latch = java.util.concurrent.CountDownLatch(1)
        mainHandler.post {
            try {
                block()
            } finally {
                latch.countDown()
            }
        }
        try {
            latch.await(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
        }
    }

    private fun canDrawOverlays(): Boolean =
        android.provider.Settings.canDrawOverlays(context)
}
