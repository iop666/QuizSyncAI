import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 签名配置：keystore/quizsync-release.jks + android/key.properties（均不入库）。
// 生成方式见 tools/gen_keystore.ps1 与 README。
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    namespace = "com.example.quizsync_android"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // M24：applicationId 从 com.example.quizsync_android 改成正式反向域名。
        // 这不只是「好看」：`com.example.*` 是被保留的示例命名空间（Play 拒收）。
        // 代价是**包名变了，已装用户不能覆盖升级**，必须先卸载旧版再装（见 README）。
        // 注意 `namespace` 保持不动（它是 R 类与 `.MainActivity` 这类相对类名的解析基准，
        // 与安装身份无关；改它要连带搬 6 个 Kotlin 文件的目录与 import，没有功能收益）。
        applicationId = "com.quizsync.android"
        minSdk = 26
        targetSdk = 34
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("storeFile")) {
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.properties 存在时用正式签名；否则退回 debug 签名（本机构建用）。
            signingConfig = if (keystoreProperties.containsKey("storeFile")) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 系统栏外观桥（M13）：WindowInsetsControllerCompat 是官方推荐、未废弃的做法
    // （Flutter 引擎自己也用它）。版本取 Gradle 缓存里已有的，避免为这一处依赖
    // 触发新的网络解析；与引擎要求冲突时 Gradle 会取高版本。
    implementation("androidx.core:core:1.13.1")
}
