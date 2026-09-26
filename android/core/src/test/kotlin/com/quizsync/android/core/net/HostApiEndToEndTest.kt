package com.quizsync.android.core.net

import androidx.sqlite.execSQL
import com.quizsync.android.core.db.QuizSyncDatabase
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.net.ServerSocket
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * **跨实现端到端**：Kotlin 客户端 → 真实的 C# Server（Phase 2 的产物）。
 *
 * 这是 Phase 3 计划里「Kotlin 内核 + 一个可打的 Server」那条依赖的正面验收：
 * 起真进程、走真 HTTP、配对 → 上传 → 建任务 → 轮询到 done。
 *
 * 服务端位置：环境变量 `QS_SERVER_DLL`，否则取 QuizSyncServer 仓的发布产物。
 * **找不到就直接失败**（不静默跳过）—— 这个测试的意义就是「两个实现真的能对话」，
 * 悄悄变成绿的就是自欺。
 */
class HostApiEndToEndTest {

    private var process: Process? = null
    private val serverOutput = StringBuilder()

    @AfterTest
    fun stopServer() {
        process?.let { p ->
            p.destroy()
            if (!p.waitFor(5, TimeUnit.SECONDS)) {
                p.destroyForcibly()
            }
        }
        process = null
    }

    /**
     * 把子进程输出**边读边攒**。
     *
     * 不要用 `readText()`：那会读到 EOF，而服务端还活着 —— 实测直接把测试挂死。
     * 顺带也避免了管道缓冲区被写满导致子进程阻塞。
     */
    private fun drainOutput(started: Process) {
        Thread {
            runCatching {
                started.inputStream.bufferedReader().forEachLine { line ->
                    synchronized(serverOutput) {
                        serverOutput.appendLine(line)
                        if (serverOutput.length > 8_000) {
                            serverOutput.delete(0, serverOutput.length - 8_000)
                        }
                    }
                }
            }
        }.apply { isDaemon = true }.start()
    }

    private fun serverLog(): String = synchronized(serverOutput) { serverOutput.toString() }

    private fun serverDll(): File {
        val configured = System.getenv("QS_SERVER_DLL")
        // 以协议仓的父目录（= 三个仓共同的上级目录）为锚点，比相对路径稳。
        val anchor = QuizSyncDatabase.protocolDir().parentFile
        val candidates = buildList {
            if (!configured.isNullOrBlank()) add(File(configured))
            add(File(anchor, "QuizSyncServer/src/QuizSync.Server.Cli/bin/Release/publish/QuizSync.Server.Cli.dll"))
            add(File("../../../QuizSyncServer/src/QuizSync.Server.Cli/bin/Release/publish/QuizSync.Server.Cli.dll"))
        }
        return candidates.firstOrNull { it.isFile }
            ?: error(
                "找不到 C# 服务端产物。先执行：\n" +
                    "  dotnet publish QuizSyncServer/src/QuizSync.Server.Cli -c Release -o src/QuizSync.Server.Cli/bin/Release/publish\n" +
                    "或用环境变量 QS_SERVER_DLL 指定 dll。试过：" +
                    candidates.joinToString { it.absolutePath },
            )
    }

    /// dotnet 可执行文件：优先环境变量 `QS_DOTNET`，否则用 PATH 里的 `dotnet`。
    /// **不写死任何机器路径**（仓库是公开的，写死等于泄漏开发机的目录结构）。
    private fun dotnet(): String {
        val configured = System.getenv("QS_DOTNET")
        if (!configured.isNullOrBlank()) return configured
        return "dotnet"
    }

    private fun freePort(): Int = ServerSocket(0).use { it.localPort }

