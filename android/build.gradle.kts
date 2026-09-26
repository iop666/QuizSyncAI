plugins {
    // 版本与 Flutter 安卓工程对齐：Kotlin 2.4.0。
    kotlin("jvm") version "2.4.0" apply false
    kotlin("plugin.serialization") version "2.4.0" apply false
    // Phase 4 起：Android 应用 + Compose。
    // AGP 8.13.2 与 Gradle 8.13 配套（AGP 9.x 要求 Gradle 9.x，本工程用系统装的 8.13）。
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // Kotlin 2.x 起 Compose 编译器随 Kotlin 版本走（不再单独用 composeOptions）。
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.0" apply false
}

allprojects {
    group = "com.quizsync.android"
    version = "2.0.0"
}
