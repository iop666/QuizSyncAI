package com.quizsync.android.core.db

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.execSQL
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Phase 3 的两个关键前提，先钉住：
 * 1. `BundledSQLiteDriver` 真的带 **FTS5 + trigram**（中文检索的命脉，计划 §12 的风险项）；
 * 2. 协议仓的 `schema-v1.sql` 能被原样执行，且表/列与它的 JSON 描述一致。
 */
class SchemaAndFtsTest {

    @Test
    fun `bundled driver has fts5 and trigram tokenizer`() {
        QuizSyncDatabase.open(":memory:", "").use { db ->
            // FTS5 能不能建表。
            db.connection.execSQL(
                "CREATE VIRTUAL TABLE t_fts USING fts5(stem, tokenize='trigram')",
            )
            db.connection.execSQL("INSERT INTO t_fts(stem) VALUES ('已知函数单调递增求参数取值范围')")

            // **trigram 的硬规则：查询词至少 3 个字符**（3 字符切一片）。
            // 实测（SQLite 3.50.1，BundledSQLiteDriver 2.7.1）：
            //   MATCH '单调递增'（4 字）→ 命中；MATCH '单调'（2 字）→ 0 行。
            // 所以客户端搜索必须对 1–2 个字符的查询**兜底走 LIKE**（见 Phase 3 计划 §12）。
            assertEquals(
                1,
                db.connection.countOf("SELECT count(*) FROM t_fts WHERE t_fts MATCH '单调递增'"),
                "4 字中文子串应当命中",
            )
            assertEquals(
                1,
                db.connection.countOf("SELECT count(*) FROM t_fts WHERE t_fts MATCH '已知函数'"),
                "开头 4 字也应当命中",
            )
            assertEquals(
                0,
                db.connection.countOf("SELECT count(*) FROM t_fts WHERE t_fts MATCH '单调'"),
                "2 字查询在 trigram 下天然不命中 —— 必须靠 LIKE 兜底",
            )
            assertEquals(
                1,
                db.connection.countOf("SELECT count(*) FROM t_fts WHERE stem LIKE '%单调%'"),
                "LIKE 兜底能命中 2 字查询",
            )
            assertEquals(
                0,
                db.connection.countOf("SELECT count(*) FROM t_fts WHERE t_fts MATCH '不存在的词'"),
                "不存在的词不该命中",
            )
        }
    }

    @Test
    fun `protocol schema executes and matches its json description`() {
        val sqlFile = java.io.File(QuizSyncDatabase.protocolDir(), "schema/schema-v1.sql")
        val jsonFile = java.io.File(QuizSyncDatabase.protocolDir(), "schema/schema-v1.json")
        assertTrue(sqlFile.isFile, "缺 schema-v1.sql：${sqlFile.absolutePath}")
        assertTrue(jsonFile.isFile, "缺 schema-v1.json：${jsonFile.absolutePath}")

        QuizSyncDatabase.open(":memory:", sqlFile.readText()).use { db ->
            val described = Json.parseToJsonElement(jsonFile.readText())
            val tables = described.jsonObject["tables"]!!.jsonArray
            assertTrue(tables.size >= 11, "schema 描述里至少要 11 张表，实际 ${tables.size}")

            for (table in tables) {
                val name = table.jsonObject["name"]!!.jsonPrimitive.content
                val expectedColumns = table.jsonObject["columns"]!!.jsonArray
                    .map { it.jsonObject["name"]!!.jsonPrimitive.content }
                val actualColumns = db.connection.columnNames(name)

                assertEquals(
                    expectedColumns.sorted(),
                    actualColumns.sorted(),
                    "表 $name 的列与 schema-v1.json 不一致",
                )
            }
        }
    }
}

/** `SELECT count(*)` 的便捷读法。 */
private fun SQLiteConnection.countOf(sql: String): Long {
    prepare(sql).use { statement ->
        assertTrue(statement.step(), "查询没有返回行：$sql")
        return statement.getLong(0)
    }
}

/** 从 `PRAGMA table_info` 读列名（顺序保持建表顺序）。 */
private fun SQLiteConnection.columnNames(table: String): List<String> {
    val names = mutableListOf<String>()
    prepare("PRAGMA table_info($table)").use { statement ->
        while (statement.step()) {
            names.add(statement.getText(1))
        }
    }
    return names
}
