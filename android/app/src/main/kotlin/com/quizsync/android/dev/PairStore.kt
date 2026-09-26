package com.quizsync.android.dev

import android.content.Context

/**
 * 配对结果的持久化（电脑地址 + 访问令牌）。
 *
 * 之前 `HostApi.pair()` 只把 token 放在内存里，App 一重启就没了 —— 配对等于白配。
 * 令牌是密钥，按 NATIVE-2.0-PLAN Phase 3 要迁到 EncryptedSharedPreferences；
 * 这一步先用普通 SharedPreferences 打通流程，迁移单独一轮做（已记在 DECISIONS）。
 */
class PairStore(context: Context) {
    private val prefs = context.getSharedPreferences("quizsync", Context.MODE_PRIVATE)

    var host: String?
        get() = prefs.getString(KEY_HOST, null)
        private set(value) = prefs.edit().putString(KEY_HOST, value).apply()

    var token: String?
        get() = prefs.getString(KEY_TOKEN, null)
        private set(value) = prefs.edit().putString(KEY_TOKEN, value).apply()

    val isPaired: Boolean get() = !host.isNullOrEmpty() && !token.isNullOrEmpty()

    fun save(host: String, token: String) {
        this.host = host
        this.token = token
    }

    /** 手机端主动「解除配对」：只清本地凭据，不动电脑上的记录。 */
    fun clear() {
        prefs.edit().remove(KEY_HOST).remove(KEY_TOKEN).apply()
    }

    private companion object {
        const val KEY_HOST = "paired_host"
        const val KEY_TOKEN = "paired_token"
    }
}
