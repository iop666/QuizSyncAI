package com.quizsync.android.dev

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.quizsync.android.core.db.QuizSyncDatabase
import java.io.File
import java.util.UUID

/**
 * 原生 2.0 的 Android 首屏。
 *
 * 第五轮纠正（用户当场质问「我应用 1.1.0 原来是浅绿的，你用紫色干什么」）：
 * 上一版所有样式取值都是我**凭空发明**的（品牌紫 #63519F、按钮胶囊、标签圆角矩形、
 * 描边 #78747D），而且方向正好修反 —— 老应用是**按钮圆角 10 / 标签 999 胶囊**。
 *
 * 现在一律走 `QsTokens`：值由 `tools/gen_design_tokens.py` 从 `design/tokens.json` 生成，
 * 而 `design/tokens.json` 的值又被 `packages/quizsync_ui/test/design_token_parity_test.dart`
 * 用真 Flutter 钉在老应用的视觉契约上（凭空写一个值就会红）。
 *
 * 结构也照老应用：页面底色用 canvas（#F3F5F4），内容放进白卡片 —— 不再整屏铺白。
 */
class MainActivity : ComponentActivity() {
    /// 深链进来的配对请求（扫码 / 点链接）。onNewIntent 时也要能更新，所以放在字段上。
    private var pendingPair by mutableStateOf<PairRequest?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        pendingPair = PairUri.parse(intent?.dataString)
        val schema = readSchemaAsset()
        val deviceId = deviceId()
        val store = PairStore(this)
        setContent {
            // 明暗跟随系统；两套配色都来自同一份 token（与 Windows 的 ThemeDictionaries 同源）。
            MaterialTheme(
                colorScheme = if (isSystemInDarkTheme()) QsTokens.darkScheme else QsTokens.lightScheme,
            ) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    // 深链进来就直接落到配对页并自动提交，用户不用手输地址与码。
                    var showPair by remember { mutableStateOf(false) }
                    var pairedHost by remember { mutableStateOf(store.host) }
                    LaunchedEffect(pendingPair) {
                        if (pendingPair != null) showPair = true
                    }
                    if (showPair) {
                        PairScreen(
                            deviceId = deviceId,
                            store = store,
                            prefill = pendingPair,
                            onLinkConsumed = { pendingPair = null },
                            onPaired = {
                                pairedHost = store.host
                                pendingPair = null
                                showPair = false
                            },
                            onBack = {
                                pendingPair = null
                                showPair = false
                            },
                        )
                    } else {
                        HomeScreen(
                            schemaSql = schema,
                            pairedHost = pairedHost,
                            onShowPairCode = { showPair = true },
                            onUnpair = {
                                store.clear()
                                pairedHost = null
                            },
                        )
                    }
                }
            }
        }
    }

    /// 应用已经开着时再扫一次码 / 点一次链接，也要能接住。
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        PairUri.parse(intent.dataString)?.let { pendingPair = it }
    }

    /// 设备标识：配对协议要求一个稳定的 `device_id`。它不是密钥，放普通 SharedPreferences 即可
    /// （配对 token 才是密钥，将来走 EncryptedSharedPreferences —— 见 NATIVE-2.0-PLAN Phase 3）。
    private fun deviceId(): String {
        val prefs = getSharedPreferences("quizsync", Context.MODE_PRIVATE)
        return prefs.getString("device_id", null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString("device_id", it).apply()
        }
    }

    /// 协议 schema 随 APK 走（assets）。真机第一次运行时抓到的教训：
    /// 内核原来靠「从工作目录往上找协议仓」拿 schema —— Android 上根本没有这个概念。
    private fun readSchemaAsset(): String =
        assets.open("quizsync/schema-v1.sql").bufferedReader().use { it.readText() }
}

