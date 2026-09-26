package com.quizsync.android.core.sync

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.execSQL
import com.quizsync.android.core.db.QuizSyncDatabase
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * **Kotlin 同步引擎 vs 一致性向量**（Phase 3 的「用向量对拍」）。
 *
 * 只跑 `sync.ndjson` 里**与同步内核有关**的步骤：推 op（归属校验 → 逐字段 LWW → op_id 幂等）
 * 与快照里那几条题目断言。需要 HTTP 上传 / 任务流水线的步骤**显式记账为「跳过 + 原因」**，
 * 并在最后断言「已覆盖 + 已跳过 = 全部」—— 这样「悄悄少跑几步」是不可能的。
 */
class SyncVectorParityTest {

    private val protocolDir: File = QuizSyncDatabase.protocolDir()

    /** 向量里的 `auth` 取值 → 设备号（由配对步骤定义：`device` 是第一台，`token2` 是第二台）。 */
    private val deviceByAuth = mapOf("device" to "android-device-1", "device:token2" to "android-device-2")

    @Test
    fun `sync vectors judge the Kotlin applier`() {
        val steps = File(protocolDir, "conformance/vectors/sync.ndjson").readLines()
            .filter { it.isNotBlank() }
            .map { Json.parseToJsonElement(it).jsonObject }

        QuizSyncDatabase.openWithProtocolSchema(":memory:").use { db ->
            val applier = SyncApplier(db.connection)
            var covered = 0
            val skipped = mutableListOf<String>()

            for (step in steps) {
                val number = step["step"]!!.jsonPrimitive.content
                val title = step["title"]?.jsonPrimitive?.content ?: ""
                val action = step["do"]!!.jsonObject

                when {
                    // 推 op：这是本测试的主角。
                    action["http"]?.jsonObject?.get("path")?.jsonPrimitive?.content == "/api/v1/sync/ops" &&
                        action["http"]!!.jsonObject["method"]?.jsonPrimitive?.content == "POST" -> {
                        val http = action["http"]!!.jsonObject
                        val auth = http["auth"]?.jsonPrimitive?.content ?: "none"
                        val caller = deviceByAuth[auth] ?: error("第 $number 步的 auth=$auth 没在测试里映射")
                        val ops = http["json"]!!.jsonObject["ops"]!!.jsonArray

                        var applied = 0
                        var rejected = 0
                        for (raw in ops) {
                            val op = SyncOp.parse(raw)
                            // 主机自己的 op 会被静默跳过（客户端只是在回推历史）。
                            if (op.device_id == "server-device-1") continue
                            if (op.device_id != caller) {
                                rejected++
                                continue
                            }
                            if (applier.apply(op) == ApplyResult.APPLIED) applied++
                        }

                        val expected = step["expect"]?.jsonObject
                        assertEquals(
                            expected?.get("json")?.jsonObject?.get("applied")?.jsonPrimitive?.content?.toInt(),
                            applied,
                            "第 $number 步 applied（$title）",
                        )
                        assertEquals(
                            expected?.get("json")?.jsonObject?.get("rejected")?.jsonPrimitive?.content?.toInt(),
                            rejected,
                            "第 $number 步 rejected（$title）",
                        )
                        covered++
                    }

                    // 快照里的题目断言：直接读库比对（本增量还没有 HTTP 层）。
                    step["expect"]?.jsonObject?.get("json_contains")?.jsonObject?.get("questions") is JsonArray -> {
                        val expectedQuestions =
                            step["expect"]!!.jsonObject["json_contains"]!!.jsonObject["questions"]!!.jsonArray
                        for (expectedQuestion in expectedQuestions) {
                            val wanted = expectedQuestion.jsonObject
                            val questionId = wanted["question_id"]!!.jsonPrimitive.content
                            val row = db.connection.rowOrNull("questions", "question_id", questionId)
                            for ((field, value) in wanted) {
                                if (field == "question_id") continue
                                val expectedText = (value as? JsonPrimitive)?.content
                                assertEquals(
                                    expectedText,
                                    row[field]?.toString(),
                                    "第 $number 步：题目 $questionId 的 $field",
                                )
                            }
                        }
                        covered++
                    }

                    // 快照「没有题目」的断言（墓碑生效）。
                    step["expect"]?.jsonObject?.get("json")?.jsonObject?.get("questions") is JsonArray -> {
                        val count = db.connection.scalarLong("SELECT count(*) FROM questions WHERE deleted_at IS NULL")
                        assertEquals(0L, count, "第 $number 步：软删除的题目不该再出现在快照里")
                        covered++
                    }

                    // 建库/配对/时钟/种子/WS/需要任务流水线的步骤：显式记账跳过。
                    else -> skipped.add("第 $number 步：$title")
                }
            }

            println("SYNC-PARITY 已覆盖 $covered 步；跳过 ${skipped.size} 步：")
            skipped.forEach { println("SYNC-PARITY   跳过 $it") }

            // 诚实账本：每一步要么被覆盖，要么被显式跳过（数量对得上）。
            assertEquals(steps.size, covered + skipped.size, "有步骤既没被覆盖也没被记账")
            assertTrue(covered >= 10, "同步内核至少应当覆盖 10 步，实际 $covered")
        }
    }
}

private fun SQLiteConnection.scalarLong(sql: String): Long =
    prepare(sql).use { statement -> if (statement.step()) statement.getLong(0) else 0L }

/** 读一行成 `列名 → 值`；**按列类型读**（TEXT 列用 getLong 会被强转成 0）。
 *  `getColumnType` 给的是 SQLite 基本类型码（C API 口径）：1=INTEGER 2=FLOAT 3=TEXT 4=BLOB 5=NULL。 */
private fun SQLiteConnection.rowOrNull(table: String, idColumn: String, id: String): Map<String, Any?> {
    val row = mutableMapOf<String, Any?>()
    prepare("SELECT * FROM $table WHERE $idColumn = ?").use { statement ->
        statement.bindText(1, id)
        if (!statement.step()) return emptyMap()
        for (index in 0 until statement.getColumnCount()) {
            val name = statement.getColumnName(index)
            row[name] = when (statement.getColumnType(index)) {
                5 -> null // NULL
                3 -> statement.getText(index)
                1 -> statement.getLong(index)
                2 -> statement.getDouble(index)
                else -> "<blob>"
            }
        }
    }
    return row
}
