package com.quizsync.android.core.sync

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.execSQL
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

/** 应用一条 op 的结果。 */
enum class ApplyResult {
    /** 已入库（新 op，字段按 LWW 落地）。 */
    APPLIED,

    /** `op_id` 已存在 —— 重复投递，直接忽略（`applied` 计数不增）。 */
    DUPLICATE,
}

/**
 * 把对端推来的 op 落到本地库（**逐字段 LWW**）。
 *
 * 语义与 Dart 参考实现 / C# 实现逐条对齐（三者由同一批 `sync.ndjson` 裁判）：
 * - 比较键是 `(lamport, device_id)`，**相等即判负**；
 * - 每个字段各记一条时钟，存进 `field_clocks_json`；
 * - `delete` 只是「写 `deleted_at`」的一种 upsert，同样受 LWW 约束（墓碑）；
 * - `op_id` 幂等：重复投递返回 [ApplyResult.DUPLICATE]；
 * - 新行按 op 的字段建，缺的列走 DEFAULT。
 *
 * **字段名必须白名单**：`fields_json` 的键来自网络，直接拼进 SQL 就是注入。
 */
class SyncApplier(private val connection: SQLiteConnection) {

    private data class Target(val table: String, val idColumn: String, val columns: Set<String>)

    private val targets: Map<String, Target> = mapOf(
        SyncEntity.SESSION to Target(
            "sessions", "session_id",
            setOf(
                "image_hash", "source_device", "status", "question_count", "cached", "collection_id",
                "created_at", "updated_at", "updated_by", "deleted_at", "task_id", "error_message",
                "latency_ms",
            ),
        ),
        SyncEntity.QUESTION to Target(
            "questions", "question_id",
            setOf(
                "session_id", "ordinal", "question_no", "stem", "material", "type", "options_json",
                "choice_json", "answer_text", "analysis", "confidence", "need_review",
                "answer_in_image", "incomplete", "answer_guessed", "warnings_json",
                "analysis_edited", "answer_edited", "created_at", "updated_at", "updated_by",
                "deleted_at",
            ),
        ),
        SyncEntity.COLLECTION to Target(
            "collections", "collection_id",
            setOf("name", "created_at", "updated_at", "updated_by", "deleted_at"),
        ),
        SyncEntity.SESSION_IMAGE to Target(
            "session_images", "session_image_id",
            setOf("session_id", "ordinal", "image_hash", "created_at", "deleted_at"),
        ),
    )

    fun apply(op: SyncOp): ApplyResult {
        if (opExists(op.op_id)) return ApplyResult.DUPLICATE
        insertOpLog(op)
        val target = targets[op.entity] ?: return ApplyResult.APPLIED // 未知实体（含 snapshot）只记账
        applyEntity(op, target)
        return ApplyResult.APPLIED
    }

    private fun opExists(opId: String): Boolean =
        connection.prepare("SELECT 1 FROM sync_ops WHERE op_id = ? LIMIT 1").use { statement ->
            statement.bindText(1, opId)
            statement.step()
        }