    @Test
    fun `kotlin client pairs uploads and gets a result from the real C# server`() {
        val dll = serverDll()
        val dataDir = java.nio.file.Files.createTempDirectory("qs-kotlin-e2e-").toFile()
        val port = freePort()

        val started = ProcessBuilder(
            dotnet(), dll.absolutePath, "run", "--port", port.toString(), "--data", dataDir.absolutePath,
        ).redirectErrorStream(true).start()
        process = started
        drainOutput(started)

        try {
            val api = HostApi("http://127.0.0.1:$port")

            // 1) 探活：等 /health 起来（最多 20 秒）。
            val deadline = System.currentTimeMillis() + 20_000
            var healthy = false
            while (System.currentTimeMillis() < deadline) {
                val ok = runCatching { api.info().status == 200 }.getOrDefault(false)
                if (ok) {
                    healthy = true
                    break
                }
                Thread.sleep(250)
            }
            assertTrue(healthy, "服务端没在 20 秒内起来（$port）。进程输出：\n${serverLog()}")

            // 2) 未配对时受保护端点应当 401（负向检查）。
            assertEquals(401, api.collections().status, "没有 token 时读合集应当 401")

            // 3) 读配对码：走本机控制面（回环 + control.token）。
            val controlToken = File(dataDir, "control.token").readText().trim()
            assertTrue(controlToken.length == 64, "控制令牌应当是 64 位十六进制")
            val pairCode = java.net.http.HttpClient.newHttpClient().send(
                java.net.http.HttpRequest.newBuilder(java.net.URI("http://127.0.0.1:$port/api/v1/pair/code"))
                    .header("X-QS-Control", controlToken)
                    .GET().build(),
                java.net.http.HttpResponse.BodyHandlers.ofString(),
            ).body()
            val code = Json.parseToJsonElement(pairCode).jsonObject["code"]!!.jsonPrimitive.content
            assertEquals(6, code.length, "配对码是 6 位")

            // 4) 配对 → 自动记住 token。
            val pair = api.pair(code, deviceId = "android-kotlin-1", deviceName = "Kotlin 测试机")
            assertEquals(200, pair.status, "配对应当成功：${pair.rawText}")
            assertTrue(api.hasToken(), "配对后应当记住 token")
            assertEquals(200, api.collections().status, "带上 token 后读合集应当 200")

            // 5) 上传一页图（内容寻址：响应给 image_hash）。
            val jpeg = ByteArray(1024).also {
                it[0] = 0xFF.toByte(); it[1] = 0xD8.toByte(); it[2] = 0xFF.toByte(); it[3] = 0xD9.toByte()
            }
            val upload = api.uploadImage(jpeg)
            assertEquals(200, upload.status, "上传应当成功：${upload.rawText}")
            val hash = assertNotNull(upload.string("image_hash"), "上传响应要带 image_hash")
            assertEquals(64, hash.length)
            assertEquals(false, upload.jsonObject()["existed"]!!.jsonPrimitive.content.toBoolean())

            // 重复上传同一张图 → existed=true（内容寻址去重）。
            val again = api.uploadImage(jpeg)
            assertEquals(true, again.jsonObject()["existed"]!!.jsonPrimitive.content.toBoolean())

            // 6) 给主机播种一个合集（与向量回放器的 seed 同义：任务必须落在合集里）。
            QuizSyncDatabase.openExisting(File(dataDir, "quizsync.db").absolutePath).use { db ->
                db.connection.execSQL(
                    "INSERT INTO collections (collection_id, name, created_at, updated_at, updated_by, lamport) " +
                        "VALUES ('c-kotlin', 'Kotlin E2E 合集', 1700000000000, 1700000000000, 'server-device-1', 0)",
                )
                db.connection.execSQL(
                    "INSERT INTO settings (key, value) VALUES ('active_collection_id', 'c-kotlin')",
                )
            }

            // 7) 建任务 → 202（恒 202，不是 200）→ 轮询到 done。
            val task = api.createTask("t-kotlin-1", hash, "android-kotlin-1")
            assertEquals(202, task.status, "建任务恒 202：${task.status} ${task.rawText}")
            assertEquals("queued", task.string("status"))
            assertEquals(0, task.int("question_count"), "提交那一刻是 0 题（不是分析完之后的值）")

            val done = api.awaitTask("t-kotlin-1")
            assertEquals("done", done.string("status"), "任务应当跑到 done：${done.rawText}")
            val session = assertNotNull(done.jsonObject()["session"], "done 的任务视图要带 session")
            assertEquals(1, session.jsonObject["question_count"]!!.jsonPrimitive.content.toInt(), "fixture 识别出 1 题")
            assertEquals("done", session.jsonObject["status"]!!.jsonPrimitive.content)

            // 8) 同一 task_id 再提一次 → 幂等：返回既有状态且不再识别。
            val repeat = api.createTask("t-kotlin-1", hash, "android-kotlin-1")
            assertEquals(202, repeat.status)
            assertEquals("done", repeat.string("status"))
            assertEquals(true, repeat.jsonObject()["cached"]!!.jsonPrimitive.content.toBoolean())

            // 9) 推一条 op：冒充别人（device_id 与调用者不符）会被计成 rejected。
            val push = api.pushOps(
                """{"ops":[{"op_id":"op-kotlin-1","device_id":"someone-else","lamport":1,
                   "entity":"question","entity_id":"q-kotlin-1","op_type":"upsert","fields_json":{}}]}""",
            )
            assertEquals(200, push.status, "推 op 应当 200：${push.rawText}")
            assertEquals(0, push.int("applied"))
            assertEquals(1, push.int("rejected"), "冒充别人的 op 必须被拒")
        } finally {
            started.destroy()
        }
    }
}
