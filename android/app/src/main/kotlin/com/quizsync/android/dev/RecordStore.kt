package com.quizsync.android.dev

import android.content.Context
import com.quizsync.android.core.db.QuizSyncDatabase
import com.quizsync.android.core.net.HostApi
import com.quizsync.android.core.sync.SyncApplier
import com.quizsync.android.core.sync.SyncOp
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import java.io.File

/** 记录列表用的一行会话。 */
data class SessionRow(
    val sessionId: String,
    val questionCount: Int,
    val createdAt: Long,
    val sourceDevice: String,
    val aiModel: String?,
)

/** 记录列表用的一道题。 */
data class QuestionRow(
    val ordinal: Int,
    val questionNo: String?,
    val stem: String,
    val answer: String,
)

/**
 * 手机侧的记录存储：**持久库 + 从主机拉 op + 应用 + 查询**。
 *
 * 三件事都有现成的内核，这里只做接线：
 * * `QuizSyncDatabase`（协议 schema 随 APK 走 assets）；
 * * `SyncApplier`（逐字段 LWW，已与一致性向量对拍过）；
 * * `HostApi.pullOps`（用配对时拿到的 token）。
 *
 * **两条与 Windows 侧同一个坑，务必按这个顺序**：
 * 1. 协议 DDL **不幂等** —— 库已存在时必须 `openExisting`，不能拿 schema 再跑一遍
 *    （Windows 侧就是在这里抛了 `index ... already exists`）；
 * 2. 拉取要带 **本地水位**（`applier.watermark()`），否则每次都全量重拉。
 */
class RecordStore(context: Context, schemaSql: String, private val selfDeviceId: String) {
    private val file = File(context.filesDir, "quizsync.db")
    private val database: QuizSyncDatabase =
        if (file.exists()) QuizSyncDatabase.openExisting(file.absolutePath)
        else QuizSyncDatabase.open(file.absolutePath, schemaSql)

    private val applier = SyncApplier(database.connection)

    /**
     * 从主机拉 op 并应用。返回本次应用了几条（0 表示没有新东西）。
     *
     * **`from_device` 是「要拉谁的 op」**（`spec/04-http-api.md` §1.3.13 / §1.4.3 写得很明确：
     * 它是**来源设备**维度，既不是「我」也不是「发给谁」）。第十五轮实测栽在这里：我传的是
     * **手机自己的 deviceId** → 等价于「只拉我自己产生的 op」→ 屏幕上显示「已从主机拉取 0 条 op」，
     * 而服务端库里有 op。
     *
     * 所以这里按协议的做法来：**对每个来源设备各拉一次** —— 主机自己的 `/info.device_id`
     * （主机直接产生的改动）加上 `/devices` 里所有已配对设备（排除自己）。
     * 游标暂用 0（全量重拉）：applier 按 `op_id` 幂等，重复投递是安全的；
     * 「每个来源设备各自一条独立游标」是协议里的模型，作为后续优化（现在这点数据量不值得先做）。
     */
    fun sync(host: String, token: String): Int {
        val api = HostApi(host)
        api.setToken(token)

        val sources = linkedSetOf<String>()
        api.info().string("device_id")?.takeIf { it.isNotBlank() }?.let { sources += it }
        for (element in api.devices().jsonObject()["devices"]?.jsonArray ?: emptyList()) {
            element.jsonObject["device_id"]?.toString()?.trim('"')
                ?.takeIf { it.isNotBlank() }?.let { sources += it }
        }
        sources -= selfDeviceId

        if (sources.isEmpty()) {
            // 没有任何来源设备：只可能是「服务端没报告自己的 device_id」，如实说出来。
            error("主机没有可拉取的来源设备（/info 与 /devices 都没给 device_id）")
        }

        var applied = 0
        for (source in sources) {
            val response = api.pullOps(fromDevice = source, sinceLamport = 0)
            if (response.status !in 200..299) {
                error("拉取 $source 的 op 失败：${response.status}"
                    + (response.string("message")?.let { "：$it" } ?: ""))
            }

            val ops = response.jsonObject()["ops"]?.jsonArray?.map { SyncOp.parse(it) } ?: emptyList()
            ops.forEach { applier.apply(it) }
            applied += ops.size
        }

        return applied
    }

    fun sessions(limit: Int = 50): List<SessionRow> {
        val rows = mutableListOf<SessionRow>()
        val statement = database.connection.prepare(
            """
            SELECT session_id, question_count, created_at, source_device, ai_model
              FROM sessions
             WHERE deleted_at IS NULL
             ORDER BY created_at DESC, rowid DESC
             LIMIT ?
            """.trimIndent(),
        )
        try {
            statement.bindLong(1, limit.toLong())
            while (statement.step()) {
                rows += SessionRow(
                    sessionId = statement.getText(0),
                    questionCount = statement.getLong(1).toInt(),
                    createdAt = statement.getLong(2),
                    sourceDevice = statement.getText(3),
                    aiModel = if (statement.isNull(4)) null else statement.getText(4),
                )
            }
        } finally {
            statement.close()
        }
        return rows
    }

    fun questions(sessionId: String): List<QuestionRow> {
        val rows = mutableListOf<QuestionRow>()
        val statement = database.connection.prepare(
            """
            SELECT ordinal, question_no, stem, answer_text, choice_json
              FROM questions
             WHERE session_id = ? AND deleted_at IS NULL
             ORDER BY ordinal
            """.trimIndent(),
        )
        try {
            statement.bindText(1, sessionId)
            while (statement.step()) {
                val answerText = if (statement.isNull(3)) null else statement.getText(3)
                val choices = if (statement.isNull(4)) null else statement.getText(4)
                rows += QuestionRow(
                    ordinal = statement.getLong(0).toInt(),
                    questionNo = if (statement.isNull(1)) null else statement.getText(1),
                    stem = statement.getText(2),
                    // 选择题的答案在 choice_json 里（answer_text 是空的）—— 与落库时的写法对应。
                    answer = answerText ?: parseChoices(choices),
                )
            }
        } finally {
            statement.close()
        }
        return rows
    }

    private fun parseChoices(raw: String?): String {
        if (raw.isNullOrBlank()) return ""
        return runCatching {
            kotlinx.serialization.json.Json.parseToJsonElement(raw).jsonArray
                .joinToString(" ") { it.toString().trim('"') }
        }.getOrDefault("")
    }

    fun close() = database.close()
}
