package com.quizsync.android.core.db

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.execSQL
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * **旧库兼容**：Flutter 版（drift，schemaVersion 3）写出来的库，原生 2.0 的内核必须能打开、
 * 读出正确内容，并且能在它上面继续写。
 *
 * 样本由 Dart 侧生成并提交（`packages/quizsync_core/test/db/legacy_fixture_test.dart`）：
 * 二进制库没法在 Kotlin 侧现造（那要跑 Dart）。这一条守的是「升级不砸用户数据」。
 */
class LegacyDatabaseCompatibilityTest {

    /** 把 classpath 上的样本拷到临时文件（SQLite 要能写，不能直接读 jar 内资源）。 */
    private fun legacyDatabase(): File {
        val resource = javaClass.classLoader.getResourceAsStream("legacy-drift-v3.db")
            ?: error("找不到旧库样本 legacy-drift-v3.db（先跑 dart test test/db/legacy_fixture_test.dart）")
        val temp = Files.createTempFile("legacy-drift-", ".db").toFile()
        resource.use { input -> temp.outputStream().use { input.copyTo(it) } }
        return temp
    }

    @Test
    fun `opens the legacy drift v3 database and reads its rows`() {
        val file = legacyDatabase()
        QuizSyncDatabase.openExisting(file.absolutePath).use { db ->
            val connection = db.connection

            // 1) 旧库的 schemaVersion 仍是 drift 的 3（新内核不去改它 —— 迁移是显式动作）。
            assertEquals(3L, connection.scalarLong("PRAGMA user_version"))

            // 2) 旧版本写的数据要能原样读出来。
            assertEquals("旧库合集", connection.scalarText("SELECT name FROM collections WHERE collection_id = 'c-legacy'"))
            assertEquals("done", connection.scalarText("SELECT status FROM sessions WHERE session_id = 's-legacy'"))
            assertEquals(2L, connection.scalarLong("SELECT COUNT(*) FROM questions WHERE session_id = 's-legacy'"))

            // 3) 选项与答案是 JSON 文本，形态与契约一致（'single' 题选 B）。
            assertEquals("[\"B\"]", connection.scalarText("SELECT choice_json FROM questions WHERE question_id = 'q-legacy-1'"))
            assertEquals("H2O", connection.scalarText("SELECT answer_text FROM questions WHERE question_id = 'q-legacy-2'"))
        }
    }

    @Test
    fun `new kernel can keep writing into the legacy database`() {
        val file = legacyDatabase()
        QuizSyncDatabase.openExisting(file.absolutePath).use { db ->
            val connection = db.connection

            // 新内核对同一批表继续写：新增一道题 + 一条同步 op（列集合必须与旧库一致，
            // 少一列就会在这里炸出来 —— 这正是这条用例要守的）。
            connection.execSQL(
                "INSERT INTO questions (question_id, session_id, ordinal, stem, type, options_json, choice_json, " +
                    "analysis, confidence, created_at, updated_at, updated_by, lamport) " +
                    "VALUES ('q-new', 's-legacy', 2, '新内核写的题', 'single', '[]', '[]', '', 0.5, " +
                    "1700000001000, 1700000001000, 'new-device', 5)",
            )
            connection.execSQL(
                "INSERT INTO sync_ops (op_id, device_id, lamport, entity, entity_id, op_type, fields_json, created_at) " +
                    "VALUES ('op-new', 'new-device', 5, 'question', 'q-new', 'upsert', '{}', 1700000001000)",
            )

            assertEquals(3L, connection.scalarLong("SELECT COUNT(*) FROM questions WHERE session_id = 's-legacy'"))
            assertEquals(1L, connection.scalarLong("SELECT COUNT(*) FROM sync_ops WHERE device_id = 'new-device'"))
        }
    }

    @Test
    fun `legacy database has every table the new kernel touches`() {
        val file = legacyDatabase()
        QuizSyncDatabase.openExisting(file.absolutePath).use { db ->
            val names = mutableSetOf<String>()
            val statement = db.connection.prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
            try {
                while (statement.step()) {
                    names += statement.getText(0)
                }
            } finally {
                statement.close()
            }

            // 新内核要用的表，旧库里必须都在（缺一个就说明两个实现的数据模型分叉了）。
            for (expected in listOf(
                "collections", "sessions", "questions", "session_images", "images",
                "sync_ops", "peer_state", "tasks", "settings", "ai_usage", "devices",
            )) {
                assertTrue(names.contains(expected), "旧库缺少表 $expected（现有：${names.sorted()}）")
            }
        }
    }

    @Test
    fun `legacy fixture is present and self contained`() {
        val file = legacyDatabase()
        assertTrue(file.length() > 0, "样本是空的")
        // 自包含：不该再依赖同名的 -wal / -shm 才能读出数据（生成时已关连接合并 WAL）。
        assertTrue(!File("${file.absolutePath}-wal").exists())
    }

    private fun SQLiteConnection.scalarText(sql: String): String? {
        val statement = prepare(sql)
        return try {
            if (statement.step()) statement.getText(0) else null
        } finally {
            statement.close()
        }
    }

    private fun SQLiteConnection.scalarLong(sql: String): Long {
        val statement = prepare(sql)
        return try {
            if (statement.step()) statement.getLong(0) else 0L
        } finally {
            statement.close()
        }
    }
}
