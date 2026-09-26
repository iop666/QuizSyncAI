package com.quizsync.android.core.db

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import java.io.File

/**
 * 本地库（Android 内核的数据层）。
 *
 * **schema 的唯一来源是协议仓的 `schema/schema-v1.sql`** —— 我们不在这里手抄一遍
 * 建表语句：抄一遍就有两个真相，早晚漂移。测试 `SchemaParityTest` 会把「执行这份
 * DDL 得到的结构」与协议仓的 JSON 描述逐列比对。
 *
 * 用的是 `BundledSQLiteDriver`：它自带 SQLite（含 FTS5 与 **trigram 分词器**），
 * 不看 ROM 的脸色 —— 中文检索不能赌系统 SQLite。
 */
class QuizSyncDatabase private constructor(
    val connection: SQLiteConnection,
) : AutoCloseable {

    companion object {
        /** 打开（或新建）一个库；[path] 传 `:memory:` 时是内存库。 */
        fun open(path: String, schemaSql: String): QuizSyncDatabase {
            val connection = connect(path)
            // `execSQL` 一次只跑一条语句（实测），所以这里逐条执行 —— 直接丢整份
            // 脚本进去的话，**只有第一张表会被建出来**，而且不报错。
            for (statement in SqlScript.split(schemaSql)) {
                connection.execSQL(statement)
            }
            return QuizSyncDatabase(connection)
        }

        /** 开连接 + 两个 PRAGMA（建库与打开既有库共用）。 */
        private fun connect(path: String): SQLiteConnection {
            val connection = BundledSQLiteDriver().open(path)
            connection.execSQL("PRAGMA foreign_keys=ON")
            if (path != ":memory:") {
                connection.execSQL("PRAGMA journal_mode=WAL")
            }
            return connection
        }

        /** 从协议仓的 schema 文件建库（路径由 `QS_PROTOCOL_DIR` 或默认同级仓库给出）。 */
        fun openWithProtocolSchema(path: String): QuizSyncDatabase =
            open(path, File(protocolDir(), "schema/schema-v1.sql").readText())

        /**
         * 打开一个**已经建好**的库（不执行 DDL）。
         *
         * 协议 schema 里的索引是裸 `CREATE INDEX`（没有 `IF NOT EXISTS`），对既有库
         * 再跑一遍会直接抛 `index ... already exists` —— 实测踩到。所以「首次建库」与
         * 「打开既有库」必须是两条路。
         */
        fun openExisting(path: String): QuizSyncDatabase = QuizSyncDatabase(connect(path))

        /**
         * 协议仓的位置：优先环境变量 `QS_PROTOCOL_DIR`（CI 里指到 checkout 的路径），
         * 否则取与本仓库同级的 `QuizSyncProtocol`。找不到就**直接抛**，不静默退化。
         */
        fun protocolDir(): File {
            val configured = System.getenv("QS_PROTOCOL_DIR")
            val candidates = buildList {
                if (!configured.isNullOrBlank()) add(File(configured))
                add(File("../QuizSyncProtocol"))
                add(File("../../QuizSyncProtocol"))
                add(File("../../../QuizSyncProtocol"))
            }
            val found = candidates.firstOrNull { File(it, "schema/schema-v1.sql").isFile }
            return found ?: error(
                "找不到协议仓（需要 schema/schema-v1.sql）。试过：" +
                    candidates.joinToString { it.absolutePath } +
                    "；可用环境变量 QS_PROTOCOL_DIR 指定。",
            )
        }
    }

    override fun close() {
        connection.close()
    }
}
