package com.quizsync.android.dev

import java.net.URI
import java.net.URLDecoder

/** 深链 `quizsync://pair?host=…&port=…&code=…` 解析出来的配对请求。 */
data class PairRequest(val host: String, val code: String)

/**
 * 解析电脑端二维码/深链里的配对信息。
 *
 * 为什么需要它（第六轮实测教训）：我原想用 `adb shell input text` 把地址和码打进手机，
 * 结果**输入法把 `.` 和 `:` 转成了全角 `。`/`：`**（`adb input text` 走的是手机当前 IME，
 * 中文输入法在中文标点模式下就会这么转）—— 打进 `192.168.1.23:8765`、
 * 屏上却是 `192。168。101。23：8765`。深链既绕开输入法，又是**产品本来就需要的功能**：
 * 服务端 `/api/v1/pair/code` 返回的 `pair_uri` 就是它，二维码里放的也是它。
 *
 * 用 `java.net.URI` 而不是 `android.net.Uri`：纯 JVM 实现 → 能跑普通单测，不需要真机。
 */
object PairUri {
    const val SCHEME = "quizsync"
    const val AUTHORITY = "pair"

    fun parse(raw: String?): PairRequest? {
        if (raw.isNullOrBlank()) {
            return null
        }

        val uri = runCatching { URI(raw.trim()) }.getOrNull() ?: return null
        if (!SCHEME.equals(uri.scheme, ignoreCase = true)) {
            return null
        }
        if (!AUTHORITY.equals(uri.host ?: uri.authority?.substringBefore('?'), ignoreCase = true)) {
            return null
        }

        val params = (uri.rawQuery ?: "")
            .split('&')
            .mapNotNull { part ->
                val index = part.indexOf('=')
                if (index <= 0) null
                else URLDecoder.decode(part.substring(0, index), "UTF-8") to
                    URLDecoder.decode(part.substring(index + 1), "UTF-8")
            }
            .toMap()

        val host = params["host"]?.takeIf { it.isNotBlank() } ?: return null
        val code = params["code"]?.filter { it.isDigit() }?.takeIf { it.length == 6 } ?: return null
        val port = params["port"]?.toIntOrNull() ?: HostAddress.DEFAULT_PORT
        return PairRequest(host = "$host:$port", code = code)
    }
}
