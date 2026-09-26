plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.quizsync.android.dev"
    compileSdk = 36

    defaultConfig {
        // **开发期专用包名**：与手机上正在用的 1.2.1（com.quizsync.android）**并存**，
        // 开发包绝不会覆盖用户那个能用的版本（计划 §Phase 3 的回滚策略）。
        applicationId = "com.quizsync.android.dev"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "2.0.0-dev"
    }

    buildTypes {
        release {
            // 开发期不配签名：release 只用于「能不能编出来」的验证。
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(project(":core"))
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")

    // Compose BOM 统一版本（避免各库版本互相打架）。
    implementation(platform("androidx.compose:compose-bom:2025.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation(kotlin("test"))
}
