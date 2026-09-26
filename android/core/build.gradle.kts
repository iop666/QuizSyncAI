plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
}

kotlin {
    jvmToolchain(17)
    compilerOptions {
        allWarningsAsErrors.set(true)
    }
}

dependencies {
    // androidx.sqlite 的 BundledSQLiteDriver：**自带 SQLite**（含 FTS5 + trigram），
    // 不赌系统 SQLite 版本 —— Phase 3 计划 §12 点名的风险项就是它。
    api("androidx.sqlite:sqlite-bundled:2.7.1")

    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")

    // HTTP 客户端：Android 上没有 java.net.http（API 34 才有），所以按计划用 OkHttp。
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    testImplementation(kotlin("test"))
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
}

tasks.test {
    useJUnitPlatform()
    // 协议仓的 schema/向量目录：默认取同级仓库（可用环境变量覆盖，CI 里指到 checkout 的路径）。
    environment("QS_PROTOCOL_DIR", System.getenv("QS_PROTOCOL_DIR")
        ?: rootProject.file("../../QuizSyncProtocol").absolutePath)
    testLogging {
        events("passed", "failed", "skipped")
    }
}
