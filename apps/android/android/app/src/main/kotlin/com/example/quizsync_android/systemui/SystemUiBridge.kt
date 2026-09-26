package com.example.quizsync_android.systemui

import android.app.Activity
import android.os.Build
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 系统栏（状态栏 / 导航栏）外观桥（M13，保持极薄：只做「显示窗口」这一层）。
 *
 * ## 为什么不能只靠 Flutter 的 `SystemChrome.setSystemUIOverlayStyle`
 *
 * 反编译本项目实际使用的引擎产物
 * （`bin/cache/artifacts/engine/android-arm64-release/flutter.jar` →
 * `io.flutter.plugin.platform.PlatformPlugin`）可以看到：
 *
 * ```
 * aload statusBarColor; ifnull skip
 * getstatic Build.VERSION.SDK_INT; bipush 35; if_icmpge skip   // ← SDK >= 35 直接跳过
 * window.setStatusBarColor(color)
 * ```
 *
 * 也就是说 **Android 15（API 35）及以上，引擎根本不设状态栏底色**，只设图标明暗
 * （`WindowInsetsControllerCompat.setAppearanceLightStatusBars`）。M10/M11 两轮
 * 「显式配色」因此在 15+ 机器上注定无效：用户看到的是**启动窗口主题**里那个
 * `android:statusBarColor`（平台默认黑色），切浅色/深色都不动 —— 这正是
 * 「状态栏不跟着主题变化」的根因。
 *
 * ## 这里的对策
 *
 * 1. 图标明暗：用官方推荐的 `WindowInsetsControllerCompat`，未废弃，API 26–36 通用；
 * 2. 底色：API < 35 平台仍然认，直接设；API >= 35 平台忽略颜色、状态栏是透明的，
 *    底色改由 Flutter 自己在顶部安全区画一条同色条带（见 `ui/system_ui.dart`）；
 * 3. **缓存最后一次样式并在 onResume / 失焦回焦时重贴**：Android 会在窗口获焦、
 *    系统弹窗、Activity 重建时重置这些窗口标志，而 Flutter 侧 `_latestStyle`
 *    缓存以为「已经下发过了」不会重发。宿主主动重贴是最可靠的一层。
 */
object SystemUiBridge {

    const val CHANNEL = "quizsync/system_ui"

    /** 上一次下发的样式；Activity 重建 / 窗口获焦后由宿主重新贴回。 */
    private data class Style(
        val statusBarColor: Int,
        val navigationBarColor: Int,
        val dark: Boolean,
    )

    @Volatile
    private var last: Style? = null

    fun handle(call: MethodCall, result: MethodChannel.Result, activity: Activity?) {
        when (call.method) {
            "setStyle" -> {
                val style = Style(
                    statusBarColor = call.argument<Number>("statusBarColor")?.toInt() ?: 0,
                    navigationBarColor = call.argument<Number>("navigationBarColor")?.toInt() ?: 0,
                    dark = call.argument<Boolean>("dark") ?: false,
                )
                last = style
                apply(activity, style)
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    /** 宿主在 `onResume` / `onWindowFocusChanged` 调：系统会重置窗口标志，这里补一次。 */
    fun reapply(activity: Activity?) {
        last?.let { apply(activity, it) }
    }

    @Suppress("DEPRECATION")
    private fun apply(activity: Activity?, style: Style) {
        val window = activity?.window ?: return
        // 内容铺到系统栏底下。Android 15 起平台强制 edge-to-edge，这里是显式声明，
        // 保证 Flutter 一定能拿到顶部 inset（顶部条带就画在这块 inset 上）。
        WindowCompat.setDecorFitsSystemWindows(window, false)
        // 真正决定「时间 / 电量 / 通知图标是深是浅」的开关。
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.isAppearanceLightStatusBars = !style.dark
        controller.isAppearanceLightNavigationBars = !style.dark
        if (Build.VERSION.SDK_INT < 35) {
            // 35+ 平台忽略这两个 setter（引擎也因此跳过），由 Flutter 自绘条带负责。
            window.statusBarColor = style.statusBarColor
            window.navigationBarColor = style.navigationBarColor
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // 明确禁止系统再叠一层对比度遮罩，否则浅色主题下状态栏会被压成一块深色。
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }
}
