plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingEnvironment = listOf(
    "LAN_SIMPLE_FILE_KEYSTORE",
    "LAN_SIMPLE_FILE_STORE_PASSWORD",
    "LAN_SIMPLE_FILE_KEY_ALIAS",
    "LAN_SIMPLE_FILE_KEY_PASSWORD",
).associateWith { System.getenv(it) }
val hasReleaseSigning = signingEnvironment.values.all { !it.isNullOrBlank() }
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) } &&
    !hasReleaseSigning) {
    throw GradleException("Release signing is required; see tool/build_android_release.ps1")
}

android {
    namespace = "com.lansimplefile.lan_simple_file"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lansimplefile.lan_simple_file"

        // minSdk 24：`DocumentFile` / `Intent.FLAG_IMMUTABLE` 与
        // `Settings.ACTION_APP_NOTIFICATION_SETTINGS` 在本项目用到的形态
        // 从 24 起稳定；低于 24 还要额外的兼容分支，本阶段不做。
        minSdk = 24

        // targetSdk 34：前台服务类型（dataSync）与 POST_NOTIFICATIONS
        // 是 33/34 的行为变更，必须按 34 编译才能真正验证到它们。
        targetSdk = 34

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 清空 ndk abiFilters：Flutter 插件会按当前构建架构注入，
        // 与下面的 splits.abi 同时存在会被 AGP 判定为冲突配置而直接失败
        // （实测报 "Conflicting configuration : ... cannot be present when
        // splits abi filters are set"）。split-per-abi 由 splits 决定产物，
        // 因此这里必须显式清空，而不是两边都设。
        ndk {
            abiFilters.clear()
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(signingEnvironment.getValue("LAN_SIMPLE_FILE_KEYSTORE")!!)
                storePassword = signingEnvironment.getValue("LAN_SIMPLE_FILE_STORE_PASSWORD")
                keyAlias = signingEnvironment.getValue("LAN_SIMPLE_FILE_KEY_ALIAS")
                keyPassword = signingEnvironment.getValue("LAN_SIMPLE_FILE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            if (providers.gradleProperty("lanProbe").orNull == "true") {
                applicationIdSuffix = ".probe"
            }
        }
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    // split-per-abi 打包：计划 M7 要求 APK split-per-abi。
    // `flutter build apk --split-per-abi` 会直接产出这几个 ABI 的 APK。
    splits {
        abi {
            isEnable = project.findProperty("split-per-abi") == "true"
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = false
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
    testImplementation("junit:junit:4.13.2")
    // SAF 桥用 DocumentFile 做文档属性查询（1.0.0 与 Flutter 默认依赖链兼容）。
    implementation("androidx.documentfile:documentfile:1.0.0")

    // ForegroundChannelHandler 用 NotificationManagerCompat 查通知开关，
    // 这是 AndroidX 里对「通知是否被用户关掉」最稳的判定，避免各 ROM 的差异。
    implementation("androidx.core:core-ktx:1.12.0")
}
