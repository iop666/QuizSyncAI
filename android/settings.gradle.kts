// Android 内核（Phase 3）：先做成 Kotlin/JVM 模块，跑得动、测得动；
// 之后搬进 app module（Kotlin 代码与 Room 映射两边通用）。
//
// 镜像必须保留：本机 maven.google.com 20s 超时（见 AGENTS.md 网络事实）。
pluginManagement {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
}

rootProject.name = "QuizSyncAndroid"
include(":core")
// Phase 4 起的原生 UI：Compose + 设计系统（applicationId 带 .dev 后缀，与在用版本并存）
include(":app")
