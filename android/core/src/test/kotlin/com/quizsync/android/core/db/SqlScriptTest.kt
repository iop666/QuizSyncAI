package com.quizsync.android.core.db

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 数据层的两条硬约束（都是本机实测出来的，不是猜的）：
 *
 * 1. `SQLiteConnection.execSQL` **一次只执行第一条语句** —— 整份 schema 脚本直接丢进去
 *    只会建出第一张表，而且**不报错**（静默半成品）。所以 `QuizSyncDatabase.open`
 *    必须先 `SqlScript.split` 再逐条执行；这个测试就是它的回归钉子。
 * 2. `SqlScript.split` 要能切对「触发器体里的分号」——切错了建库就失败。
 */
class SqlScriptTest {

    private fun open(): SQLiteConnection = BundledSQLiteDriver().open(":memory:")

    private fun SQLiteConnection.scalar(sql: String): String =
        prepare(sql).use { statement -> if (statement.step()) statement.getText(0) else "<no row>" }

    private fun SQLiteConnection.tableExists(name: String): Boolean =
        scalar("SELECT count(*) FROM sqlite_master WHERE name='$name'") == "1"

    @Test
    fun `execSQL runs only the first statement of a script`() {
        open().use { connection ->
            connection.execSQL("CREATE TABLE a(x TEXT); CREATE TABLE b(y TEXT);")
            assertTrue(connection.tableExists("a"), "第一条语句会执行")
            assertEquals(false, connection.tableExists("b"), "第二条不会执行 —— 必须自己切分")
        }
    }

    @Test
    fun `split keeps trigger bodies intact`() {
        val script = """
            -- 注释里的分号 ; 不算分隔符
            CREATE TABLE t(id TEXT PRIMARY KEY, stem TEXT);
            CREATE INDEX idx_t ON t(stem);
            CREATE TABLE t_log(id TEXT);
            CREATE TRIGGER t_ai AFTER INSERT ON t BEGIN
              INSERT INTO t_log(id) VALUES (new.id);
            END;
            INSERT INTO t(id, stem) VALUES ('1', 'a;b');
        """.trimIndent()

        val statements = SqlScript.split(script)
        assertEquals(5, statements.size, "应当切出 5 条（表 / 索引 / 日志表 / 触发器 / 插入）：$statements")
        assertTrue(statements[3].startsWith("CREATE TRIGGER"), "触发器体不能被切开：${statements[3]}")
        assertTrue(statements[3].trimEnd().endsWith("END"), "触发器要以 END 收尾")
        assertTrue(statements[4].contains("'a;b'"), "字符串里的分号不能当分隔符")

        // 切出来的每一条都能真的执行，触发器也真的生效（说明 BEGIN…END 是完整的）。
        open().use { connection ->
            statements.forEach { connection.execSQL(it) }
            assertTrue(connection.tableExists("t"))
            assertEquals("1", connection.scalar("SELECT count(*) FROM t"))
            assertEquals("1", connection.scalar("SELECT count(*) FROM t_log"), "触发器应当被建出来并生效")
        }
    }

    @Test
    fun `openWithProtocolSchema creates every table of the protocol schema`() {
        QuizSyncDatabase.openWithProtocolSchema(":memory:").use { db ->
            val expected = listOf(
                "devices", "images", "collections", "sessions", "session_images", "questions",
                "tasks", "sync_ops", "settings", "peer_state", "ai_usage",
            )
            for (table in expected) {
                val found = db.connection.scalar(
                    "SELECT count(*) FROM sqlite_master WHERE name='$table'",
                )
                assertEquals("1", found, "协议 schema 里的表 $table 没建出来")
            }
        }
    }
}
