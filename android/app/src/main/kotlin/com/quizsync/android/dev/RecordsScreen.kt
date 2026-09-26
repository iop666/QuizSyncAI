package com.quizsync.android.dev

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 记录页：从主机**拉取 op**、应用到本地库、把会话与题目列出来。
 *
 * 这是「答案同时出现在两端」真正落地的那一步 —— 之前手机上只有配对页，
 * 电脑识别出的结果手机看不到。
 *
 * 失败一律如实显示（拉取失败 / 未配对），不把「没有新记录」和「拉不到」混成一句。
 */
@Composable
fun RecordsScreen(
    store: RecordStore,
    pairedHost: String?,
    token: String?,
    onBack: () -> Unit,
) {
    var sessions by remember { mutableStateOf(store.sessions()) }
    var detail by remember { mutableStateOf<Pair<String, List<QuestionRow>>?>(null) }
    var status by remember { mutableStateOf("本地已有 ${sessions.size} 条记录") }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun reload() {
        sessions = store.sessions()
        detail = null
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().padding(QsTokens.spaceXl).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(QsTokens.spaceLg),
        ) {
            Text("记录", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
            Text(
                "电脑识别出的结果会自动同步到这里",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Card(
                shape = RoundedCornerShape(QsTokens.radiusCard),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    modifier = Modifier.padding(QsTokens.spaceLg),
                    verticalArrangement = Arrangement.spacedBy(QsTokens.spaceSm),
                ) {
                    if (sessions.isEmpty()) {
                        Text("还没有记录。", style = MaterialTheme.typography.bodyMedium)
                    }
                    sessions.forEach { session ->
                        Text(
                            "${formatTime(session.createdAt)} · ${session.questionCount} 道题"
                                + (session.aiModel?.let { " · $it" } ?: ""),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                        )
                        TextButton(onClick = {
                            detail = session.sessionId to store.questions(session.sessionId)
                        }) {
                            Text("查看题目", style = MaterialTheme.typography.labelLarge)
                        }
                    }
                }
            }

            detail?.let { (sessionId, questions) ->
                Card(
                    shape = RoundedCornerShape(QsTokens.radiusCard),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(QsTokens.spaceLg),
                        verticalArrangement = Arrangement.spacedBy(QsTokens.spaceSm),
                    ) {
                        Text("这条会话的题目（$sessionId）", style = MaterialTheme.typography.labelLarge)
                        if (questions.isEmpty()) {
                            Text("这条会话里没有题目。", style = MaterialTheme.typography.bodySmall)
                        }
                        questions.forEach { question ->
                            Text(
                                "${question.questionNo ?: (question.ordinal + 1)}. ${question.stem}",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Text(
                                "答案：${question.answer.ifEmpty { "（AI 未给出）" }}",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }
                }
            }

            Button(
                onClick = {
                    if (pairedHost == null || token == null) {
                        status = "还没配对：请先在电脑上点「显示配对码」，再用手机配对"
                        return@Button
                    }
                    busy = true
                    status = "正在从 $pairedHost 拉取…"
                    scope.launch {
                        status = withContext(Dispatchers.IO) {
                            runCatching {
                                val count = store.sync(pairedHost, token)
                                "已从主机拉取 $count 条 op"
                            }.getOrElse { error ->
                                "拉取失败：${error.message ?: error::class.simpleName}"
                            }
                        }
                        reload()
                        busy = false
                    }
                },
                enabled = !busy,
                shape = RoundedCornerShape(QsTokens.radiusControl),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (busy) "同步中…" else "从电脑同步")
            }

            TextButton(onClick = onBack, enabled = !busy) {
                Text("返回", style = MaterialTheme.typography.labelLarge)
            }
        }

        Surface(color = MaterialTheme.colorScheme.background) {
            Text(
                text = status,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}

private fun formatTime(epochMs: Long): String =
    SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(epochMs))