    private fun insertOpLog(op: SyncOp) {
        connection.prepare(
            """
            INSERT OR IGNORE INTO sync_ops
              (op_id, device_id, lamport, entity, entity_id, op_type, fields_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { statement ->
            statement.bindText(1, op.op_id)
            statement.bindText(2, op.device_id)
            statement.bindLong(3, op.lamport)
            statement.bindText(4, op.entity)
            statement.bindText(5, op.entity_id)
            statement.bindText(6, op.op_type)
            statement.bindText(7, JsonObject(op.fields_json).toString())
            statement.bindLong(8, op.created_at)
            statement.step()
        }
    }

    private fun applyEntity(op: SyncOp, target: Target) {
        var clocks = mutableMapOf<String, FieldClock>()
        var rowLamport: Long? = null

        connection.prepare(
            "SELECT lamport, field_clocks_json FROM ${target.table} WHERE ${target.idColumn} = ?",
        ).use { statement ->
            statement.bindText(1, op.entity_id)
            if (statement.step()) {
                rowLamport = statement.getLong(0)
                clocks = parseFieldClocks(if (statement.isNull(1)) null else statement.getText(1))
            }
        }

        val winners = mutableMapOf<String, kotlinx.serialization.json.JsonElement?>()
        for ((field, value) in op.fields_json) {
            if (field !in target.columns) continue // 白名单：不认识的列一律丢弃
            val clock = clocks[field]
            if (clock != null && clock.losesTo(op)) continue
            winners[field] = value
            clocks[field] = FieldClock(op.lamport, op.device_id)
        }

        val newLamport = maxOf(rowLamport ?: 0L, op.lamport)
        val clocksJson = encodeFieldClocks(clocks)

        if (rowLamport == null) {
            val names = mutableListOf(target.idColumn)
            val values = mutableListOf<Any?>(op.entity_id)
            for ((field, value) in winners) {
                names.add(field)
                values.add(bindValue(value))
            }
            names.add("lamport")
            values.add(newLamport)
            names.add("field_clocks_json")
            values.add(clocksJson)

            val placeholders = names.indices.joinToString(", ") { "?" }
            connection.prepare(
                "INSERT INTO ${target.table} (${names.joinToString(", ")}) VALUES ($placeholders)",
            ).use { statement ->
                values.forEachIndexed { index, value -> statement.bindAny(index + 1, value) }
                statement.step()
            }
            return
        }

        val sets = mutableListOf<String>()
        val values = mutableListOf<Any?>()
        var position = 1
        for ((field, value) in winners) {
            sets.add("$field = ?")
            values.add(bindValue(value))
            position++
        }
        sets.add("lamport = ?")
        values.add(newLamport)
        sets.add("field_clocks_json = ?")
        values.add(clocksJson)
        values.add(op.entity_id)

        connection.prepare(
            "UPDATE ${target.table} SET ${sets.joinToString(", ")} WHERE ${target.idColumn} = ?",
        ).use { statement ->
            values.forEachIndexed { index, value -> statement.bindAny(index + 1, value) }
            statement.step()
        }
    }

    /** 水位：`MAX(lamport)`（主机的 `/tasks/active` 就是拿它判断「要不要拉一次」）。 */
    fun watermark(): Long =
        connection.prepare("SELECT COALESCE(MAX(lamport), 0) FROM sync_ops").use { statement ->
            if (statement.step()) statement.getLong(0) else 0L
        }

    /** 拉取：本机从某个游标之后的 op（按 lamport 升序）。 */
    fun pull(deviceId: String, sinceLamport: Long, limit: Int = 500): List<SyncOp> {
        val ops = mutableListOf<SyncOp>()
        connection.prepare(
            """
            SELECT op_id, device_id, lamport, entity, entity_id, op_type, fields_json, created_at
            FROM sync_ops WHERE device_id = ? AND lamport > ?
            ORDER BY lamport ASC, op_id ASC LIMIT ?
            """.trimIndent(),
        ).use { statement ->
            statement.bindText(1, deviceId)
            statement.bindLong(2, sinceLamport)
            statement.bindLong(3, limit.toLong() + 1)
            while (statement.step()) {
                val fields = Json.parseToJsonElement(statement.getText(6)) as? JsonObject
                    ?: JsonObject(emptyMap())
                ops.add(
                    SyncOp(
                        op_id = statement.getText(0),
                        device_id = statement.getText(1),
                        lamport = statement.getLong(2),
                        entity = statement.getText(3),
                        entity_id = statement.getText(4),
                        op_type = statement.getText(5),
                        fields_json = fields,
                        created_at = statement.getLong(7),
                    ),
                )
            }
        }
        return ops
    }
}

/** 绑定任意标量（SQLite 只认这几种）。 */
private fun androidx.sqlite.SQLiteStatement.bindAny(index: Int, value: Any?) {
    when (value) {
        null -> bindNull(index)
        is String -> bindText(index, value)
        is Long -> bindLong(index, value)
        is Int -> bindLong(index, value.toLong())
        is Double -> bindDouble(index, value)
        is Boolean -> bindLong(index, if (value) 1L else 0L)
        else -> bindText(index, value.toString())
    }
}