@Composable
private fun HomeScreen(
    schemaSql: String,
    pairedHost: String?,
    onShowPairCode: () -> Unit,
    onUnpair: () -> Unit,
) {
    val paired = !pairedHost.isNullOrEmpty()
    var status by remember { mutableStateOf("") }
    val diagnostics = remember(schemaSql) {
        runCatching { dataLayerReport(schemaSql) }.getOrElse { "数据层未就绪：${it.message}" }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().padding(QsTokens.spaceXl),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // 白卡片托住内容（老应用的做法：canvas 底 + surface 卡片 + 圆角 16 + 装饰描边）。
            Card(
                shape = RoundedCornerShape(QsTokens.radiusCard),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
                border = BorderStroke(
                    width = 1.dp,
                    color = MaterialTheme.colorScheme.outlineVariant,
                ),
            ) {
                Column(
                    modifier = Modifier.padding(QsTokens.spaceXl),
                    verticalArrangement = Arrangement.spacedBy(QsTokens.spaceLg),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        "AI 双端搜题",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        "手机截屏搜题，答案同时出现在手机和电脑上",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    // 已配对时把能力标签换成配对状态，并把主按钮换成「重新配对」——
                    // 否则用户配完了界面上看不出任何变化（第一版就是这个毛病）。
                    if (paired) {
                        Row(horizontalArrangement = Arrangement.spacedBy(QsTokens.spaceSm)) {
                            CapabilityTag("已配对")
                            CapabilityTag("可开始搜题")
                        }
                        Text(
                            "已连接：$pairedHost",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(QsTokens.spaceSm)) {
                            CapabilityTag("局域网直连")
                            CapabilityTag("双端同步")
                            CapabilityTag("无需账号")
                        }
                    }

                    GuideSteps()

                    Button(
                        onClick = onShowPairCode,
                        shape = RoundedCornerShape(QsTokens.radiusControl),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (paired) "重新配对电脑" else "配对电脑")
                    }

                    if (paired) {
                        TextButton(onClick = onUnpair) {
                            Text("解除配对", style = MaterialTheme.typography.labelLarge)
                        }
                    } else {
                        TextButton(onClick = { status = "诊断：$diagnostics" }) {
                            Text("查看诊断信息", style = MaterialTheme.typography.labelLarge)
                        }
                    }
                }
            }
        }

        // 底部状态条：通栏条带 + token 里的前景/底色（与 Windows 的 QsStatusBarBorderStyle 同源）。
        Surface(color = MaterialTheme.colorScheme.background) {
            Text(
                text = status.ifEmpty { "已就绪，可开始搜题" },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}

/**
 * 能力标签：**全胶囊**（`AppRadius.chip = 999`）+ `outline` 描边。
 *
 * 第五轮纠正：上一版我把它改成 8px 圆角矩形，理由是「和 Windows 拉齐」—— 而老应用本来就是
 * 999 胶囊，Windows 那一侧才是对的。**功能边界用 outline，不用 cardStroke**（后者对比度天生
 * 很低，是卡片装饰用的）。
 */
@Composable
private fun CapabilityTag(text: String) {
    AssistChip(
        onClick = {},
        label = { Text(text, style = MaterialTheme.typography.labelMedium) },
        shape = RoundedCornerShape(QsTokens.radiusChip),
    )
}

/** 三步引导：与 Windows 首屏同一份文案、同一套形制（编号圆 + 正文）。 */
@Composable
private fun GuideSteps() {
    val steps = listOf(
        "电脑：点「显示配对码」",
        "手机：输入电脑上的 6 位配对码",
        "任一端截屏，答案同时出现在两端",
    )
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(QsTokens.spaceSm),
    ) {
        Text(
            "三步开始",
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        steps.forEachIndexed { index, text ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(22.dp)
                        .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "${index + 1}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(text, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

/** 用一个临时库跑一遍协议 schema，回报表数（诊断动作，不再常驻状态条）。 */
private fun dataLayerReport(schemaSql: String): String {
    val dbFile = File.createTempFile("quizsync-selftest", ".db")
    QuizSyncDatabase.open(dbFile.absolutePath, schemaSql).use { db ->
        val tables = mutableListOf<String>()
        val statement = db.connection.prepare("SELECT name FROM sqlite_master WHERE type='table'")
        try {
            while (statement.step()) {
                tables += statement.getText(0)
            }
        } finally {
            statement.close()
        }
        return "数据层就绪（${tables.size} 张表）"
    }
}
