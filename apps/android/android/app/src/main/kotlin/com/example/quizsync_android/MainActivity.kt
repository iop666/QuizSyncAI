package com.example.quizsync_android

import android.content.Intent
import com.example.quizsync_android.capture.CaptureBridge
import com.example.quizsync_android.capture.CaptureService
import com.example.quizsync_android.systemui.SystemUiBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CaptureBridge.activity = this
        flutterEngine.plugins.add(CaptureBridge())
        // 悬浮球由 CaptureBridge 以 applicationContext 单例持有：
        // 挂在 Activity 上会随授权录屏时的 Activity 重建一起被系统移除。
        // 系统栏外观（M13）：引擎在 API 35+ 不设状态栏底色，必须自己来。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SystemUiBridge.CHANNEL,
        ).setMethodCallHandler { call, result ->
            SystemUiBridge.handle(call, result, this)
        }
    }

    /**
     * 窗口获焦 / 回到前台时系统会重置 light-status-bar 这类窗口标志
     * （引擎的 `enableEdgeToEdge()` 就显式把 visibility 清成 0），
     * 而 Flutter 侧认为「已经下发过」不会重发 —— 这里按最后一次样式补一次。
     */
    override fun onResume() {
        super.onResume()
        SystemUiBridge.reapply(this)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) SystemUiBridge.reapply(this)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CaptureBridge.REQUEST_PROJECTION) {
            CaptureBridge.handleProjectionResult(resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (requestCode == CaptureBridge.REQUEST_NOTIFICATIONS) {
            CaptureBridge.handlePermissionResult(permissions, granted)
        } else if (requestCode == CaptureBridge.REQUEST_CAMERA) {
            // 配对页扫码（用户需求 7）：只有用户点了「开始使用」才会走到这里。
            CaptureBridge.handleCameraPermissionResult(granted)
        }
    }

    override fun onDestroy() {
        if (isFinishing) {
            CaptureService.stop(this)
            CaptureBridge.activity = null
        }
        super.onDestroy()
    }
}
