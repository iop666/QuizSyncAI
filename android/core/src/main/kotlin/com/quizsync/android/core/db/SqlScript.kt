package com.quizsync.android.core.db

/**
 * 把一份 SQL 脚本切成一条条语句。
 *
 * 为什么需要它：`SQLiteConnection.execSQL` 一次**只执行第一条语句**（本机实测：
 * `CREATE TABLE a(...); CREATE TABLE b(...);` 之后只有 a 存在，且**不报错**）——
 * 而协议仓的 `schema/schema-v1.sql` 是一整份脚本。切分要照顾三件事：
 * - 字符串字面量里的 `;` 不算分隔符（`'a;b'`）；
 * - `CREATE TRIGGER ... BEGIN ... END;` 里的 `;` 不算（触发器体要完整保留）；
 * - `--` 行注释里的内容整体忽略。
 */
object SqlScript {

    fun split(script: String): List<String> {
        val statements = mutableListOf<String>()
        val current = StringBuilder()
        val word = StringBuilder()
        var inString = false
        var inLineComment = false
        var blockDepth = 0
        var index = 0

        fun flushWord() {
            if (word.isEmpty()) return
            when (word.toString().uppercase()) {
                "BEGIN" -> blockDepth++
                "END" -> if (blockDepth > 0) blockDepth--
            }
            word.clear()
        }

        while (index < script.length) {
            val ch = script[index]
            val next = script.getOrNull(index + 1)

            if (inLineComment) {
                if (ch == '\n') {
                    inLineComment = false
                    current.append(ch)
                }

                index++
                continue
            }

            if (inString) {
                current.append(ch)
                if (ch == '\'') {
                    if (next == '\'') {
                        current.append(next)
                        index += 2
                        continue
                    }

                    inString = false
                }

                index++
                continue
            }

            if (ch == '-' && next == '-') {
                flushWord()
                inLineComment = true
                index += 2
                continue
            }

            if (ch == '\'') {
                flushWord()
                inString = true
                current.append(ch)
                index++
                continue
            }

            // **先结算词，再判分号**：`END;` 里的 END 必须先让块深度归零，
            // 否则那个分号会被当成块内分号，触发器和后面那条插入会被拼成一条。
            if (ch.isLetter()) {
                word.append(ch)
            } else {
                flushWord()
            }

            if (ch == ';' && blockDepth == 0) {
                statements.add(current.toString().trim())
                current.clear()
                index++
                continue
            }

            current.append(ch)
            index++
        }

        flushWord()
        val tail = current.toString().trim()
        if (tail.isNotEmpty()) {
            statements.add(tail)
        }

        return statements.filter { it.isNotBlank() }
    }
}
