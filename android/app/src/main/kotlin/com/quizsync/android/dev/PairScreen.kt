package com.quizsync.android.dev

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.quizsync.android.core.net.HostApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 配对页 —— Android 侧的第一个真页面。
 *
 * 两条入口走的是同一条真实链路（`HostApi(baseUrl).pair(...)` → `POST /api/v1/pair`）：
 * ① 手输：地址 + 6 位码；② 深链 `quizsync://pair?host=…&port=…&code=…`（预填 + 自动提交）。
 *
 * 200 与 409 都算成功（409 = 重复配对，服务端照样发新 token，与 v1 语义一致），
 * 成功后把地址与 token 落盘（[PairStore]），App 重启不会白配。失败如实显示错误码与文案。
 */
@Composable
fun PairScreen(
    deviceId: String,
    store: PairStore,
    prefill: PairRequest? = null,
    onLinkConsumed: () -> Unit = {},
    onPaired: () -> Unit,
    onBack: () -> Unit,
) {
    var host by remember { mutableStateOf(prefill?.host ?: "") }
    var code by remember { mutableStateOf(prefill?.code ?: "") }
    var busy by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf("把电脑上的 6 位配对码填进来") }
    val scope = rememberCoroutineScope()
    val baseUrl = HostAddress.normalize(host)

    fun submit() {
        val url = baseUrl ?: return
        busy = true
        result = "正在配对…"
        scope.launch {
            var ok = false
            result = withContext(Dispatchers.IO) {
                runCatching {
                    val response = HostApi(url).pair(
                        code = code,
                        deviceId = deviceId,
                        deviceName = "安卓设备",
                    )
                    val token = response.string("token")
                    if ((response.status == 200 || response.status == 409) && token != null) {
                        store.save(url, token)
                        ok = true
                        "配对成功：已连上 $url"
                    } else {
                        "配对失败：" +
                            (response.string("code") ?: "http_${response.status}") +
                            " · " + (response.string("message") ?: "服务端未给说明")
                    }
                }.getOrElse { error ->
                    "连不上电脑（$url）：${error.message ?: error::class.simpleName}"
                }
            }
            busy = false
            if (ok) onPaired()
        }
    }

    // 深链：预填好了就自动提交一次，用户只需看结果（扫码之后不该再让他按一下）。
    LaunchedEffect(prefill) {
        if (prefill != null && HostAddress.normalize(prefill.host) != null) {
            onLinkConsumed()
            submit()
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().padding(QsTokens.spaceXl),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Card(
                shape = RoundedCornerShape(QsTokens.radiusCard),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    modifier = Modifier.padding(QsTokens.spaceXl),
                    verticalArrangement = Arrangement.spacedBy(QsTokens.spaceLg),
                ) {
                    Text(
                        "配对电脑",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        "电脑上点「显示配对码」，把地址和 6 位码填到这里",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )

                    OutlinedTextField(
                        value = host,
                        onValueChange = { host = it.trim() },
                        label = { Text("电脑地址") },
                        placeholder = { Text("例如 192.168.1.10:8765") },
                        singleLine = true,
                        enabled = !busy,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                        modifier = Modifier.fillMaxWidth(),
                    )

                    OutlinedTextField(
                        value = code,
                        // 只留数字、最多 6 位 —— 与协议里的配对码长度一致。
                        onValueChange = { input -> code = input.filter { it.isDigit() }.take(6) },
                        label = { Text("6 位配对码") },
                        singleLine = true,
                        enabled = !busy,
                        textStyle = MaterialTheme.typography.titleLarge.copy(
                            fontFamily = FontFamily.Monospace,
                        ),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        modifier = Modifier.fillMaxWidth(),
                    )

                    Button(
                        onClick = { submit() },
                        enabled = !busy && code.length == 6 && baseUrl != null,
                        shape = RoundedCornerShape(QsTokens.radiusControl),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (busy) "正在配对…" else "开始配对")
                    }

                    TextButton(onClick = onBack, enabled = !busy) {
                        Text("返回", style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
        }

        Surface(color = MaterialTheme.colorScheme.background) {
            Text(
                text = result,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}
