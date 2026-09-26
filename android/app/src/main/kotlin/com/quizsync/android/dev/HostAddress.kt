package com.quizsync.android.dev

/**
 * 把用户在「电脑地址」里敲的字符串变成可用的 base URL。
 *
 * 为什么单独一个文件：用户在手机上敲的是 `192.168.1.10` 这种**裸地址**，
 * 直接丢给 OkHttp 会抛 `Expected URL scheme 'http' or 'https' but no scheme was found`
 * （第六轮用户亲手试配对时正是这个报错）。这类「人输的字符串 → 规范 URL」的规则
 * 必须能被单测直接钉住，不能藏在 Composable 里。
 *
 * 规则（按协议：默认端口 8765）：
 *  * 空 / 只有空白 → null（调用方禁用按钮）
 *  * 已经有 `http://` / `https://` → 原样（去掉尾部斜杠）
 *  * 没写协议 → 补 `http://`（局域网直连，明文是既定事实，见 spec）
 *  * 没写端口 → 补默认 8765
 */
object HostAddress {
    const val DEFAULT_PORT = 8765

    fun normalize(raw: String): String? {
        val trimmed = raw.trim().trimEnd('/')
        if (trimmed.isEmpty()) {
            return null
        }

        val withScheme = when {
            trimmed.startsWith("http://", ignoreCase = true) -> trimmed
            trimmed.startsWith("https://", ignoreCase = true) -> trimmed
            else -> "http://$trimmed"
        }

        val withoutScheme = withScheme.substringAfter("://")
        if (withoutScheme.isEmpty()) {
            return null
        }

        // 只在「主机后没有冒号」时补端口；IPv6 字面量（带方括号）不在本版范围内，
        // 所以这里不会把 `[::1]:8765` 判错 —— 它有冒号，原样保留。
        val hasPort = withoutScheme.contains(':')
        val hostAndPort = if (hasPort) withoutScheme else "$withoutScheme:$DEFAULT_PORT"

        return withScheme.substringBefore("://") + "://" + hostAndPort
    }
}
